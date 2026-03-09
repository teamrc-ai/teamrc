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
import { resolveTeam, listTeams, templateToTeamDefinition, listAgentCategories, loadAgent, loadSkill, agentRecommendedSkills, type TeamTemplate } from "./catalog.js";
import { writeTeamYaml, validateTeamName, readTeamYaml, TEAM_YAML, GLOBAL_TEAM_YAML, mergeKnowledge, MAX_KNOWLEDGE_SIZE } from "./team-yaml.js";
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

  // Platforms with working adapters (exclude unimplemented ones)
  const UNIMPLEMENTED_PLATFORMS = ["copilot", "amazon-q", "windsurf", "cline"];
  const selectablePlatforms = VALID_PLATFORMS.filter(
    (pl) => !UNIMPLEMENTED_PLATFORMS.includes(pl),
  );

  // Interactive multi-select with detected platforms pre-selected
  const selected = await p.multiselect({
    message: "Which platforms?",
    options: selectablePlatforms.map((pl) => ({
      value: pl,
      label: pl,
      hint: detected.includes(pl) ? "detected" : undefined,
    })),
    initialValues: detected.filter((pl) => !UNIMPLEMENTED_PLATFORMS.includes(pl)),
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
  let yamlTeam;
  try {
    yamlTeam = readTeamYaml(TEAM_YAML);
  } catch (e) {
    p.log.error(`Failed to parse .teamrc.yaml: ${e instanceof Error ? e.message : e}`);
    process.exit(1);
  }
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

  // 2. Fall back to global YAML (~/.teamrc/team.yaml)
  let globalTeam;
  try {
    globalTeam = readTeamYaml(GLOBAL_TEAM_YAML);
  } catch (e) {
    p.log.error(`Failed to parse global team.yaml: ${e instanceof Error ? e.message : e}`);
    process.exit(1);
  }
  if (globalTeam?.teamId) {
    const relay = globalTeam.relay ?? config.relay;
    const platforms = globalTeam.platforms ?? detectPlatforms();
    const client = new TeamrcClient(relay, kp.privateKey, config.token, globalTeam.teamId);
    return {
      team: globalTeam,
      scope: "global",
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
async function deviceAuthFlow(client: TeamrcClient, machineName: string, relayUrl: string): Promise<boolean> {
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

  // Try to open browser automatically (only if same origin as relay)
  if (deviceAuth.verification_url.startsWith("https://")) {
    try {
      const relayOrigin = new URL(relayUrl).origin;
      const verifyOrigin = new URL(deviceAuth.verification_url).origin;
      if (verifyOrigin === relayOrigin) {
        const openCmd = process.platform === "darwin" ? "open" : "xdg-open";
        execFileSync(openCmd, [deviceAuth.verification_url], { stdio: "ignore" });
      } else {
        // Don't auto-open URLs from different origins
      }
    } catch {
      // URL parsing failed, skip auto-open
    }
  }

  s.start("Waiting for confirmation... (press Ctrl-C to cancel)");

  const MAX_EXPIRES_SEC = 600;
  const MIN_INTERVAL_SEC = 1;
  const MAX_INTERVAL_SEC = 30;
  const startTime = Date.now();
  const timeoutMs = Math.min(deviceAuth.expires_in, MAX_EXPIRES_SEC) * 1000;
  const intervalMs = Math.max(MIN_INTERVAL_SEC, Math.min(deviceAuth.interval, MAX_INTERVAL_SEC)) * 1000;

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

// ---------------------------------------------------------------------------
// Template selection helpers
// ---------------------------------------------------------------------------

/** Prompt the user to select a team template, or resolve from --team flag */
async function selectTemplate(teamFlag?: string): Promise<TeamTemplate> {
  const teamIds = listTeams();

  if (teamFlag) {
    if (!teamIds.includes(teamFlag)) {
      p.log.error(`Unknown team: ${teamFlag}. Options: ${teamIds.join(", ")}`);
      process.exit(1);
    }
    return resolveTeam(teamFlag);
  }

  if (isNonInteractive()) return resolveTeam("custom");

  const selected = await p.select({
    message: "What kind of team?",
    options: teamIds.map((id) => {
      const t = resolveTeam(id);
      return { value: id, label: t.label, hint: t.description };
    }),
  });
  handleCancel(selected);
  return resolveTeam(selected as string);
}

/** Prompt for a team name with a default value */
async function promptTeamName(defaultName: string): Promise<string> {
  if (isNonInteractive()) return defaultName;

  const name = await p.text({
    message: "Team name",
    initialValue: defaultName,
    validate: (val) => {
      if (!val || !val.trim()) return "Team name is required";
      try {
        validateTeamName(val.trim());
      } catch (e) {
        return (e as Error).message;
      }
    },
  });
  handleCancel(name);
  return (name as string).trim();
}

// --- init ---
program
  .command("init")
  .description("Initialize teamrc: detect platform, create agents, connect to relay")
  .option("--relay <url>", "Relay server URL")
  .option("--platform <platform>", "Override platform detection")
  .option("--global", "Install as global team (all projects)")
  .option("--name <name>", "Team name")
  .option("--team <id>", "Team template (fullstack, backend, frontend, security, devops, custom, ...)")
  .action(async (opts: { relay?: string; platform?: string; global?: boolean; name?: string; team?: string }) => {
    p.intro("teamrc");

    const platforms = await requirePlatforms(opts.platform);
    const scope = await selectScope(opts);

    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);

    const firstAdapter = getAdapter(platforms[0]);

    // Check for existing .teamrc.yaml first (highest precedence)
    let existingYaml;
    try {
      existingYaml = readTeamYaml(TEAM_YAML);
    } catch (e) {
      p.log.error(`Failed to parse .teamrc.yaml: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }

    let team: TeamDefinition;

    if (existingYaml) {
      p.log.info(`Found existing .teamrc.yaml: "${existingYaml.name}" with ${existingYaml.members.length} agent(s).`);
      team = existingYaml;
      if (opts.name) team.name = opts.name;
    } else {
      // Scan ALL platforms for existing teams
      const platformTeams: Array<{ platform: string; team: TeamDefinition }> = [];
      for (const pl of platforms) {
        const adapter = getAdapter(pl);
        const t = adapter.readTeam();
        if (t) platformTeams.push({ platform: pl, team: t });
      }

      if (platformTeams.length > 0) {
        let selectedTeam: TeamDefinition;
        if (platformTeams.length === 1 || isNonInteractive()) {
          selectedTeam = platformTeams[0].team;
          p.log.info(`Found existing team "${selectedTeam.name}" in ${platformTeams[0].platform}.`);
        } else {
          const choice = await p.select({
            message: "Found existing teams. Which one?",
            options: platformTeams.map((pt) => ({
              value: pt.platform,
              label: `${pt.team.name} (${pt.platform})`,
              hint: `${pt.team.members.length} agents`,
            })),
          });
          handleCancel(choice);
          selectedTeam = platformTeams.find((pt) => pt.platform === choice)!.team;
        }
        team = selectedTeam;
        if (opts.name) team.name = opts.name;
      } else {
        // No existing team — select a template
        const template = await selectTemplate(opts.team);
        const teamName = opts.name ?? await promptTeamName(template.id === "custom" ? "my-team" : template.teamName);
        team = templateToTeamDefinition(template, teamName);

        if (template.id !== "custom") {
          const memberNames = template.members.map((m) => m.name).join(", ");
          p.log.info(`${template.members.length} agents: ${memberNames}`);
        }
      }
    }

    // Apply to each platform's native format
    const platformSummary: string[] = [];
    for (const pl of platforms) {
      const adapter = getAdapter(pl);
      adapter.writeTeam(team, scope);
      platformSummary.push(pl);
    }
    p.log.step(`Applied to: ${platformSummary.join(", ")}`);

    // Create team knowledge file if it doesn't exist
    if (!firstAdapter.readKnowledge()) {
      firstAdapter.writeKnowledge(`# Team Knowledge\n\nShared findings and decisions across team members.\n`);
    }

    // Create team on relay
    const s = p.spinner();
    const client = new TeamrcClient(relayUrl, kp.privateKey, token);
    try {
      s.start("Creating team on relay...");
      const knowledge = firstAdapter.readKnowledge();
      const relayTeam = await client.createTeam(
        team.name,
        team.members.map((m) => ({ name: m.name, role: m.role, platform: platforms.join(","), ...(m.skills?.length ? { skills: m.skills } : {}) })),
        team.skills,
        knowledge || undefined,
      );
      s.stop("Team created.");

      // Write YAML with teamId (project mode) or write to global YAML
      team.teamId = relayTeam.id;
      team.platforms = platforms;

      if (scope === "global") {
        team.relay = relayUrl;
        writeTeamYaml(GLOBAL_TEAM_YAML, team);
        p.log.step(`Wrote ${GLOBAL_TEAM_YAML}`);
        saveConfig({ relay: relayUrl, token });
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
          await deviceAuthFlow(client, machineName, relayUrl);
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

      p.outro("Customize agents and skills in .teamrc.yaml, then run teamrc apply");
    } catch (err) {
      s.error("Failed to create team on relay.");
      p.log.warn(`Relay error: ${(err as Error).message}`);
      saveConfig({ relay: relayUrl, token });
      p.log.info("Configuration saved (relay unreachable).");
      p.outro("Configuration saved locally. Re-run `teamrc init` when the relay is available to complete setup.");
    }
  });

// --- join ---
program
  .command("join")
  .description("Join an existing team and create local agents")
  .argument("<invite-code>", "Team invitation code")
  .option("--relay <url>", "Relay server URL")
  .option("--platform <platform>", "Override platform detection")
  .option("--global", "Join as global team")
  .action(async (inviteCode: string, opts: { relay?: string; platform?: string; global?: boolean }) => {
    p.intro("teamrc");

    const platforms = await requirePlatforms(opts.platform);
    const scope = await selectScope(opts);

    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);
    const client = new TeamrcClient(relayUrl, kp.privateKey, token);

    const s = p.spinner();
    try {
      s.start("Joining team...");
      const joinedTeam = await client.joinByInvite(inviteCode);
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
        const skillCount = teamDef.skills?.length ?? 0;
        const detail = skillCount > 0
          ? `${teamDef.members.length} agents, ${skillCount} skills`
          : `${teamDef.members.length} agents`;
        appliedLines.push(`  ${pl.padEnd(14)} ${detail}`);
      }
      s2.stop("Applied.");
      p.log.info(appliedLines.join("\n"));

      // Create team knowledge file if it doesn't exist
      const joinAdapter = getAdapter(platforms[0]);
      if (!joinAdapter.readKnowledge()) {
        joinAdapter.writeKnowledge(`# Team Knowledge\n\nShared findings and decisions across team members.\n`);
      }

      // Merge knowledge from relay
      if (joinedTeam.knowledge) {
        const localKnowledge = joinAdapter.readKnowledge();
        const merged = mergeKnowledge(localKnowledge, joinedTeam.knowledge);
        if (merged.length <= MAX_KNOWLEDGE_SIZE) {
          joinAdapter.writeKnowledge(merged);
        } else {
          p.log.warn("Remote knowledge exceeds maximum size, skipping merge.");
        }
      }

      if (scope === "global") {
        teamDef.teamId = joinedTeam.id;
        teamDef.platforms = platforms;
        teamDef.relay = relayUrl;
        writeTeamYaml(GLOBAL_TEAM_YAML, teamDef);
        p.log.step(`Wrote ${GLOBAL_TEAM_YAML}`);
        saveConfig({ relay: relayUrl, token });
      } else {
        teamDef.teamId = joinedTeam.id;
        teamDef.platforms = platforms;
        teamDef.relay = relayUrl;
        writeTeamYaml(TEAM_YAML, teamDef);
        p.log.step(`Wrote ${TEAM_YAML}`);
        saveConfig({ relay: relayUrl, token });
      }

      if (!isNonInteractive()) {
        const shouldLink = await p.confirm({
          message: "Link your account? (optional, for recovery & dashboard)",
          initialValue: false,
        });
        handleCancel(shouldLink);
        if (shouldLink) {
          const machineName = os.hostname();
          await deviceAuthFlow(client, machineName, relayUrl);
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
    let team;
    try {
      team = readTeamYaml(TEAM_YAML);
    } catch (e) {
      p.log.error(`Failed to parse .teamrc.yaml: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
    if (!team) {
      // Fall back to global YAML
      try {
        team = readTeamYaml(GLOBAL_TEAM_YAML);
      } catch (e) {
        p.log.error(`Failed to parse global team.yaml: ${e instanceof Error ? e.message : e}`);
        process.exit(1);
      }
    }
    if (!team) {
      p.log.error("No .teamrc.yaml found. Run `teamrc init` or `teamrc import <platform>` first.");
      process.exit(1);
    }

    const scope = await selectScope(opts);

    const s = p.spinner();
    s.start(`Applying "${team.name}" to ${platforms.length} platform(s)...`);

    const appliedLines: string[] = [];
    for (const pl of platforms) {
      const adapter = getAdapter(pl);
      adapter.writeTeam(team, scope);
      const skillCount = team.skills?.length ?? 0;
      const parts = [`${team.members.length} agents`];
      if (skillCount > 0) parts.push(`${skillCount} skills`);
      appliedLines.push(`  ${pl.padEnd(14)} ${parts.join(", ")}`);
    }
    s.stop("Applied.");

    p.log.info(appliedLines.join("\n"));
    p.outro(`Done. ${team.members.length} agents across ${platforms.length} platform(s).`);
  });

// --- import ---
program
  .command("import")
  .description("Import team from platform files into .teamrc.yaml")
  .argument("<platform>", "Platform to import from (claude-code, cursor, codex, gemini, openclaw)")
  .action(async (platform: string) => {
    p.intro("teamrc");

    if (!VALID_PLATFORMS.includes(platform as typeof VALID_PLATFORMS[number])) {
      p.log.error(`Unknown platform: ${platform}. Valid options: ${VALID_PLATFORMS.join(", ")}`);
      process.exit(1);
    }

    const adapter = getAdapter(platform);
    const team = adapter.readTeam();
    if (!team) {
      p.log.error(`Platform "${platform}" has no teamrc files to import.`);
      process.exit(1);
    }

    writeTeamYaml(TEAM_YAML, team);
    p.log.success(`Imported "${team.name}" (${team.members.length} agents) from ${platform}.`);
    p.log.step(`Wrote ${TEAM_YAML}`);
    p.outro("This is a local copy. Run `teamrc init` to create a synced team.");
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

      const remoteTeam = await client.getTeam();

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
  .description("Push local changes to relay and pull remote updates")
  .option("--platform <platform>", "Override platform detection")
  .option("--scope <scope>", "Team scope: project or global")
  .option("--global", "Pull as global team")
  .action(async (opts: { platform?: string; scope?: string; global?: boolean }) => {
    p.intro("teamrc");

    const ctx = requireTeamContext();
    const { client, config } = ctx;
    const platforms = await requirePlatforms(opts.platform);
    const scope = await selectScope(opts);
    const adapter = ctx.adapters[0];

    const s = p.spinner();
    try {
      // Push: send local definition + knowledge to relay
      s.start("Pushing to relay...");
      const team = readTeamYaml(TEAM_YAML);
      if (!team) {
        s.stop("No .teamrc.yaml found.");
        process.exit(1);
      }
      const knowledge = adapter.readKnowledge();
      await client.pushTeam(team, knowledge || undefined);
      s.stop("Pushed.");

      // Pull: get latest from relay
      s.start("Pulling from relay...");
      const remoteTeam = await client.getTeam();
      validateTeamName(remoteTeam.name);
      const remoteDef = remoteTeamToDefinition(remoteTeam);

      // Preserve local YAML metadata
      remoteDef.teamId = ctx.team.teamId;
      remoteDef.relay = ctx.team.relay;
      remoteDef.platforms = ctx.team.platforms;

      // Merge knowledge (append-only dedup)
      if (remoteTeam.knowledge) {
        const localKnowledge = adapter.readKnowledge();
        const merged = mergeKnowledge(localKnowledge, remoteTeam.knowledge);
        if (merged.length <= MAX_KNOWLEDGE_SIZE) {
          adapter.writeKnowledge(merged);
        } else {
          p.log.warn("Remote knowledge exceeds maximum size, skipping merge.");
        }
      }

      writeTeamYaml(TEAM_YAML, remoteDef);

      // Apply to platforms
      for (const pl of platforms) {
        const a = getAdapter(pl);
        a.writeTeam(remoteDef, scope);
      }
      s.stop("Pulled and applied.");

      p.outro("Synced.");
    } catch (err) {
      s.stop("Sync failed.");
      p.log.error((err as Error).message);
      process.exit(1);
    }
  });

// --- push ---
program
  .command("push")
  .description("Push team definition and knowledge to relay")
  .action(async () => {
    p.intro("teamrc");

    const ctx = requireTeamContext();
    const { client } = ctx;
    const adapter = ctx.adapters[0];

    let team;
    try {
      team = readTeamYaml(TEAM_YAML);
    } catch (e) {
      p.log.error(`Failed to parse .teamrc.yaml: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
    if (!team) {
      p.log.error("No .teamrc.yaml found. Run `teamrc init` first.");
      process.exit(1);
    }

    const s = p.spinner();
    try {
      s.start("Pushing to relay...");
      const knowledge = adapter.readKnowledge();
      await client.pushTeam(team, knowledge || undefined);
      s.stop("Pushed team definition and knowledge.");
      p.outro("Done.");
    } catch (err) {
      s.stop("Push failed.");
      p.log.error((err as Error).message);
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

    let yamlTeam;
    try {
      yamlTeam = readTeamYaml(TEAM_YAML);
    } catch (e) {
      p.log.error(`Failed to parse .teamrc.yaml: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
    let globalYaml = null;
    if (!yamlTeam) {
      try {
        globalYaml = readTeamYaml(GLOBAL_TEAM_YAML);
      } catch (e) {
        p.log.error(`Failed to parse global team.yaml: ${e instanceof Error ? e.message : e}`);
        process.exit(1);
      }
    }
    const activeTeam = yamlTeam ?? globalYaml;
    const teamId = activeTeam?.teamId ?? null;
    const platformStr = activeTeam?.platforms?.join(",") ?? detectPlatforms()[0] ?? "claude-code";
    const activePlatform = platformStr.split(",")[0];
    const adapter = getAdapter(activePlatform);
    const localTeam = activeTeam;

    // Check relay state
    let remoteTeam = null;
    let relayConnected = false;
    if (teamId) {
      const kp = loadKeypair();
      if (kp) {
        const client = new TeamrcClient(config.relay, kp.privateKey, config.token);
        try {
          remoteTeam = await client.getTeam();
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

    p.outro("Done.");
  });

// --- daemon ---
program
  .command("daemon")
  .description("Start the background sync daemon")
  .option("--poll-interval <ms>", "Poll interval in milliseconds", "120000")
  .action(async (opts: { pollInterval: string }) => {
    const pollMs = parseInt(opts.pollInterval, 10);
    if (isNaN(pollMs) || pollMs < 5000) {
      p.log.error("--poll-interval must be at least 5000ms.");
      process.exit(1);
    }

    const ctx = requireTeamContext();
    const { client } = ctx;

    p.intro("teamrc daemon");
    p.log.info([
      `Watching "${ctx.team.name || "team"}" on ${ctx.platforms.join(", ")}`,
      `Poll interval: ${parseInt(opts.pollInterval, 10) / 1000}s`,
    ].join("\n"));

    const { startDaemon } = await import("./daemon.js");
    const daemon = startDaemon({
      client,
      adapters: ctx.adapters,
      platforms: ctx.platforms,
      pollInterval: parseInt(opts.pollInterval, 10),
    });

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
      const remoteTeam = await client.getTeam();
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
    const adapter = ctx.adapters[0];

    const s = p.spinner();
    try {
      s.start("Pulling from relay...");
      const remoteTeam = await client.getTeam();
      validateTeamName(remoteTeam.name);
      const team = remoteTeamToDefinition(remoteTeam);

      // Preserve local YAML metadata
      team.teamId = ctx.team.teamId;
      team.relay = ctx.team.relay;
      team.platforms = ctx.team.platforms;

      // Merge knowledge
      if (remoteTeam.knowledge) {
        const localKnowledge = adapter.readKnowledge();
        const merged = mergeKnowledge(localKnowledge, remoteTeam.knowledge);
        if (merged.length <= MAX_KNOWLEDGE_SIZE) {
          adapter.writeKnowledge(merged);
        } else {
          p.log.warn("Remote knowledge exceeds maximum size, skipping merge.");
        }
      }

      writeTeamYaml(TEAM_YAML, team);
      s.stop(`Pulled "${team.name}" (${team.members.length} agents).`);

      // Apply to platforms
      for (const pl of platforms) {
        const a = getAdapter(pl);
        a.writeTeam(team, scope);
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

    const success = await deviceAuthFlow(client, machineName, relayUrl);
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
      p.outro("Cloned locally. To join and sync with the original team, use `teamrc join <invite-code>`.");
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

    let whoamiYaml;
    try {
      whoamiYaml = readTeamYaml(TEAM_YAML) ?? readTeamYaml(GLOBAL_TEAM_YAML);
    } catch (e) {
      p.log.error(`Failed to parse team YAML: ${e instanceof Error ? e.message : e}`);
      process.exit(1);
    }
    const whoamiTeamId = whoamiYaml?.teamId ?? "none";
    const whoamiPlatform = whoamiYaml?.platforms?.join(",") ?? "none";

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
        await fetch(`${config.relay}/api/teams/${encodeURIComponent(config.token)}`);
        const ms = Date.now() - start;
        p.log.success(`Relay reachable (${ms}ms)`);
        passed++;
      } catch {
        p.log.error("Relay unreachable");
        failures++;
      }
    }

    // 4. .teamrc.yaml check
    let yamlTeam;
    let yamlParseError = false;
    try {
      yamlTeam = readTeamYaml(TEAM_YAML);
    } catch (e) {
      p.log.error(`${TEAM_YAML} has parse errors: ${e instanceof Error ? e.message : e}`);
      failures++;
      yamlParseError = true;
    }
    if (yamlTeam) {
      p.log.success(`${TEAM_YAML} found (${yamlTeam.members.length} members)`);
      passed++;
    } else if (!yamlParseError) {
      p.log.warn(`No ${TEAM_YAML}`);
      warnings++;
    }

    // 5. Platform agents match
    if (config && yamlTeam) {
      let doctorGlobal;
      try {
        doctorGlobal = readTeamYaml(GLOBAL_TEAM_YAML);
      } catch {
        // ignore parse errors for global yaml in doctor
      }
      const doctorPlatform = yamlTeam?.platforms?.[0] ?? doctorGlobal?.platforms?.[0] ?? detectPlatforms()[0] ?? "claude-code";
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
      p.outro("Done.");
      return;
    }

    let deleteGlobalTeam;
    try {
      deleteGlobalTeam = readTeamYaml(GLOBAL_TEAM_YAML);
    } catch {
      // Ignore parse errors during delete — proceed with detected platforms
    }
    const platforms = deleteGlobalTeam?.platforms ?? detectPlatforms();

    // Determine team name for confirmation
    let teamName: string | null = null;
    let yamlTeam;
    try {
      yamlTeam = readTeamYaml(TEAM_YAML);
    } catch {
      // Ignore parse errors during delete
    }
    if (yamlTeam?.name) {
      teamName = yamlTeam.name;
    }

    p.log.warn(
      "This will remove all teamrc agents, skills, and knowledge\n" +
      "from this machine. Other team members keep their setup.",
    );

    // Build deletion plan to show before confirmation
    const planLines: string[] = [];
    for (const pl of platforms) {
      planLines.push(`Remove ${pl} agents and skills`);
    }
    const configDir = path.join(os.homedir(), ".teamrc");
    if (fs.existsSync(configDir)) {
      planLines.push(`Delete ${configDir}`);
    }
    if (fs.existsSync(TEAM_YAML)) {
      planLines.push(`Delete ${TEAM_YAML}`);
    }
    if (planLines.length > 0) {
      p.log.info("Will delete:\n" + planLines.map((a) => `  ${a}`).join("\n"));
    }

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

// --- add-member ---
program
  .command("add-member")
  .description("Add a catalog agent (or custom agent) to the current team")
  .argument("[agent-name]", "Agent name from catalog (e.g. backend-dev)")
  .action(async (agentName?: string) => {
    p.intro("teamrc");

    const ctx = requireTeamContext();
    const { team, scope, client, platforms } = ctx;
    const yamlPath = scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML;

    // Resolve agent name — from argument or interactive picker
    let name = agentName;
    if (!name) {
      if (isNonInteractive()) {
        p.log.error("Agent name is required in non-interactive mode.\n  Usage: teamrc add-member <agent-name>");
        process.exit(1);
      }

      const categories = listAgentCategories();
      const existingNames = new Set(team.members.map((m) => m.name));

      // Build flat option list grouped by category
      const options: Array<{ value: string; label: string; hint?: string }> = [];
      for (const cat of categories) {
        const available = cat.agents.filter((a) => !existingNames.has(a));
        if (available.length === 0) continue;
        for (const a of available) {
          try {
            const agent = loadAgent(a);
            options.push({ value: a, label: a, hint: `${agent.role} [${cat.label}]` });
          } catch {
            options.push({ value: a, label: a, hint: cat.label });
          }
        }
      }

      if (options.length === 0) {
        p.log.warn("All catalog agents are already on this team.");
        p.outro("Nothing to add.");
        return;
      }

      const selected = await p.select({
        message: "Select an agent to add",
        options,
      });
      handleCancel(selected);
      name = selected as string;
    }

    // Duplicate check
    if (team.members.find((m) => m.name === name)) {
      p.log.warn(`Agent "${name}" is already on this team.`);
      p.outro("Nothing to add.");
      return;
    }

    // Load agent from catalog
    let agent;
    try {
      agent = loadAgent(name);
    } catch {
      p.log.error(`Agent "${name}" not found in catalog.`);
      process.exit(1);
    }

    // Get recommended skills for this agent
    const recommendedSkillIds = agentRecommendedSkills(name);

    // Ensure referenced skills exist in team.skills
    const existingSkillIds = new Set((team.skills ?? []).map((s) => s.id));
    const newSkills = [];
    for (const skillId of recommendedSkillIds) {
      if (!existingSkillIds.has(skillId)) {
        try {
          const skill = loadSkill(skillId);
          newSkills.push({
            id: skill.id,
            title: skill.title,
            ...(skill.description ? { description: skill.description } : {}),
            ...(skill.alwaysApply !== undefined ? { alwaysApply: skill.alwaysApply } : {}),
            ...(skill.globs ? { globs: skill.globs } : {}),
            ...(skill.userInvocable !== undefined ? { userInvocable: skill.userInvocable } : {}),
            body: skill.body,
          });
        } catch {
          // Skill not in catalog — skip
        }
      }
    }

    // Build new member
    const newMember = {
      name: agent.name,
      role: agent.role,
      soul: agent.soul,
      ...(recommendedSkillIds.length > 0 ? { skills: recommendedSkillIds } : {}),
    };

    // Mutate team (in memory only — write after push succeeds)
    team.members.push(newMember);
    if (newSkills.length > 0) {
      if (!team.skills) team.skills = [];
      team.skills.push(...newSkills);
    }

    // Push to relay first — don't persist locally until relay accepts
    const s = p.spinner();
    try {
      s.start("Pushing to relay...");
      const knowledge = ctx.adapters[0]?.readKnowledge();
      await client.pushTeam(team, knowledge || undefined);
      s.stop("Pushed.");
    } catch (err) {
      s.error("Push failed.");
      p.log.error((err as Error).message);
      process.exit(1);
    }

    // Write YAML and apply to platforms only after successful push
    writeTeamYaml(yamlPath, team);
    for (const pl of platforms) {
      const adapter = getAdapter(pl);
      adapter.writeTeam(team, scope);
    }

    // Summary
    const parts = [`Added ${agent.name} (${agent.role})`];
    if (recommendedSkillIds.length > 0) {
      parts.push(`Includes ${recommendedSkillIds.length} skill(s): ${recommendedSkillIds.join(", ")}`);
    }
    p.log.success(parts.join("\n  "));
    p.outro(`Applied to ${platforms.length} platform(s).`);
  });

// --- list-templates ---
program
  .command("list-templates")
  .description("List available team templates from the catalog")
  .option("--json", "Output as JSON")
  .action(async (opts: { json?: boolean }) => {
    const useJson = opts.json ?? globals().json;
    const teamIds = listTeams();

    const teams = teamIds.map((id) => {
      const t = resolveTeam(id);
      return {
        id,
        label: t.label,
        description: t.description,
        agents: t.members.length,
        skills: t.skills.length,
        members: t.members.map((m) => m.name),
      };
    });

    if (useJson) {
      jsonOutput(teams);
      return;
    }

    p.intro("teamrc");
    p.log.info("Available team templates:\n");

    for (const t of teams) {
      const memberList = t.members.join(", ");
      p.log.message(
        `  ${t.id.padEnd(16)} ${t.label}\n` +
        `  ${"".padEnd(16)} ${t.description}\n` +
        `  ${"".padEnd(16)} ${t.agents} agents, ${t.skills} skills: ${memberList}\n`,
      );
    }

    p.outro(`${teams.length} templates. Use \`teamrc init --team <name>\` to create a team.`);
  });

// --- list-agents ---
program
  .command("list-agents")
  .description("List available agents from the catalog")
  .option("--json", "Output as JSON")
  .action(async (opts: { json?: boolean }) => {
    const useJson = opts.json ?? globals().json;
    const categories = listAgentCategories();

    if (useJson) {
      const data = categories.map((cat) => ({
        category: cat.id,
        label: cat.label,
        agents: cat.agents.map((name) => {
          try {
            const a = loadAgent(name);
            return { name: a.name, role: a.role };
          } catch {
            return { name, role: "" };
          }
        }),
      }));
      jsonOutput(data);
      return;
    }

    p.intro("teamrc");

    let totalAgents = 0;
    for (const cat of categories) {
      const lines: string[] = [];
      for (const name of cat.agents) {
        try {
          const a = loadAgent(name);
          lines.push(`  ${a.name.padEnd(28)} ${a.role}`);
        } catch {
          lines.push(`  ${name}`);
        }
        totalAgents++;
      }
      p.log.message(`${cat.label}\n${lines.join("\n")}\n`);
    }

    p.outro(`${totalAgents} agents. Use \`teamrc add-member <name>\` to add one to your team.`);
  });

program.parse();
