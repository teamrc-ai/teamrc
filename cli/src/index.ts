#!/usr/bin/env node

import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

import { execFileSync } from "node:child_process";
import { Command } from "commander";
import * as p from "@clack/prompts";
import {
  generateKeypair,
  saveKeypair,
  loadKeypair,
  toToken,
} from "./auth.js";
import { TeamrcClient, remoteTeamToDefinition } from "./client.js";
import {
  loadConfig,
  saveConfig,
  detectPlatforms,
  getRelayUrl,
} from "./config.js";
import { getAdapter, VALID_PLATFORMS, type TeamScope, type TeamDefinition, type PlatformAdapter } from "./adapters/base.js";
import { resolveChange } from "./merge.js";
import { writeTeamYaml, validateTeamName, readTeamYaml, TEAM_YAML } from "./team-yaml.js";
import { resolveTeamSource } from "./resolve-source.js";
import type { TeamrcConfig } from "./config.js";

// ---------------------------------------------------------------------------
// Global options — parsed from root program, threaded through all commands
// ---------------------------------------------------------------------------
interface GlobalOpts {
  json?: boolean;
  yes?: boolean;
  verbose?: boolean;
  color?: boolean;  // Commander flips --no-color → color=false
}

function globals(): GlobalOpts {
  return program.opts() as GlobalOpts;
}

/** True when running in a non-interactive environment. */
function isNonInteractive(): boolean {
  return !process.stdin.isTTY || !!globals().yes;
}

/**
 * Require interactive input or bail with a helpful error message.
 * Pass the flag name that would skip the prompt (e.g. "--yes", "--platform").
 */
function requireTTY(flagHint: string): void {
  if (!process.stdin.isTTY && !globals().yes) {
    p.log.error(
      `This command requires interactive input but stdin is not a TTY.\n` +
      `  Use ${flagHint} to skip this prompt.`,
    );
    process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// Cancel handler — graceful Ctrl-C for all prompts
// ---------------------------------------------------------------------------
function handleCancel(value: unknown): void {
  if (p.isCancel(value)) {
    p.cancel("Cancelled.");
    process.exit(0);
  }
}

// ---------------------------------------------------------------------------
// Platform resolution with clack multiselect
// ---------------------------------------------------------------------------
async function requirePlatforms(override?: string): Promise<string[]> {
  if (override) {
    const requested = override.split(",").map((s) => s.trim()).filter(Boolean);
    for (const pl of requested) {
      if (!VALID_PLATFORMS.includes(pl as typeof VALID_PLATFORMS[number])) {
        p.log.error(`Unknown platform: ${pl}. Valid options: ${VALID_PLATFORMS.join(", ")}`);
        process.exit(1);
      }
    }
    return requested;
  }

  const detected = detectPlatforms();
  if (detected.length === 0) {
    p.log.error(
      "Could not detect platform.\n" +
      "  Ensure a supported platform is installed, or use --platform.",
    );
    process.exit(1);
  }

  if (detected.length === 1 || isNonInteractive()) {
    return detected;
  }

  // Interactive multi-select with detected platforms pre-selected
  const selected = await p.multiselect({
    message: "Which platforms?",
    options: VALID_PLATFORMS.map((pl) => ({
      value: pl,
      label: pl,
      hint: detected.includes(pl) ? "detected" : undefined,
    })),
    initialValues: detected,
    required: true,
  });
  handleCancel(selected);
  return selected as string[];
}

// ---------------------------------------------------------------------------
// Keypair helper
// ---------------------------------------------------------------------------
async function requireKeypair() {
  let kp = loadKeypair();
  if (!kp) {
    kp = await generateKeypair();
    saveKeypair(kp);
    if (globals().verbose) {
      p.log.step("Generated new keypair.");
    }
  }
  return kp;
}

// ---------------------------------------------------------------------------
// Team context resolution
// ---------------------------------------------------------------------------
interface TeamContext {
  team: TeamDefinition;
  scope: TeamScope;
  config: TeamrcConfig;
  client: TeamrcClient;
  platforms: string[];
  adapters: PlatformAdapter[];
}

function requireTeamContext(): TeamContext {
  const config = loadConfig();
  if (!config) {
    p.log.error("Not initialized. Run `teamrc init` first.");
    process.exit(1);
  }
  const kp = loadKeypair();
  if (!kp) {
    p.log.error("No keypair found. Run `teamrc init` first.");
    process.exit(1);
  }

  // 1. Try project-level .teamrc.yaml
  const yamlTeam = readTeamYaml(TEAM_YAML);
  if (yamlTeam?.teamId) {
    const relay = yamlTeam.relay ?? config.relay;
    const platforms = yamlTeam.platforms ?? detectPlatforms();
    const client = new TeamrcClient(relay, kp.privateKey, config.token, yamlTeam.teamId);
    return {
      team: yamlTeam,
      scope: "project",
      config,
      client,
      platforms,
      adapters: platforms.map((pl) => getAdapter(pl)),
    };
  }

  // 2. Fall back to global team
  if (config.globalTeam?.teamId) {
    const platforms = config.globalTeam.platforms;
    const client = new TeamrcClient(config.relay, kp.privateKey, config.token, config.globalTeam.teamId);
    return {
      team: { name: "", members: [], teamId: config.globalTeam.teamId, platforms, noSync: config.globalTeam.noSync },
      scope: "global",
      config,
      client,
      platforms,
      adapters: platforms.map((pl) => getAdapter(pl)),
    };
  }

  // 3. Legacy fallback: top-level teamId in config
  if (config.teamId) {
    const legacyPlatform = config.platform ? config.platform.split(",")[0] : detectPlatforms()[0] ?? "claude-code";
    const platforms = config.platform ? config.platform.split(",") : [legacyPlatform];
    const client = new TeamrcClient(config.relay, kp.privateKey, config.token, config.teamId);
    return {
      team: { name: "", members: [], teamId: config.teamId },
      scope: "project",
      config,
      client,
      platforms,
      adapters: platforms.map((pl) => getAdapter(pl)),
    };
  }

  p.log.error("No team configured. Run `teamrc init` or `teamrc join`.");
  process.exit(1);
}

// ---------------------------------------------------------------------------
// Device auth flow with spinner
// ---------------------------------------------------------------------------
async function deviceAuthFlow(client: TeamrcClient, machineName: string): Promise<boolean> {
  const s = p.spinner();

  let deviceAuth;
  try {
    s.start("Starting device auth...");
    deviceAuth = await client.createDeviceAuth();
    s.stop("Device auth ready.");
  } catch (err) {
    s.error("Failed to start device auth.");
    if (globals().verbose) {
      p.log.error(String(err));
    }
    return false;
  }

  p.note(
    `Open in browser: ${deviceAuth.verification_url}\nEnter code: ${deviceAuth.user_code}`,
    "Authenticate",
  );

  // Try to open browser automatically
  try {
    const openCmd = process.platform === "darwin" ? "open" : "xdg-open";
    execFileSync(openCmd, [deviceAuth.verification_url], { stdio: "ignore" });
  } catch {
    // Ignore - user can open manually
  }

  s.start("Waiting for confirmation... (press Ctrl-C to cancel)");

  const startTime = Date.now();
  const timeoutMs = deviceAuth.expires_in * 1000;
  const intervalMs = deviceAuth.interval * 1000;

  while (Date.now() - startTime < timeoutMs) {
    await new Promise((resolve) => setTimeout(resolve, intervalMs));

    try {
      const result = await client.pollDeviceAuth(deviceAuth.device_code);
      if (result.status === "confirmed") {
        s.stop("Authenticated.");

        p.log.success(`Signed in as ${result.email}`);
        p.log.info(`Machine "${machineName}" linked.`);
        p.log.info(`${result.team_count ?? 0} team(s) across ${result.machine_count ?? 0} machine(s).`);

        // Save account info to config
        const config = loadConfig();
        if (config) {
          saveConfig({
            ...config,
            machineName,
            account: { email: result.email! },
          });
        }
        return true;
      }
    } catch (err) {
      s.error("Polling error.");
      if (globals().verbose) {
        p.log.error(String(err));
      }
      return false;
    }
  }

  s.error("Device authorization timed out. Please try again.");
  return false;
}

// ---------------------------------------------------------------------------
// Scope selection with clack select
// ---------------------------------------------------------------------------
async function selectScope(opts: { scope?: string; global?: boolean }): Promise<TeamScope> {
  if (opts.global) return "global";
  if (opts.scope === "project" || opts.scope === "global") return opts.scope;

  if (isNonInteractive()) return "project";

  const scope = await p.select({
    message: "Where should this team live?",
    options: [
      { value: "project" as TeamScope, label: "This project", hint: "agents in ./<platform>/agents/, checked into git" },
      { value: "global" as TeamScope, label: "Global", hint: "agents in ~/.<platform>/agents/, all projects" },
    ],
    initialValue: "project" as TeamScope,
  });
  handleCancel(scope);
  return scope as TeamScope;
}

// ---------------------------------------------------------------------------
// JSON output helper
// ---------------------------------------------------------------------------
function jsonOutput(data: unknown): void {
  process.stdout.write(JSON.stringify(data, null, 2) + "\n");
}

// ---------------------------------------------------------------------------
// Program definition
// ---------------------------------------------------------------------------
const program = new Command();

program
  .name("teamrc")
  .description("teamrc -- sync multi-agent teams across platforms")
  .version("0.1.0")
  .option("--json", "Output as JSON")
  .option("-y, --yes", "Skip all prompts, use defaults")
  .option("--no-color", "Disable colored output")
  .option("-v, --verbose", "Show detailed output");

// --- init ---
program
  .command("init")
  .description("Initialize teamrc: detect platform, create agents, connect to relay")
  .option("--relay <url>", "Relay server URL")
  .option("--platform <platform>", "Override platform detection")
  .option("--global", "Install as global team (all projects)")
  .option("--name <name>", "Team name")
  .action(async (opts: { relay?: string; platform?: string; global?: boolean; name?: string }) => {
    p.intro("teamrc");

    const platforms = await requirePlatforms(opts.platform);
    const scope = await selectScope(opts);

    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);

    // Read existing team from platform-native files
    const firstAdapter = getAdapter(platforms[0]);
    const existingTeam = firstAdapter.readTeam();
    const team: TeamDefinition = existingTeam ?? {
      name: opts.name ?? "my-team",
      members: [{ name: "agent", role: "General-purpose assistant" }],
    };

    // If --name was provided, override the team name
    if (opts.name && existingTeam) {
      team.name = opts.name;
    }

    if (!existingTeam) {
      p.log.info("No existing agents found. Creating defaults.");
    } else {
      p.log.info(`Found existing team "${team.name}" with ${team.members.length} agent(s).`);
    }

    // Apply to each platform's native format
    const platformSummary: string[] = [];
    for (const pl of platforms) {
      const adapter = getAdapter(pl);
      adapter.writeTeam(team, scope);
      platformSummary.push(pl);
    }
    p.log.step(`Applied to: ${platformSummary.join(", ")}`);

    // Create team on relay
    const s = p.spinner();
    const client = new TeamrcClient(relayUrl, kp.privateKey, token);
    try {
      s.start("Creating team on relay...");
      const relayTeam = await client.createTeam(
        team.name,
        team.members.map((m) => ({ name: m.name, role: m.role, platform: platforms.join(",") })),
      );
      s.stop("Team created.");

      const knowledge = firstAdapter.readKnowledge();
      if (knowledge) {
        await client.push(platforms[0], {
          type: "team-knowledge",
          content: knowledge,
        });
        if (globals().verbose) {
          p.log.step("Pushed team knowledge.");
        }
      }

      // Write YAML with teamId (project mode) or save to global config
      team.teamId = relayTeam.id;
      team.platforms = platforms;

      if (scope === "global") {
        saveConfig({
          relay: relayUrl,
          token,
          globalTeam: { teamId: relayTeam.id, platforms },
        });
      } else {
        team.relay = relayUrl;
        writeTeamYaml(TEAM_YAML, team);
        p.log.step(`Wrote ${TEAM_YAML}`);
        saveConfig({ relay: relayUrl, token });
      }

      // Offer account linking
      if (!isNonInteractive()) {
        const shouldLink = await p.confirm({
          message: "Link your account? (optional, for recovery & dashboard)",
          initialValue: false,
        });
        handleCancel(shouldLink);
        if (shouldLink) {
          const machineName = os.hostname();
          await deviceAuthFlow(client, machineName);
        } else {
          p.log.info("Tip: Run `teamrc login` anytime to link your account.");
        }
      }

      // Create invite for sharing
      let inviteInfo: { invite_code: string; expires_at: string } | null = null;
      try {
        inviteInfo = await client.createInvite(24);
      } catch {
        // invite creation may not be available
      }

      if (inviteInfo) {
        p.note(
          `npx teamrc join ${inviteInfo.invite_code}\nExpires in 24 hours.`,
          "Share with teammates",
        );
      }

      p.outro("Next: Add members to .teamrc.yaml, then run teamrc apply");
    } catch (err) {
      s.error("Failed to create team on relay.");
      p.log.warn(`Relay error: ${(err as Error).message}`);
      saveConfig({ relay: relayUrl, token });
      p.log.info("Configuration saved (relay unreachable).");
      p.outro("Team created locally. Relay sync will resume when available.");
    }
  });

// --- join ---
program
  .command("join")
  .description("Join an existing team and create local agents")
  .argument("<token>", "Team invitation token")
  .option("--relay <url>", "Relay server URL")
  .option("--platform <platform>", "Override platform detection")
  .option("--global", "Join as global team")
  .option("--no-sync", "Join without live sync")
  .action(async (joinToken: string, opts: { relay?: string; platform?: string; global?: boolean; sync?: boolean }) => {
    p.intro("teamrc");

    const noSync = opts.sync === false;
    const platforms = await requirePlatforms(opts.platform);
    const scope = await selectScope(opts);

    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);
    const client = new TeamrcClient(relayUrl, kp.privateKey, token);

    const s = p.spinner();
    try {
      s.start("Joining team...");
      const joinedTeam = await client.joinByInvite(joinToken);
      s.stop(`Joined "${joinedTeam.name}" (${joinedTeam.members.length} members)`);

      const teamDef = remoteTeamToDefinition(joinedTeam);

      // Show members
      if (joinedTeam.members.length > 0) {
        const memberLines = joinedTeam.members.map(
          (m) => `  ${m.name.padEnd(14)} ${m.role}`,
        );
        p.log.info("Members:\n" + memberLines.join("\n"));
      }

      // Apply to each platform
      const s2 = p.spinner();
      s2.start("Applying to detected platforms...");
      const appliedLines: string[] = [];
      for (const pl of platforms) {
        const adapter = getAdapter(pl);
        adapter.writeTeam(teamDef, scope);
        const ruleCount = teamDef.rules?.length ?? 0;
        const detail = ruleCount > 0
          ? `${teamDef.members.length} agents, ${ruleCount} rules`
          : `${teamDef.members.length} agents`;
        appliedLines.push(`  ${pl.padEnd(14)} ${detail}`);
      }
      s2.stop("Applied.");
      p.log.info(appliedLines.join("\n"));

      if (scope === "global") {
        saveConfig({
          relay: relayUrl,
          token,
          globalTeam: { teamId: joinedTeam.id, platforms, ...(noSync ? { noSync: true } : {}) },
        });
      } else {
        teamDef.teamId = joinedTeam.id;
        teamDef.platforms = platforms;
        teamDef.relay = relayUrl;
        if (noSync) teamDef.noSync = true;
        writeTeamYaml(TEAM_YAML, teamDef);
        p.log.step(`Wrote ${TEAM_YAML}`);
        saveConfig({ relay: relayUrl, token });
      }

      if (noSync) {
        p.log.info("Joined without live sync. Use `teamrc sync` for manual sync.");
      } else if (!isNonInteractive()) {
        const shouldLink = await p.confirm({
          message: "Link your account? (optional, for recovery & dashboard)",
          initialValue: false,
        });
        handleCancel(shouldLink);
        if (shouldLink) {
          const machineName = os.hostname();
          await deviceAuthFlow(client, machineName);
        } else {
          p.log.info("Tip: Run `teamrc login` anytime to link your account.");
        }
      }

      p.outro("Next: Run teamrc daemon to start live sync");
    } catch (err) {
      s.error("Failed to join team.");
      p.log.error((err as Error).message);
      process.exit(1);
    }
  });

// --- apply ---
program
  .command("apply")
  .description("Re-apply team agents to local platform native format")
  .option("--platform <platform>", "Override platform detection")
  .option("--scope <scope>", "Team scope: project or global")
  .option("--global", "Install as global team")
  .action(async (opts: { platform?: string; scope?: string; global?: boolean }) => {
    p.intro("teamrc");

    const platforms = await requirePlatforms(opts.platform);

    // Priority: YAML > platform adapters
    const sourceAdapter = getAdapter(platforms[0]);
    const { source, team } = resolveTeamSource(TEAM_YAML, sourceAdapter.readTeam());
    if (!team) {
      p.log.error("No team agents found. Run `teamrc init` or `teamrc join` first.");
      process.exit(1);
    }

    const scope = await selectScope(opts);

    const s = p.spinner();
    s.start(`Applying "${team.name}" to ${platforms.length} platform(s)...`);

    const appliedLines: string[] = [];
    for (const pl of platforms) {
      const adapter = getAdapter(pl);
      adapter.writeTeam(team, scope);
      const ruleCount = team.rules?.length ?? 0;
      const skillCount = team.skills?.length ?? 0;
      const parts = [`${team.members.length} agents`];
      if (ruleCount > 0) parts.push(`${ruleCount} rules`);
      if (skillCount > 0) parts.push(`${skillCount} skills`);
      appliedLines.push(`  ${pl.padEnd(14)} ${parts.join(", ")}`);
    }
    s.stop("Applied.");

    p.log.info(appliedLines.join("\n"));

    // If source was platform, generate the YAML for future use
    if (source === "platform") {
      writeTeamYaml(TEAM_YAML, team);
      p.log.step(`Generated ${TEAM_YAML} from platform agents.`);
    }

    p.outro(`Done. ${team.members.length} agents across ${platforms.length} platform(s).`);
  });

// --- diff ---
program
  .command("diff")
  .description("Show differences between local agents and relay")
  .option("--json", "Output as JSON")
  .action(async (opts: { json?: boolean }) => {
    const useJson = opts.json ?? globals().json;
    const ctx = requireTeamContext();
    const { config, client } = ctx;
    const adapter = ctx.adapters[0];

    const localTeam = adapter.readTeam();
    if (!localTeam) {
      if (useJson) {
        jsonOutput({ error: "no local team agents found" });
      } else {
        p.log.error("No local team agents found.");
      }
      process.exit(1);
    }

    const s = p.spinner();
    try {
      if (!useJson) {
        p.intro("teamrc");
        s.start("Comparing local and relay...");
      }

      const remoteTeam = await client.getTeam(config.token);

      const localAgents = new Map(localTeam.members.map((m) => [m.name, m.role]));
      const remoteAgents = new Map(remoteTeam.members.map((m) => [m.name, m.role]));

      const added: string[] = [];
      const removed: string[] = [];
      const changed: string[] = [];
      const teamNameDiff = localTeam.name !== remoteTeam.name
        ? { local: localTeam.name, remote: remoteTeam.name }
        : null;

      for (const [name, role] of localAgents) {
        if (!remoteAgents.has(name)) {
          added.push(name);
        } else if (remoteAgents.get(name) !== role) {
          changed.push(name);
        }
      }

      for (const [name] of remoteAgents) {
        if (!localAgents.has(name)) {
          removed.push(name);
        }
      }

      if (useJson) {
        const result: Record<string, unknown> = { added, removed, changed };
        if (teamNameDiff) result.teamName = teamNameDiff;
        jsonOutput(result);
        return;
      }

      s.stop(`Comparing local <-> relay for "${localTeam.name}"`);

      const totalDiffs = added.length + removed.length + changed.length + (teamNameDiff ? 1 : 0);

      if (totalDiffs === 0) {
        p.log.success("No differences between local and relay.");
        p.outro("Everything in sync.");
        return;
      }

      const diffLines: string[] = [];
      if (teamNameDiff) {
        diffLines.push(`  ~ team name: "${teamNameDiff.local}" (local) vs "${teamNameDiff.remote}" (relay)`);
      }
      for (const name of added) {
        diffLines.push(`  + ${name} (${localAgents.get(name)})  local only`);
      }
      for (const name of changed) {
        diffLines.push(`  ~ ${name}: "${localAgents.get(name)}" -> "${remoteAgents.get(name)}"`);
      }
      for (const name of removed) {
        diffLines.push(`  - ${name} (${remoteAgents.get(name)})  relay only`);
      }

      p.log.info("Members\n" + diffLines.join("\n"));
      p.outro(`${totalDiffs} difference(s). Run teamrc sync to resolve.`);
    } catch (err) {
      if (!useJson) s.error("Failed to fetch relay state.");
      if (useJson) {
        jsonOutput({ error: (err as Error).message });
      } else {
        p.log.error((err as Error).message);
      }
      process.exit(1);
    }
  });

// --- sync ---
program
  .command("sync")
  .description("Sync with relay server")
  .action(async () => {
    p.intro("teamrc");

    const ctx = requireTeamContext();
    const { client } = ctx;
    const platform = ctx.platforms[0];
    const adapter = ctx.adapters[0];

    if (!adapter.supportsSync) {
      p.log.error(`Sync is not supported for ${platform}. Use \`teamrc apply\` to apply team changes.`);
      process.exit(1);
    }

    const s = p.spinner();
    try {
      s.start("Syncing with relay...");
      const hashes = adapter.getHashes();
      const result = await client.sync(platform, hashes);

      const entries = Object.entries(result.changes);
      if (entries.length > 0) {
        let applied = 0;
        const changeLines: string[] = [];
        for (const [key, remoteChange] of entries) {
          const localContent = adapter.readFile(key);
          const localMtime = adapter.getFileMtime(key);
          const merged = resolveChange(key, localContent, remoteChange, localMtime);
          if (merged.warning) {
            p.log.warn(merged.warning);
          }
          if (merged.action !== "keep-local") {
            adapter.writeFile(key, merged.content);
            applied++;
            changeLines.push(`  Applied: ${key}`);
          } else {
            changeLines.push(`  Kept local: ${key}`);
          }
        }
        s.stop("Synced.");
        if (globals().verbose && changeLines.length > 0) {
          p.log.info(changeLines.join("\n"));
        }
        p.outro(`${applied} of ${entries.length} change(s) applied.`);
      } else {
        s.stop("Already up to date.");
        p.outro("No changes.");
      }
    } catch (err) {
      s.error("Sync failed.");
      p.log.error((err as Error).message);
      p.log.info(
        "Your machine's token may not be registered with this team.\n" +
        "  To fix: Run `teamrc join <invite-code>` to re-register.",
      );
      process.exit(1);
    }
  });

// --- push ---
program
  .command("push")
  .description("Push local knowledge to relay")
  .action(async () => {
    p.intro("teamrc");

    const ctx = requireTeamContext();
    const { client } = ctx;
    const platform = ctx.platforms[0];
    const adapter = ctx.adapters[0];

    try {
      const knowledge = adapter.readKnowledge();
      if (!knowledge) {
        p.log.info("No team knowledge to push.");
        p.outro("Nothing to do.");
        return;
      }

      const s = p.spinner();
      s.start("Pushing team knowledge...");
      await client.push(platform, {
        type: "team-knowledge",
        content: knowledge,
      });
      s.stop("Pushed team knowledge.");
      p.outro("Done.");
    } catch (err) {
      p.log.error(`Push failed: ${(err as Error).message}`);
      process.exit(1);
    }
  });

// --- status ---
program
  .command("status")
  .description("Show current configuration and sync state")
  .option("--json", "Output as JSON")
  .action(async (opts: { json?: boolean }) => {
    const useJson = opts.json ?? globals().json;
    const config = loadConfig();

    if (!config) {
      if (useJson) {
        jsonOutput({ error: "not initialized" });
      } else {
        p.intro("teamrc");
        p.log.warn("teamrc is not initialized.");
        p.outro("Run `teamrc init` to get started.");
      }
      return;
    }

    const teamId = config.teamId ?? config.globalTeam?.teamId ?? null;
    const platformStr = config.platform ?? config.globalTeam?.platforms?.join(",") ?? detectPlatforms()[0] ?? "claude-code";
    const activePlatform = platformStr.split(",")[0];
    const adapter = getAdapter(activePlatform);
    const localTeam = adapter.readTeam();

    // Check relay state
    let remoteTeam = null;
    let relayConnected = false;
    if (teamId) {
      const kp = loadKeypair();
      if (kp) {
        const client = new TeamrcClient(config.relay, kp.privateKey, config.token);
        try {
          remoteTeam = await client.getTeam(config.token);
          relayConnected = true;
        } catch {
          // relay unreachable
        }
      }
    }

    if (useJson) {
      jsonOutput({
        machine: config.machineName ?? os.hostname(),
        token: config.token.slice(0, 12) + "...",
        relay: { url: config.relay, connected: relayConnected },
        account: config.account?.email ?? null,
        platform: platformStr,
        teamId,
        localTeam: localTeam ?? null,
        remoteTeam: remoteTeam ?? null,
      });
      return;
    }

    p.intro("teamrc");

    // Machine identity block
    const identityLines = [
      `Machine   ${config.machineName ?? os.hostname()}`,
      `Identity  ${config.token.slice(0, 12)}...`,
      `Relay     ${config.relay}  ${relayConnected ? "connected" : "unreachable"}`,
    ];
    if (config.account?.email) {
      identityLines.push(`Account   ${config.account.email}`);
    }
    p.log.info(identityLines.join("\n"));

    // Local team info
    if (localTeam) {
      const memberLines = localTeam.members.map(
        (m) => `  ${m.name.padEnd(14)} ${m.role}`,
      );
      p.note(
        [
          `Team ID    ${teamId ?? "none"}`,
          `Platforms  ${platformStr}`,
          `Members    ${localTeam.members.length} agents`,
          ...memberLines,
        ].join("\n"),
        `Local team: ${localTeam.name}`,
      );
    } else {
      p.log.warn("No local team agents found.");
    }

    // Remote team info
    if (remoteTeam) {
      const memberLines = remoteTeam.members.map(
        (m) => `  ${m.name.padEnd(14)} ${m.role} (${m.platform ?? "all"})`,
      );
      p.note(
        memberLines.join("\n"),
        `Relay team: ${remoteTeam.name}`,
      );
    } else if (teamId) {
      p.log.warn("Relay unreachable.");
    }

    p.outro("");
  });

// --- daemon ---
program
  .command("daemon")
  .description("Start the background sync daemon")
  .option("--poll-interval <ms>", "Poll interval in milliseconds", "120000")
  .option("--sync-mode <mode>", "What to sync: all, knowledge, none", "knowledge")
  .action(async (opts: { pollInterval: string; syncMode: string }) => {
    const ctx = requireTeamContext();
    const { client } = ctx;
    const platform = ctx.platforms[0];
    const adapter = ctx.adapters[0];

    if (!adapter.supportsSync) {
      p.log.error(`Daemon sync is not supported for ${platform}. Use \`teamrc apply\` to apply team changes.`);
      process.exit(1);
    }

    const validModes = ["all", "knowledge", "none"];
    if (!validModes.includes(opts.syncMode)) {
      p.log.error(`Invalid sync mode: ${opts.syncMode}. Valid options: ${validModes.join(", ")}`);
      process.exit(1);
    }

    p.intro("teamrc daemon");
    p.log.info([
      `Watching "${ctx.team.name || "team"}" on ${ctx.platforms.join(", ")}`,
      `Sync mode: ${opts.syncMode}`,
      `Poll interval: ${parseInt(opts.pollInterval, 10) / 1000}s`,
    ].join("\n"));

    const { startDaemon } = await import("./daemon.js");
    const daemon = startDaemon({
      adapter,
      client,
      platform,
      pollInterval: parseInt(opts.pollInterval, 10),
      syncMode: opts.syncMode as "all" | "knowledge" | "none",
    });

    // Graceful shutdown
    const shutdown = () => {
      daemon.stop();
      p.outro("Daemon stopped.");
      process.exit(0);
    };
    process.on("SIGINT", shutdown);
    process.on("SIGTERM", shutdown);
  });

// --- export ---
program
  .command("export")
  .description("Export team from relay to .teamrc.yaml")
  .action(async () => {
    p.intro("teamrc");

    const ctx = requireTeamContext();
    const { config, client } = ctx;

    const s = p.spinner();
    try {
      s.start("Fetching team from relay...");
      const remoteTeam = await client.getTeam(config.token);
      validateTeamName(remoteTeam.name);
      const team = remoteTeamToDefinition(remoteTeam);
      writeTeamYaml(TEAM_YAML, team);
      s.stop(`Exported "${team.name}" (${team.members.length} agents) to ${TEAM_YAML}.`);
      p.outro("Done.");
    } catch (err) {
      s.error("Failed to fetch team from relay.");
      p.log.error((err as Error).message);
      process.exit(1);
    }
  });

// --- pull ---
program
  .command("pull")
  .description("Pull team from relay and apply to local platforms")
  .option("--platform <platform>", "Override platform detection")
  .option("--scope <scope>", "Team scope: project or global")
  .option("--global", "Pull as global team")
  .action(async (opts: { platform?: string; scope?: string; global?: boolean }) => {
    p.intro("teamrc");

    const ctx = requireTeamContext();
    const { config, client } = ctx;
    const platforms = await requirePlatforms(opts.platform);
    const scope = await selectScope(opts);

    const s = p.spinner();
    try {
      s.start("Pulling from relay...");
      const remoteTeam = await client.getTeam(config.token);
      validateTeamName(remoteTeam.name);
      const team = remoteTeamToDefinition(remoteTeam);

      writeTeamYaml(TEAM_YAML, team);
      s.stop(`Pulled "${team.name}" (${team.members.length} agents).`);

      // Apply to platforms
      for (const pl of platforms) {
        const adapter = getAdapter(pl);
        adapter.writeTeam(team, scope);
        p.log.step(`Applied to ${pl} (${scope} scope).`);
      }

      p.outro("Done.");
    } catch (err) {
      s.error("Pull failed.");
      p.log.error((err as Error).message);
      process.exit(1);
    }
  });

// --- login ---
program
  .command("login")
  .description("Link this machine to your teamrc account")
  .option("--name <machine-name>", "Machine name (defaults to hostname)")
  .action(async (opts: { name?: string }) => {
    p.intro("teamrc");

    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const config = loadConfig();
    const relayUrl = config?.relay ?? getRelayUrl();
    const client = new TeamrcClient(relayUrl, kp.privateKey, token);
    const machineName = opts.name ?? os.hostname();

    const success = await deviceAuthFlow(client, machineName);
    if (success) {
      p.outro("Account linked.");
    } else {
      p.outro("Login failed.");
      process.exit(1);
    }
  });

// --- clone ---
program
  .command("clone")
  .description("Clone a team locally from an invite code without joining")
  .argument("<invite-code>", "Team invitation code")
  .option("--relay <url>", "Relay server URL")
  .option("--platform <platform>", "Override platform detection")
  .option("--scope <scope>", "Team scope: project or global")
  .option("--global", "Clone as global team")
  .option("--name <name>", "Override team name")
  .action(async (inviteCode: string, opts: { relay?: string; platform?: string; scope?: string; global?: boolean; name?: string }) => {
    p.intro("teamrc");

    const platforms = await requirePlatforms(opts.platform);
    const scope = await selectScope(opts);

    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);
    const client = new TeamrcClient(relayUrl, kp.privateKey, token);

    const s = p.spinner();
    try {
      s.start("Fetching team preview...");
      const previewTeam = await client.previewByInvite(inviteCode);
      const teamDef = remoteTeamToDefinition(previewTeam);
      s.stop(`Found "${teamDef.name}" (${teamDef.members.length} agents).`);

      if (opts.name) {
        validateTeamName(opts.name);
        teamDef.name = opts.name;
      }

      // Write canonical YAML
      writeTeamYaml(TEAM_YAML, teamDef);
      p.log.step(`Wrote ${TEAM_YAML}`);

      // Apply to each platform
      for (const pl of platforms) {
        const adapter = getAdapter(pl);
        adapter.writeTeam(teamDef, scope);
        p.log.step(`${pl} configured.`);
      }

      p.log.success(`Cloned "${teamDef.name}" (${teamDef.members.length} agents) locally.`);
      p.outro("This is a local copy. Run `teamrc init` to create your own synced team.");
    } catch (err) {
      s.error("Failed to clone team.");
      p.log.error((err as Error).message);
      process.exit(1);
    }
  });

// --- invite ---
program
  .command("invite")
  .description("Create an invite code for the current team")
  .option("--ttl <hours>", "Invite expiry in hours", "24")
  .action(async (opts: { ttl: string }) => {
    p.intro("teamrc");

    const ctx = requireTeamContext();
    const { client } = ctx;
    const ttlHours = parseInt(opts.ttl, 10);

    if (isNaN(ttlHours) || ttlHours < 1) {
      p.log.error("TTL must be a positive number of hours.");
      process.exit(1);
    }

    const s = p.spinner();
    try {
      s.start("Creating invite...");
      const result = await client.createInvite(ttlHours);
      s.stop("Invite created.");

      const teamName = ctx.team.name || "your team";
      p.note(
        `npx teamrc join ${result.invite_code}\n\nTeam:    ${teamName}\nExpires: ${ttlHours} hours`,
        "Invite",
      );

      p.outro("Share this command with your teammates.");
    } catch (err) {
      s.error("Failed to create invite.");
      p.log.error((err as Error).message);
      process.exit(1);
    }
  });

// --- whoami ---
program
  .command("whoami")
  .description("Show current identity and configuration")
  .option("--json", "Output as JSON")
  .action((opts: { json?: boolean }) => {
    const useJson = opts.json ?? globals().json;
    const config = loadConfig();

    if (!config) {
      if (useJson) {
        jsonOutput({ error: "not initialized" });
      } else {
        p.log.warn("teamrc is not initialized.");
      }
      return;
    }

    const whoamiTeamId = config.teamId ?? config.globalTeam?.teamId ?? "none";
    const whoamiPlatform = config.platform ?? config.globalTeam?.platforms?.join(",") ?? "none";

    if (useJson) {
      jsonOutput({
        token: config.token.slice(0, 16) + "...",
        machine: config.machineName ?? "unknown",
        account: config.account?.email ?? "not linked",
        teamId: whoamiTeamId,
        relay: config.relay,
        platform: whoamiPlatform,
      });
      return;
    }

    p.log.info([
      `Token:    ${config.token.slice(0, 16)}...`,
      `Machine:  ${config.machineName ?? "unknown"}`,
      `Account:  ${config.account?.email ?? "not linked"}`,
      `Team ID:  ${whoamiTeamId}`,
      `Relay:    ${config.relay}`,
      `Platform: ${whoamiPlatform}`,
    ].join("\n"));
  });

// --- log ---
program
  .command("log")
  .description("Show recent sync activity")
  .option("--limit <n>", "Number of entries to show", "20")
  .option("--json", "Output as JSON")
  .action(async (opts: { limit: string; json?: boolean }) => {
    const useJson = opts.json ?? globals().json;
    const ctx = requireTeamContext();
    const { client } = ctx;
    const limit = parseInt(opts.limit, 10) || 20;

    const s = p.spinner();
    try {
      if (!useJson) {
        p.intro(`teamrc log -- ${ctx.team.name || "team"}`);
        s.start("Fetching log...");
      }

      const entries = await client.getLog();
      const sliced = entries.slice(0, limit);

      if (useJson) {
        jsonOutput(sliced);
        return;
      }

      s.stop(`${sliced.length} entries.`);

      if (sliced.length === 0) {
        p.log.info("No recent sync activity.");
        p.outro("");
        return;
      }

      const logLines = sliced.map((entry) => {
        const pushedBy = entry.pushed_by
          ? entry.pushed_by.length > 16
            ? entry.pushed_by.slice(0, 16) + "..."
            : entry.pushed_by
          : "unknown";
        return `  ${entry.timestamp}  ${entry.type.padEnd(10)} ${pushedBy.padEnd(20)} ${entry.source_platform}`;
      });
      p.log.info(logLines.join("\n"));

      p.outro(`Use --limit to show more.`);
    } catch (err) {
      if (!useJson) s.error("Failed to fetch log.");
      if (useJson) {
        jsonOutput({ error: (err as Error).message });
      } else {
        p.log.error((err as Error).message);
      }
      process.exit(1);
    }
  });

// --- doctor ---
program
  .command("doctor")
  .description("Check teamrc setup and connectivity")
  .action(async () => {
    p.intro("teamrc doctor");

    let passed = 0;
    let warnings = 0;
    let failures = 0;

    // 1. Keypair check
    const kp = loadKeypair();
    if (kp) {
      p.log.success("Keypair found");
      passed++;
    } else {
      p.log.error("No keypair");
      failures++;
    }

    // 2. Config check
    const config = loadConfig();
    if (config) {
      p.log.success("Config valid");
      passed++;
    } else {
      p.log.error("No config");
      failures++;
    }

    // 3. Relay reachable
    if (config) {
      try {
        const start = Date.now();
        await fetch(`${config.relay}/api/sync/check?token=test&since=0`);
        const ms = Date.now() - start;
        p.log.success(`Relay reachable (${ms}ms)`);
        passed++;
      } catch {
        p.log.error("Relay unreachable");
        failures++;
      }
    }

    // 4. .teamrc.yaml check
    const yamlTeam = readTeamYaml(TEAM_YAML);
    if (yamlTeam) {
      p.log.success(`${TEAM_YAML} found (${yamlTeam.members.length} members)`);
      passed++;
    } else {
      p.log.warn(`No ${TEAM_YAML}`);
      warnings++;
    }

    // 5. Platform agents match
    if (config && yamlTeam) {
      const doctorPlatform = config.platform
        ? config.platform.split(",")[0]
        : (config.globalTeam?.platforms?.[0] ?? detectPlatforms()[0] ?? "claude-code");
      const adapter = getAdapter(doctorPlatform);
      const platformTeam = adapter.readTeam();
      if (platformTeam) {
        const yamlCount = yamlTeam.members.length;
        const platformCount = platformTeam.members.length;
        if (yamlCount === platformCount) {
          p.log.success(`${yamlCount} agents synced (${yamlCount} local = ${yamlCount} platform)`);
          passed++;
        } else {
          p.log.warn(`Mismatch: YAML has ${yamlCount}, platform has ${platformCount}`);
          warnings++;
        }
      } else {
        p.log.warn("Mismatch: YAML has agents, platform has none");
        warnings++;
      }
    }

    // 6. Account check
    if (config?.account?.email) {
      p.log.success(`Account: ${config.account.email}`);
      passed++;
    } else {
      p.log.info("Account not linked (optional)");
    }

    const summary = `${passed} passed, ${warnings} warnings, ${failures} failures`;
    if (failures === 0) {
      p.outro(`${summary}. Everything looks good.`);
    } else {
      p.outro(summary);
    }
  });

// --- delete ---
program
  .command("delete")
  .description("Remove teamrc from this machine")
  .option("-y, --yes", "Skip confirmation prompt")
  .action(async (opts: { yes?: boolean }) => {
    p.intro("teamrc");

    const config = loadConfig();
    if (!config) {
      p.log.info("teamrc is not initialized. Nothing to remove.");
      p.outro("");
      return;
    }

    const platforms = config.platform ? config.platform.split(",") : (config.globalTeam?.platforms ?? detectPlatforms());

    // Determine team name for confirmation
    let teamName: string | null = null;
    const yamlTeam = readTeamYaml(TEAM_YAML);
    if (yamlTeam?.name) {
      teamName = yamlTeam.name;
    }

    p.log.warn(
      "This will remove all teamrc agents, rules, skills, and knowledge\n" +
      "from this machine. Other team members keep their setup.",
    );

    const skipConfirm = opts.yes ?? globals().yes;
    if (!skipConfirm) {
      if (teamName) {
        // Type team name to confirm
        requireTTY("--yes");
        const confirmation = await p.text({
          message: `Type "${teamName}" to confirm deletion:`,
          validate: (value) => {
            if (value !== teamName) return `Please type "${teamName}" to confirm.`;
          },
        });
        handleCancel(confirmation);
      } else {
        requireTTY("--yes");
        const shouldDelete = await p.confirm({
          message: "Remove teamrc from this machine?",
          initialValue: false,
        });
        handleCancel(shouldDelete);
        if (!shouldDelete) {
          p.cancel("Cancelled.");
          return;
        }
      }
    }

    const s = p.spinner();
    s.start("Removing...");

    const actionLines: string[] = [];

    // Uninstall from each platform
    for (const pl of platforms) {
      const adapter = getAdapter(pl);
      const actions = adapter.uninstall();
      for (const action of actions) {
        actionLines.push(action);
      }
    }

    // Delete ~/.teamrc/ config
    const configDir = path.join(os.homedir(), ".teamrc");
    if (fs.existsSync(configDir)) {
      fs.rmSync(configDir, { recursive: true });
      actionLines.push(`Deleted ${configDir}`);
    }

    // Delete .teamrc.yaml if present
    if (fs.existsSync(TEAM_YAML)) {
      fs.unlinkSync(TEAM_YAML);
      actionLines.push(`Deleted ${TEAM_YAML}`);
    }

    s.stop("Removed.");

    if (actionLines.length > 0 && globals().verbose) {
      p.log.info(actionLines.map((a) => `  ${a}`).join("\n"));
    }

    p.outro("Done. Run `teamrc init` or `teamrc join` to set up again.");
  });

program.parse();
