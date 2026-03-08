#!/usr/bin/env node

import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

import * as readline from "node:readline";
import { execFileSync } from "node:child_process";
import { Command } from "commander";
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

function askQuestion(question: string): Promise<string> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
  });
  return new Promise((resolve) => {
    rl.question(question, (answer) => {
      rl.close();
      resolve(answer.trim());
    });
  });
}

async function askScope(platform: string): Promise<TeamScope> {
  if (platform !== "claude-code") {
    return "global";
  }

  console.log("\nWhere should this team be available?");
  console.log("  1) This project only (creates agents in .claude/agents/ and updates CLAUDE.md)");
  console.log("  2) All projects (creates agents in ~/.claude/agents/)");
  const answer = await askQuestion("\nChoice [1/2]: ");

  if (answer === "2") {
    return "global";
  }
  return "project";
}

async function requirePlatforms(override?: string): Promise<string[]> {
  const valid = ["claude-code", "openclaw", "cursor", "codex", "gemini"];
  if (override) {
    const requested = override.split(",").map((s) => s.trim()).filter(Boolean);
    for (const p of requested) {
      if (!valid.includes(p)) {
        console.error(`Unknown platform: ${p}. Valid options: ${valid.join(", ")}`);
        process.exit(1);
      }
    }
    return requested;
  }
  const platforms = detectPlatforms();
  if (platforms.length === 0) {
    console.error(
      "Could not detect platform. Ensure a supported platform is installed (claude-code, cursor, codex, gemini, openclaw), or use --platform.",
    );
    process.exit(1);
  }
  if (platforms.length === 1) {
    return platforms;
  }

  // Multiple platforms detected — ask the user
  console.log("\nMultiple platforms detected:");
  for (let i = 0; i < platforms.length; i++) {
    console.log(`  ${i + 1}) ${platforms[i]}`);
  }
  console.log(`  ${platforms.length + 1}) All detected`);
  const answer = await askQuestion(`\nWhich platform? [1-${platforms.length + 1}]: `);
  const choice = parseInt(answer, 10);
  if (choice >= 1 && choice <= platforms.length) {
    return [platforms[choice - 1]];
  }
  if (choice === platforms.length + 1) {
    return platforms;
  }
  return [platforms[0]];
}

/** Get the first platform from a possibly comma-separated config value. */
function primaryPlatform(platformStr: string): string {
  return platformStr.split(",")[0];
}

async function requireKeypair() {
  let kp = loadKeypair();
  if (!kp) {
    kp = await generateKeypair();
    saveKeypair(kp);
    console.log("Generated new keypair.");
  }
  return kp;
}

interface TeamContext {
  team: TeamDefinition;
  scope: TeamScope;
  config: TeamrcConfig;
  client: TeamrcClient;
  platforms: string[];
  adapters: PlatformAdapter[];
}

/** Resolve team context from project YAML or global config. */
function requireTeamContext(): TeamContext {
  const config = loadConfig();
  if (!config) {
    console.error("Not initialized. Run `teamrc init` first.");
    process.exit(1);
  }
  const kp = loadKeypair();
  if (!kp) {
    console.error("No keypair found.");
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
      adapters: platforms.map((p) => getAdapter(p)),
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
      adapters: platforms.map((p) => getAdapter(p)),
    };
  }

  // 3. Legacy fallback: top-level teamId in config
  if (config.teamId) {
    const platform = config.platform ? primaryPlatform(config.platform) : detectPlatforms()[0] ?? "claude-code";
    const platforms = config.platform ? config.platform.split(",") : [platform];
    const client = new TeamrcClient(config.relay, kp.privateKey, config.token, config.teamId);
    return {
      team: { name: "", members: [], teamId: config.teamId },
      scope: "project",
      config,
      client,
      platforms,
      adapters: platforms.map((p) => getAdapter(p)),
    };
  }

  console.error("No team configured. Run `teamrc init` or `teamrc join`.");
  process.exit(1);
}

/** Legacy helper — wraps requireTeamContext for commands that need single adapter */
function requireClient(): { config: TeamrcConfig & { teamId: string }; client: TeamrcClient; platform: string; adapter: PlatformAdapter } {
  const ctx = requireTeamContext();
  return {
    config: { ...ctx.config, teamId: ctx.team.teamId! } as TeamrcConfig & { teamId: string },
    client: ctx.client,
    platform: ctx.platforms[0],
    adapter: ctx.adapters[0],
  };
}

async function deviceAuthFlow(client: TeamrcClient, machineName: string): Promise<boolean> {
  let deviceAuth;
  try {
    deviceAuth = await client.createDeviceAuth();
  } catch (err) {
    console.error("Failed to start device auth:", err);
    return false;
  }

  console.log(`\n  Open in browser: ${deviceAuth.verification_url}`);
  console.log(`  Enter code: ${deviceAuth.user_code}\n`);

  // Try to open browser automatically
  try {
    const openCmd = process.platform === "darwin" ? "open" : "xdg-open";
    execFileSync(openCmd, [deviceAuth.verification_url], { stdio: "ignore" });
  } catch {
    // Ignore — user can open manually
  }

  console.log("  Waiting for confirmation... (press Ctrl+C to cancel)\n");

  const startTime = Date.now();
  const timeoutMs = deviceAuth.expires_in * 1000;
  const intervalMs = deviceAuth.interval * 1000;

  while (Date.now() - startTime < timeoutMs) {
    await new Promise((resolve) => setTimeout(resolve, intervalMs));

    try {
      const result = await client.pollDeviceAuth(deviceAuth.device_code);
      if (result.status === "confirmed") {
        console.log(`  Signed in as ${result.email}`);
        console.log(`  Machine "${machineName}" linked.`);
        console.log(`  ${result.team_count ?? 0} team(s) across ${result.machine_count ?? 0} machine(s).`);

        // Save account info to config
        const config = loadConfig();
        if (config) {
          saveConfig({
            ...config,
            machineName,
            account: {
              email: result.email!,
            },
          });
        }
        return true;
      }
    } catch (err) {
      console.error("Polling error:", err);
      return false;
    }
  }

  console.error("Device authorization timed out. Please try again.");
  return false;
}

const program = new Command();

program
  .name("teamrc")
  .description("teamrc — sync multi-agent teams across platforms")
  .version("0.1.0");

// --- init ---
program
  .command("init")
  .description("Initialize teamrc: detect platform, create agents, connect to relay")
  .option("--relay <url>", "Relay server URL")
  .option("--platform <platform>", "Override platform detection")
  .option("--global", "Install as global team (all projects)")
  .action(async (opts: { relay?: string; platform?: string; global?: boolean }) => {
    const platforms = await requirePlatforms(opts.platform);
    const scope: TeamScope = opts.global ? "global" : "project";

    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);

    // Read existing team from platform-native files
    const firstAdapter = getAdapter(platforms[0]);
    const existingTeam = firstAdapter.readTeam();
    const team: TeamDefinition = existingTeam ?? {
      name: "my-team",
      members: [{ name: "agent", role: "General-purpose assistant" }],
    };

    if (!existingTeam) {
      console.log("No existing agents found. Creating defaults.");
    } else {
      console.log(`Found existing team "${team.name}" with ${team.members.length} agent(s).`);
    }

    // Apply to each platform's native format
    for (const p of platforms) {
      console.log(`Setting up ${p}...`);
      const adapter = getAdapter(p);
      adapter.writeTeam(team, scope);
      console.log(`  ${p} configured.`);
    }

    // Create team on relay
    const client = new TeamrcClient(relayUrl, kp.privateKey, token);
    try {
      const relayTeam = await client.createTeam(
        team.name,
        team.members.map((m) => ({ name: m.name, role: m.role, platform: platforms.join(",") })),
      );
      console.log(`Team created on relay: ${relayTeam.id}`);

      const knowledge = firstAdapter.readKnowledge();
      if (knowledge) {
        await client.push(platforms[0], {
          type: "team-knowledge",
          content: knowledge,
        });
        console.log("Pushed team knowledge.");
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
        console.log(`Wrote ${TEAM_YAML}.`);
        saveConfig({ relay: relayUrl, token });
      }
      console.log("Configuration saved.");
      console.log(`\nShare this token to invite others: ${token}`);

      // Offer account linking
      const linkAnswer = await askQuestion("\nLink your account for recovery and dashboard access?\n[Y/n]: ");
      if (linkAnswer.toLowerCase() !== "n") {
        const machineName = os.hostname();
        await deviceAuthFlow(client, machineName);
      } else {
        console.log("Tip: Run `teamrc login` anytime to link your account.");
      }
    } catch (err) {
      console.error("Failed to initialize with relay:", (err as Error).message);
      saveConfig({ relay: relayUrl, token });
      console.log("Configuration saved (relay unreachable).");
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
    const noSync = opts.sync === false;
    const platforms = await requirePlatforms(opts.platform);
    const scope: TeamScope = opts.global ? "global" : "project";

    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);
    const client = new TeamrcClient(relayUrl, kp.privateKey, token);

    try {
      const joinedTeam = await client.joinByInvite(joinToken);
      console.log(`Joined team: ${joinedTeam.name}`);

      const teamDef = remoteTeamToDefinition(joinedTeam);

      // Apply to each platform's native format
      for (const p of platforms) {
        console.log(`Setting up ${p}...`);
        const adapter = getAdapter(p);
        adapter.writeTeam(teamDef, scope);
        console.log(`  ${p} configured.`);
      }

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
        console.log(`Wrote ${TEAM_YAML}.`);
        saveConfig({ relay: relayUrl, token });
      }
      console.log("Configuration saved.");

      if (noSync) {
        console.log("Joined without live sync. Use `teamrc sync` for manual sync.");
      } else {
        // Offer account linking
        const linkAnswer = await askQuestion("\nLink your account for recovery and dashboard access?\n[Y/n]: ");
        if (linkAnswer.toLowerCase() !== "n") {
          const machineName = os.hostname();
          await deviceAuthFlow(client, machineName);
        } else {
          console.log("Tip: Run `teamrc login` anytime to link your account.");
        }
      }
    } catch (err) {
      console.error("Failed to join team:", (err as Error).message);
      process.exit(1);
    }
  });

// --- apply ---
program
  .command("apply")
  .description("Re-apply team agents to local platform native format")
  .option("--platform <platform>", "Override platform detection (claude-code, cursor, codex, gemini, openclaw)")
  .option("--scope <scope>", "Team scope: project or global")
  .action(async (opts: { platform?: string; scope?: string }) => {
    const platforms = await requirePlatforms(opts.platform);

    // Priority: YAML > platform adapters
    const sourceAdapter = getAdapter(platforms[0]);
    const { source, team } = resolveTeamSource(TEAM_YAML, sourceAdapter.readTeam());
    if (!team) {
      console.error("No team agents found. Run `teamrc init` or `teamrc join` first.");
      process.exit(1);
    }

    console.log(`Using team from ${source}${source === "yaml" ? ` (${TEAM_YAML})` : ""}.`);

    for (const p of platforms) {
      const scope: TeamScope = opts.scope === "project" || opts.scope === "global"
        ? opts.scope
        : await askScope(p);

      const adapter = getAdapter(p);
      adapter.writeTeam(team, scope);
      console.log(`Applied "${team.name}" (${team.members.length} agents) to ${p} (${scope} scope).`);
    }

    // If source was platform, generate the YAML for future use
    if (source === "platform") {
      writeTeamYaml(TEAM_YAML, team);
      console.log(`Generated ${TEAM_YAML} from platform agents.`);
    }
  });

// --- diff ---
program
  .command("diff")
  .description("Show differences between local agents and relay")
  .option("--json", "Output as JSON")
  .action(async (opts: { json?: boolean }) => {
    const { config, client, adapter } = requireClient();
    const localTeam = adapter.readTeam();
    if (!localTeam) {
      console.error("No local team agents found.");
      process.exit(1);
    }

    try {
      const remoteTeam = await client.getTeam(config.token);

      const localAgents = new Map(localTeam.members.map((m) => [m.name, m.role]));
      const remoteAgents = new Map(remoteTeam.members.map((m) => [m.name, m.role]));

      const added: string[] = [];
      const removed: string[] = [];
      const changed: string[] = [];
      const teamNameDiff = localTeam.name !== remoteTeam.name
        ? { local: localTeam.name, remote: remoteTeam.name }
        : null;

      // Agents only in local or changed
      for (const [name, role] of localAgents) {
        if (!remoteAgents.has(name)) {
          added.push(name);
        } else if (remoteAgents.get(name) !== role) {
          changed.push(name);
        }
      }

      // Agents only on relay
      for (const [name] of remoteAgents) {
        if (!localAgents.has(name)) {
          removed.push(name);
        }
      }

      if (opts.json) {
        const result: Record<string, unknown> = { added, removed, changed };
        if (teamNameDiff) {
          result.teamName = teamNameDiff;
        }
        console.log(JSON.stringify(result, null, 2));
        return;
      }

      let hasDiff = false;

      if (teamNameDiff) {
        console.log(`  team name: "${teamNameDiff.local}" (local) vs "${teamNameDiff.remote}" (relay)`);
        hasDiff = true;
      }

      for (const name of added) {
        console.log(`  + ${name} (${localAgents.get(name)}) — local only`);
        hasDiff = true;
      }

      for (const name of changed) {
        console.log(`  ~ ${name}: role "${localAgents.get(name)}" (local) vs "${remoteAgents.get(name)}" (relay)`);
        hasDiff = true;
      }

      for (const name of removed) {
        console.log(`  - ${name} (${remoteAgents.get(name)}) — relay only`);
        hasDiff = true;
      }

      if (!hasDiff) {
        console.log("No differences between local and relay.");
      }
    } catch (err) {
      console.error("Failed to fetch relay state:", (err as Error).message);
      process.exit(1);
    }
  });

// --- sync ---
program
  .command("sync")
  .description("Sync with relay server")
  .action(async () => {
    const { client, platform, adapter } = requireClient();

    if (!adapter.supportsSync) {
      console.error(`Sync is not supported for ${platform}. Use \`teamrc apply\` to apply team changes.`);
      process.exit(1);
    }

    try {
      const hashes = adapter.getHashes();
      const result = await client.sync(platform, hashes);

      const entries = Object.entries(result.changes);
      if (entries.length > 0) {
        let applied = 0;
        for (const [key, remoteChange] of entries) {
          const localContent = adapter.readFile(key);
          const localMtime = adapter.getFileMtime(key);
          const merged = resolveChange(key, localContent, remoteChange, localMtime);
          if (merged.warning) {
            console.warn(`  WARN: ${merged.warning}`);
          }
          if (merged.action !== "keep-local") {
            adapter.writeFile(key, merged.content);
            applied++;
          }
        }
        console.log(`Applied ${applied} of ${entries.length} change(s) from relay.`);
      } else {
        console.log("Already up to date.");
      }
    } catch (err) {
      console.error("Sync failed:", (err as Error).message);
      process.exit(1);
    }
  });

// --- push ---
program
  .command("push")
  .description("Push local knowledge to relay")
  .action(async () => {
    const { client, platform, adapter } = requireClient();

    try {
      const knowledge = adapter.readKnowledge();
      if (!knowledge) {
        console.log("No team knowledge to push.");
        return;
      }

      await client.push(platform, {
        type: "team-knowledge",
        content: knowledge,
      });
      console.log("Pushed team knowledge.");
    } catch (err) {
      console.error("Push failed:", (err as Error).message);
      process.exit(1);
    }
  });

// --- status ---
program
  .command("status")
  .description("Show current configuration and sync state")
  .option("--json", "Output as JSON")
  .action(async (opts: { json?: boolean }) => {
    const config = loadConfig();
    if (!config) {
      if (opts.json) {
        console.log(JSON.stringify({ error: "not initialized" }, null, 2));
      } else {
        console.log("teamrc is not initialized.");
        console.log("Run `teamrc init` to get started.");
      }
      return;
    }

    const teamId = config.teamId ?? config.globalTeam?.teamId ?? null;

    // Show local team info from native agent files
    const platform = config.platform ? primaryPlatform(config.platform) : (config.globalTeam?.platforms?.[0] ?? detectPlatforms()[0] ?? "claude-code");
    const adapter = getAdapter(platform);
    const localTeam = adapter.readTeam();

    // Show relay state if configured
    let remoteTeam = null;
    if (teamId) {
      const kp = loadKeypair();
      if (kp) {
        const client = new TeamrcClient(config.relay, kp.privateKey, config.token);
        try {
          remoteTeam = await client.getTeam(config.token);
        } catch {
          // relay unreachable
        }
      }
    }

    if (opts.json) {
      console.log(JSON.stringify({
        platform: config.platform ?? config.globalTeam?.platforms?.join(",") ?? platform,
        relay: config.relay,
        token: config.token.slice(0, 12) + "...",
        teamId,
        localTeam: localTeam ?? null,
        remoteTeam: remoteTeam ?? null,
      }, null, 2));
      return;
    }

    console.log("teamrc Status:");
    console.log(`  Platform: ${config.platform ?? config.globalTeam?.platforms?.join(",") ?? platform}`);
    console.log(`  Relay:    ${config.relay}`);
    console.log(`  Token:    ${config.token.slice(0, 12)}...`);
    if (teamId) {
      console.log(`  Team ID:  ${teamId}`);
    }

    if (localTeam) {
      console.log(`\nLocal Team: ${localTeam.name}`);
      console.log("  Agents:");
      for (const member of localTeam.members) {
        console.log(`    - ${member.name}: ${member.role}`);
      }
    } else {
      console.log("\nNo local team agents found.");
    }

    if (remoteTeam) {
      console.log(`\nRelay Team: ${remoteTeam.name}`);
      console.log("  Members:");
      for (const m of remoteTeam.members) {
        console.log(`    - ${m.name}: ${m.role} (${m.platform})`);
      }
    } else if (config.teamId) {
      console.log("\nRelay unreachable.");
    }
  });

// --- daemon ---
program
  .command("daemon")
  .description("Start the background sync daemon")
  .option("--poll-interval <ms>", "Poll interval in milliseconds", "120000")
  .option("--sync-mode <mode>", "What to sync: all, knowledge, none", "knowledge")
  .action(async (opts: { pollInterval: string; syncMode: string }) => {
    const { client, platform, adapter } = requireClient();

    if (!adapter.supportsSync) {
      console.error(`Daemon sync is not supported for ${platform}. Use \`teamrc apply\` to apply team changes.`);
      process.exit(1);
    }

    const validModes = ["all", "knowledge", "none"];
    if (!validModes.includes(opts.syncMode)) {
      console.error(`Invalid sync mode: ${opts.syncMode}. Valid options: ${validModes.join(", ")}`);
      process.exit(1);
    }

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
    const { config, client } = requireClient();

    try {
      const remoteTeam = await client.getTeam(config.token);
      validateTeamName(remoteTeam.name);
      const team = remoteTeamToDefinition(remoteTeam);
      writeTeamYaml(TEAM_YAML, team);
      console.log(`Exported "${team.name}" (${team.members.length} agents) to ${TEAM_YAML}.`);
    } catch (err) {
      console.error("Failed to fetch team from relay:", (err as Error).message);
      process.exit(1);
    }
  });

// --- pull ---
program
  .command("pull")
  .description("Pull team from relay and apply to local platforms")
  .option("--platform <platform>", "Override platform detection")
  .option("--scope <scope>", "Team scope: project or global")
  .action(async (opts: { platform?: string; scope?: string }) => {
    const { config, client } = requireClient();
    const platforms = await requirePlatforms(opts.platform);

    try {
      const remoteTeam = await client.getTeam(config.token);
      validateTeamName(remoteTeam.name);
      const team = remoteTeamToDefinition(remoteTeam);

      // Write YAML
      writeTeamYaml(TEAM_YAML, team);
      console.log(`Pulled "${team.name}" (${team.members.length} agents).`);

      // Apply to platforms
      for (const p of platforms) {
        const scope: TeamScope = opts.scope === "project" || opts.scope === "global"
          ? opts.scope
          : await askScope(p);

        const adapter = getAdapter(p);
        adapter.writeTeam(team, scope);
        console.log(`Applied to ${p} (${scope} scope).`);
      }
    } catch (err) {
      console.error("Pull failed:", (err as Error).message);
      process.exit(1);
    }
  });

// --- login ---
program
  .command("login")
  .description("Link this machine to your teamrc account")
  .option("--name <machine-name>", "Machine name (defaults to hostname)")
  .action(async (opts: { name?: string }) => {
    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const config = loadConfig();
    const relayUrl = config?.relay ?? getRelayUrl();
    const client = new TeamrcClient(relayUrl, kp.privateKey, token);
    const machineName = opts.name ?? os.hostname();

    const success = await deviceAuthFlow(client, machineName);
    if (!success) {
      process.exit(1);
    }
  });

// --- clone ---
program
  .command("clone")
  .description("Clone a team locally from an invite code without joining")
  .argument("<invite-code>", "Team invitation code")
  .option("--relay <url>", "Relay server URL")
  .option("--platform <platform>", "Override platform detection (claude-code, cursor, codex, gemini, openclaw)")
  .option("--scope <scope>", "Team scope: project or global (skips prompt)")
  .option("--name <name>", "Override team name")
  .action(async (inviteCode: string, opts: { relay?: string; platform?: string; scope?: string; name?: string }) => {
    const platforms = await requirePlatforms(opts.platform);

    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);
    const client = new TeamrcClient(relayUrl, kp.privateKey, token);

    try {
      const previewTeam = await client.previewByInvite(inviteCode);
      const teamDef = remoteTeamToDefinition(previewTeam);

      if (opts.name) {
        validateTeamName(opts.name);
        teamDef.name = opts.name;
      }

      // Write canonical YAML
      writeTeamYaml(TEAM_YAML, teamDef);
      console.log(`Wrote ${TEAM_YAML}.`);

      // Apply to each platform's native format
      for (const p of platforms) {
        console.log(`Setting up ${p}...`);
        const adapter = getAdapter(p);
        const scope: TeamScope = opts.scope === "project" || opts.scope === "global"
          ? opts.scope
          : await askScope(p);
        adapter.writeTeam(teamDef, scope);
        console.log(`  ${p} configured.`);
      }

      console.log(`\nCloned "${teamDef.name}" (${teamDef.members.length} agents) locally.`);
      console.log("This is a local copy. Run `teamrc init` to create your own synced team.");
    } catch (err) {
      console.error("Failed to clone team:", (err as Error).message);
      process.exit(1);
    }
  });

// --- invite ---
program
  .command("invite")
  .description("Create an invite code for the current team")
  .option("--ttl <hours>", "Invite expiry in hours", "24")
  .action(async (opts: { ttl: string }) => {
    const { client } = requireClient();
    const ttlHours = parseInt(opts.ttl, 10);

    if (isNaN(ttlHours) || ttlHours < 1) {
      console.error("TTL must be a positive number of hours.");
      process.exit(1);
    }

    try {
      const result = await client.createInvite(ttlHours);
      console.log(`\nInvite code: ${result.invite_code}`);
      console.log(`Expires: ${result.expires_at}`);
      console.log(`\nShare this command:\n  npx teamrc join ${result.invite_code}`);
    } catch (err) {
      console.error("Failed to create invite:", (err as Error).message);
      process.exit(1);
    }
  });

// --- whoami ---
program
  .command("whoami")
  .description("Show current identity and configuration")
  .option("--json", "Output as JSON")
  .action((opts: { json?: boolean }) => {
    const config = loadConfig();
    if (!config) {
      if (opts.json) {
        console.log(JSON.stringify({ error: "not initialized" }, null, 2));
      } else {
        console.log("teamrc is not initialized.");
      }
      return;
    }

    const whoamiTeamId = config.teamId ?? config.globalTeam?.teamId ?? "none";
    const whoamiPlatform = config.platform ?? config.globalTeam?.platforms?.join(",") ?? "none";

    if (opts.json) {
      console.log(JSON.stringify({
        token: config.token.slice(0, 16) + "...",
        machine: config.machineName ?? "unknown",
        account: config.account?.email ?? "not linked",
        teamId: whoamiTeamId,
        relay: config.relay,
        platform: whoamiPlatform,
      }, null, 2));
      return;
    }

    console.log(`Token:    ${config.token.slice(0, 16)}...`);
    console.log(`Machine:  ${config.machineName ?? "unknown"}`);
    console.log(`Account:  ${config.account?.email ?? "not linked"}`);
    console.log(`Team ID:  ${whoamiTeamId}`);
    console.log(`Relay:    ${config.relay}`);
    console.log(`Platform: ${whoamiPlatform}`);
  });

// --- log ---
program
  .command("log")
  .description("Show recent sync activity")
  .option("--limit <n>", "Number of entries to show", "20")
  .option("--json", "Output as JSON")
  .action(async (opts: { limit: string; json?: boolean }) => {
    const { client } = requireClient();
    const limit = parseInt(opts.limit, 10) || 20;

    try {
      const entries = await client.getLog();
      const sliced = entries.slice(0, limit);

      if (opts.json) {
        console.log(JSON.stringify(sliced, null, 2));
        return;
      }

      if (sliced.length === 0) {
        console.log("No recent sync activity.");
        return;
      }

      for (const entry of sliced) {
        const pushedBy = entry.pushed_by
          ? entry.pushed_by.length > 16
            ? entry.pushed_by.slice(0, 16) + "..."
            : entry.pushed_by
          : "unknown";
        console.log(`  ${entry.timestamp}  ${entry.type}  ${pushedBy}  ${entry.source_platform}`);
      }
    } catch (err) {
      console.error("Failed to fetch log:", (err as Error).message);
      process.exit(1);
    }
  });

// --- doctor ---
program
  .command("doctor")
  .description("Check teamrc setup and connectivity")
  .action(async () => {
    let passed = 0;
    let warnings = 0;
    let failures = 0;

    // 1. Keypair check
    const kp = loadKeypair();
    if (kp) {
      console.log("[ok] Keypair found");
      passed++;
    } else {
      console.log("[fail] No keypair");
      failures++;
    }

    // 2. Config check
    const config = loadConfig();
    if (config) {
      console.log("[ok] Config valid");
      passed++;
    } else {
      console.log("[fail] No config");
      failures++;
    }

    // 3. Relay reachable (only if config exists)
    if (config) {
      try {
        await fetch(`${config.relay}/api/sync/check?token=test&since=0`);
        // Any response (even 401/403) means reachable
        console.log("[ok] Relay reachable");
        passed++;
      } catch {
        console.log("[fail] Relay unreachable");
        failures++;
      }
    }

    // 4. .teamrc.yaml check
    const yamlTeam = readTeamYaml(TEAM_YAML);
    if (yamlTeam) {
      console.log(`[ok] ${TEAM_YAML} found`);
      passed++;
    } else {
      console.log(`[warn] No ${TEAM_YAML}`);
      warnings++;
    }

    // 5. Platform agents match
    if (config && yamlTeam) {
      const doctorPlatform = config.platform ? primaryPlatform(config.platform) : (config.globalTeam?.platforms?.[0] ?? detectPlatforms()[0] ?? "claude-code");
      const adapter = getAdapter(doctorPlatform);
      const platformTeam = adapter.readTeam();
      if (platformTeam) {
        const yamlCount = yamlTeam.members.length;
        const platformCount = platformTeam.members.length;
        if (yamlCount === platformCount) {
          console.log(`[ok] ${yamlCount} agents synced`);
          passed++;
        } else {
          console.log(`[warn] Mismatch: YAML has ${yamlCount}, platform has ${platformCount}`);
          warnings++;
        }
      } else {
        console.log("[warn] Mismatch: YAML has agents, platform has none");
        warnings++;
      }
    }

    console.log(`\n${passed} passed, ${warnings} warnings, ${failures} failures`);
  });

// --- delete ---
program
  .command("delete")
  .description("Remove teamrc from this machine")
  .action(async () => {
    const config = loadConfig();
    if (!config) {
      console.log("teamrc is not initialized. Nothing to remove.");
      return;
    }

    const platforms = config.platform ? config.platform.split(",") : (config.globalTeam?.platforms ?? detectPlatforms());

    console.log("\nThis will remove all teamrc agents, config, and team knowledge from this machine.");
    console.log("Other team members will keep their setup — you're just disconnecting.\n");
    const answer = await askQuestion("Continue? [y/N]: ");

    if (answer.toLowerCase() !== "y") {
      console.log("Cancelled.");
      return;
    }

    // Uninstall from each platform
    for (const p of platforms) {
      const adapter = getAdapter(p);
      const actions = adapter.uninstall();
      for (const action of actions) {
        console.log(`  ${action}`);
      }
    }

    // Delete ~/.teamrc/ config
    const configDir = path.join(os.homedir(), ".teamrc");
    if (fs.existsSync(configDir)) {
      fs.rmSync(configDir, { recursive: true });
      console.log(`  Deleted ${configDir}`);
    }

    // Delete .teamrc.yaml if present
    if (fs.existsSync(TEAM_YAML)) {
      fs.unlinkSync(TEAM_YAML);
      console.log(`  Deleted ${TEAM_YAML}`);
    }

    console.log("\nteamrc removed. Run `teamrc init` or `teamrc join` to set up again.");
  });

program.parse();
