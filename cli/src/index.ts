#!/usr/bin/env node

import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import * as readline from "node:readline";
import { Command } from "commander";
import {
  generateKeypair,
  saveKeypair,
  loadKeypair,
  toToken,
} from "./auth.js";
import { TeamBridgeClient, remoteTeamToDefinition } from "./client.js";
import {
  loadConfig,
  saveConfig,
  detectPlatforms,
  getRelayUrl,
} from "./config.js";
import { getAdapter, type TeamScope, type TeamDefinition } from "./adapters/base.js";
import { resolveChange } from "./merge.js";
import { writeTeamYaml, validateTeamName } from "./team-yaml.js";
import { resolveTeamSource } from "./resolve-source.js";

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

async function requirePlatform(override?: string): Promise<string> {
  if (override) {
    const valid = ["claude-code", "openclaw", "cursor", "codex", "gemini"];
    if (!valid.includes(override)) {
      console.error(`Unknown platform: ${override}. Valid options: ${valid.join(", ")}`);
      process.exit(1);
    }
    return override;
  }
  const platforms = detectPlatforms();
  if (platforms.length === 0) {
    console.error(
      "Could not detect platform. Ensure ~/.claude or ~/.openclaw exists, or use --platform.",
    );
    process.exit(1);
  }
  if (platforms.length === 1) {
    return platforms[0];
  }

  // Multiple platforms detected — ask the user
  console.log("\nMultiple platforms detected:");
  for (let i = 0; i < platforms.length; i++) {
    console.log(`  ${i + 1}) ${platforms[i]}`);
  }
  console.log(`  ${platforms.length + 1}) Both`);
  const answer = await askQuestion(`\nWhich platform? [1-${platforms.length + 1}]: `);
  const choice = parseInt(answer, 10);
  if (choice >= 1 && choice <= platforms.length) {
    return platforms[choice - 1];
  }
  if (choice === platforms.length + 1) {
    return "both";
  }
  return platforms[0];
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

interface ConnectedContext {
  config: import("./config.js").TeambridgeConfig & { teamId: string };
  client: TeamBridgeClient;
  platform: string;
  adapter: import("./adapters/base.js").PlatformAdapter;
}

/** Load config + keypair + build client, or exit with error. */
function requireClient(): ConnectedContext {
  const config = loadConfig();
  if (!config) {
    console.error("Not initialized. Run `teambridge init` first.");
    process.exit(1);
  }
  if (!config.teamId) {
    console.error("No team ID configured.");
    process.exit(1);
  }
  const kp = loadKeypair();
  if (!kp) {
    console.error("No keypair found.");
    process.exit(1);
  }
  const platform = primaryPlatform(config.platform);
  return {
    config: config as ConnectedContext["config"],
    client: new TeamBridgeClient(config.relay, kp.privateKey, config.token),
    platform,
    adapter: getAdapter(platform),
  };
}

const program = new Command();

program
  .name("teambridge")
  .description("TeamBridge — sync multi-agent teams across platforms")
  .version("0.1.0");

// --- init ---
program
  .command("init")
  .description("Initialize TeamBridge: detect platform, create agents, connect to relay")
  .option("--relay <url>", "Relay server URL")
  .option("--platform <platform>", "Override platform detection (claude-code, openclaw)")
  .action(async (opts: { relay?: string; platform?: string }) => {
    const selected = await requirePlatform(opts.platform);
    const platforms = selected === "both" ? detectPlatforms() : [selected];

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

    // Write canonical YAML file
    writeTeamYaml("agent-team.yaml", team);
    console.log("Wrote agent-team.yaml.");

    // Apply to each platform's native format
    for (const p of platforms) {
      console.log(`Setting up ${p}...`);
      const adapter = getAdapter(p);
      const scope = await askScope(p);
      adapter.writeTeam(team, scope);
      adapter.installHooks(relayUrl, token);
      console.log(`  ${p} configured.`);
    }

    // Create team on relay
    const client = new TeamBridgeClient(relayUrl, kp.privateKey, token);
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

      saveConfig({
        platform: platforms.join(","),
        relay: relayUrl,
        token,
        teamId: relayTeam.id,
      });
      console.log("Configuration saved.");
      console.log(`\nShare this token to invite others: ${token}`);
    } catch (err) {
      console.error("Failed to initialize with relay:", err);
      saveConfig({ platform: platforms.join(","), relay: relayUrl, token });
      console.log("Configuration saved (relay unreachable).");
    }
  });

// --- join ---
program
  .command("join")
  .description("Join an existing team and create local agents")
  .argument("<token>", "Team invitation token")
  .option("--relay <url>", "Relay server URL")
  .option("--platform <platform>", "Override platform detection (claude-code, openclaw)")
  .option("--scope <scope>", "Team scope: project or global (skips prompt)")
  .action(async (joinToken: string, opts: { relay?: string; platform?: string; scope?: string }) => {
    const selected = await requirePlatform(opts.platform);
    const platforms = selected === "both" ? detectPlatforms() : [selected];

    const kp = await requireKeypair();
    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);
    const client = new TeamBridgeClient(relayUrl, kp.privateKey, token);

    try {
      const joinedTeam = await client.joinByInvite(joinToken);
      console.log(`Joined team: ${joinedTeam.name}`);

      const teamDef = remoteTeamToDefinition(joinedTeam);

      // Apply to each platform's native format
      for (const p of platforms) {
        console.log(`Setting up ${p}...`);
        const adapter = getAdapter(p);
        const scope: TeamScope = opts.scope === "project" || opts.scope === "global"
          ? opts.scope
          : await askScope(p);
        adapter.writeTeam(teamDef, scope);
        adapter.installHooks(relayUrl, token);
        console.log(`  ${p} configured.`);
      }

      // Write canonical YAML
      writeTeamYaml("agent-team.yaml", teamDef);
      console.log("Wrote agent-team.yaml.");

      saveConfig({
        platform: platforms.join(","),
        relay: relayUrl,
        token,
        teamId: joinedTeam.id,
      });
      console.log("Configuration saved.");
    } catch (err) {
      console.error("Failed to join team:", err);
      process.exit(1);
    }
  });

// --- apply ---
program
  .command("apply")
  .description("Re-apply team agents to local platform native format")
  .option("--platform <platform>", "Override platform detection (claude-code, openclaw)")
  .option("--scope <scope>", "Team scope: project or global")
  .action(async (opts: { platform?: string; scope?: string }) => {
    const selected = await requirePlatform(opts.platform);
    const platforms = selected === "both" ? detectPlatforms() : [selected];

    // Priority: YAML > platform adapters
    const sourceAdapter = getAdapter(platforms[0]);
    const { source, team } = resolveTeamSource("agent-team.yaml", sourceAdapter.readTeam());
    if (!team) {
      console.error("No team agents found. Run `teambridge init` or `teambridge join` first.");
      process.exit(1);
    }

    console.log(`Using team from ${source}${source === "yaml" ? " (agent-team.yaml)" : ""}.`);

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
      writeTeamYaml("agent-team.yaml", team);
      console.log("Generated agent-team.yaml from platform agents.");
    }
  });

// --- diff ---
program
  .command("diff")
  .description("Show differences between local agents and relay")
  .action(async () => {
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

      let hasDiff = false;

      if (localTeam.name !== remoteTeam.name) {
        console.log(`  team name: "${localTeam.name}" (local) vs "${remoteTeam.name}" (relay)`);
        hasDiff = true;
      }

      // Agents only in local
      for (const [name, role] of localAgents) {
        if (!remoteAgents.has(name)) {
          console.log(`  + ${name} (${role}) — local only`);
          hasDiff = true;
        } else if (remoteAgents.get(name) !== role) {
          console.log(`  ~ ${name}: role "${role}" (local) vs "${remoteAgents.get(name)}" (relay)`);
          hasDiff = true;
        }
      }

      // Agents only on relay
      for (const [name, role] of remoteAgents) {
        if (!localAgents.has(name)) {
          console.log(`  - ${name} (${role}) — relay only`);
          hasDiff = true;
        }
      }

      if (!hasDiff) {
        console.log("No differences between local and relay.");
      }
    } catch (err) {
      console.error("Failed to fetch relay state:", err);
      process.exit(1);
    }
  });

// --- sync ---
program
  .command("sync")
  .description("Sync with relay server")
  .action(async () => {
    const { client, platform, adapter } = requireClient();

    try {
      const hashes = adapter.getHashes();
      const result = await client.sync(platform, hashes);

      const entries = Object.entries(result.changes);
      if (entries.length > 0) {
        let applied = 0;
        for (const [key, remoteChange] of entries) {
          const localContent = adapter.readFile(key);
          const merged = resolveChange(key, localContent, remoteChange, 0);
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
      console.error("Sync failed:", err);
      process.exit(1);
    }
  });

// --- push ---
program
  .command("push")
  .description("Push local memory to relay")
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
      console.error("Push failed:", err);
      process.exit(1);
    }
  });

// --- status ---
program
  .command("status")
  .description("Show current configuration and sync state")
  .action(async () => {
    const config = loadConfig();
    if (!config) {
      console.log("TeamBridge is not initialized.");
      console.log("Run `teambridge init` to get started.");
      return;
    }

    console.log("TeamBridge Status:");
    console.log(`  Platform: ${config.platform}`);
    console.log(`  Relay:    ${config.relay}`);
    console.log(`  Token:    ${config.token.slice(0, 12)}...`);
    if (config.teamId) {
      console.log(`  Team ID:  ${config.teamId}`);
    }

    // Show local team info from native agent files
    const platform = primaryPlatform(config.platform);
    const adapter = getAdapter(platform);
    const localTeam = adapter.readTeam();
    if (localTeam) {
      console.log(`\nLocal Team: ${localTeam.name}`);
      console.log("  Agents:");
      for (const member of localTeam.members) {
        console.log(`    - ${member.name}: ${member.role}`);
      }
    } else {
      console.log("\nNo local team agents found.");
    }

    // Show relay state if configured
    if (config.teamId) {
      const kp = loadKeypair();
      if (kp) {
        const client = new TeamBridgeClient(config.relay, kp.privateKey, config.token);
        try {
          const remoteTeam = await client.getTeam(config.token);
          console.log(`\nRelay Team: ${remoteTeam.name}`);
          console.log("  Members:");
          for (const m of remoteTeam.members) {
            console.log(`    - ${m.name}: ${m.role} (${m.platform})`);
          }
        } catch {
          console.log("\nRelay unreachable.");
        }
      }
    }
  });

// --- daemon ---
program
  .command("daemon")
  .description("Start the background sync daemon")
  .option("--poll-interval <ms>", "Poll interval in milliseconds", "120000")
  .action(async (opts: { pollInterval: string }) => {
    const { client, platform, adapter } = requireClient();

    const { startDaemon } = await import("./daemon.js");
    const daemon = startDaemon({
      adapter,
      client,
      platform,
      pollInterval: parseInt(opts.pollInterval, 10),
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
  .description("Export team from relay to agent-team.yaml")
  .action(async () => {
    const { config, client } = requireClient();

    try {
      const remoteTeam = await client.getTeam(config.token);
      validateTeamName(remoteTeam.name);
      const team = remoteTeamToDefinition(remoteTeam);
      writeTeamYaml("agent-team.yaml", team);
      console.log(`Exported "${team.name}" (${team.members.length} agents) to agent-team.yaml.`);
    } catch (err) {
      console.error("Failed to fetch team from relay:", err);
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
    const selected = await requirePlatform(opts.platform);
    const platforms = selected === "both" ? detectPlatforms() : [selected];

    try {
      const remoteTeam = await client.getTeam(config.token);
      validateTeamName(remoteTeam.name);
      const team = remoteTeamToDefinition(remoteTeam);

      // Write YAML
      writeTeamYaml("agent-team.yaml", team);
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
      console.error("Pull failed:", err);
      process.exit(1);
    }
  });

// --- delete ---
program
  .command("delete")
  .description("Remove TeamBridge from this machine")
  .action(async () => {
    const config = loadConfig();
    if (!config) {
      console.log("TeamBridge is not initialized. Nothing to remove.");
      return;
    }

    const platforms = config.platform.split(",");

    console.log("\nThis will remove all TeamBridge agents, hooks, config, and team knowledge from this machine.");
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

    // Delete ~/.teambridge/ config
    const configDir = path.join(os.homedir(), ".teambridge");
    if (fs.existsSync(configDir)) {
      fs.rmSync(configDir, { recursive: true });
      console.log(`  Deleted ${configDir}`);
    }

    // Delete agent-team.yaml if present
    if (fs.existsSync("agent-team.yaml")) {
      fs.unlinkSync("agent-team.yaml");
      console.log("  Deleted agent-team.yaml");
    }

    console.log("\nTeamBridge removed. Run `teambridge init` or `teambridge join` to set up again.");
  });

program.parse();
