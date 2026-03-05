#!/usr/bin/env node

import { Command } from "commander";
import {
  generateKeypair,
  saveKeypair,
  loadKeypair,
  toToken,
} from "./auth.js";
import { RelayClient } from "./relay-client.js";
import {
  loadConfig,
  saveConfig,
  detectPlatform,
  getRelayUrl,
} from "./config.js";
import { getAdapter } from "./adapters/base.js";

const program = new Command();

program
  .name("teambridge")
  .description("TeamBridge — sync multi-agent teams across platforms")
  .version("0.1.0");

program
  .command("init")
  .description("Initialize TeamBridge for this platform")
  .option("--relay <url>", "Relay server URL")
  .action(async (opts: { relay?: string }) => {
    const platform = detectPlatform();
    if (!platform) {
      console.error(
        "Could not detect platform. Ensure ~/.claude or ~/.openclaw exists.",
      );
      process.exit(1);
    }
    console.log(`Detected platform: ${platform}`);

    let kp = loadKeypair();
    if (!kp) {
      kp = await generateKeypair();
      saveKeypair(kp);
      console.log("Generated new keypair.");
    } else {
      console.log("Using existing keypair.");
    }

    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);
    const adapter = getAdapter(platform);

    // Read existing team from adapter
    const existingTeam = adapter.readTeam();
    const teamName = existingTeam?.name ?? "my-team";
    const members = existingTeam?.members ?? [];

    // Create team on relay
    const client = new RelayClient(relayUrl, kp.privateKey, token);
    try {
      const relayTeam = await client.createTeam(
        teamName,
        members.map((m) => ({ ...m, platform })),
      );
      console.log(`Team created on relay: ${relayTeam.id}`);

      // Push memory
      const memory = adapter.readMemory();
      if (memory.length > 0) {
        const entries = memory.map((content, i) => ({
          key: `memory-${i}`,
          value: content,
        }));
        await client.push(relayTeam.id, entries);
        console.log(`Pushed ${entries.length} memory entries.`);
      }

      // Install hooks
      adapter.installHooks(relayUrl, token);
      console.log("Installed sync hooks.");

      // Save config
      saveConfig({
        platform,
        relay: relayUrl,
        token,
        teamId: relayTeam.id,
      });
      console.log("Configuration saved.");
      console.log(`\nShare this token to invite others: ${token}`);
    } catch (err) {
      console.error("Failed to initialize with relay:", err);
      // Save config even if relay is unreachable
      saveConfig({ platform, relay: relayUrl, token });
      console.log("Configuration saved (relay unreachable).");
    }
  });

program
  .command("join")
  .description("Join an existing team")
  .argument("<token>", "Team invitation token")
  .option("--relay <url>", "Relay server URL")
  .action(async (joinToken: string, opts: { relay?: string }) => {
    const platform = detectPlatform();
    if (!platform) {
      console.error(
        "Could not detect platform. Ensure ~/.claude or ~/.openclaw exists.",
      );
      process.exit(1);
    }
    console.log(`Detected platform: ${platform}`);

    let kp = loadKeypair();
    if (!kp) {
      kp = await generateKeypair();
      saveKeypair(kp);
      console.log("Generated new keypair.");
    }

    const token = toToken(kp.publicKey);
    const relayUrl = getRelayUrl(opts.relay);
    const client = new RelayClient(relayUrl, kp.privateKey, token);

    try {
      // Extract team ID from token (the relay will resolve it)
      const team = await client.getTeam(joinToken);
      console.log(`Joined team: ${team.name}`);

      const adapter = getAdapter(platform);
      adapter.writeTeam({
        name: team.name,
        members: team.members.map((m) => ({
          name: m.name,
          role: m.role,
        })),
      });
      console.log("Team scaffolded locally.");

      adapter.installHooks(relayUrl, token);
      console.log("Installed sync hooks.");

      saveConfig({
        platform,
        relay: relayUrl,
        token,
        teamId: team.id,
      });
      console.log("Configuration saved.");
    } catch (err) {
      console.error("Failed to join team:", err);
      process.exit(1);
    }
  });

program
  .command("sync")
  .description("Sync with relay server")
  .action(async () => {
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

    const adapter = getAdapter(config.platform);
    const client = new RelayClient(config.relay, kp.privateKey, config.token);

    try {
      const hashes = adapter.getHashes();
      const result = await client.sync(config.teamId, hashes);

      if (result.buffered_entries.length > 0) {
        const entries = result.buffered_entries.map((e) => e.value);
        adapter.writeMemory(entries);
        console.log(
          `Applied ${result.buffered_entries.length} buffered entries.`,
        );
      }

      if (result.team) {
        adapter.writeTeam({
          name: result.team.name,
          members: result.team.members.map((m) => ({
            name: m.name,
            role: m.role,
          })),
        });
        console.log("Team definition updated.");
      }

      console.log(`Sync complete. Status: ${result.status}`);
    } catch (err) {
      console.error("Sync failed:", err);
      process.exit(1);
    }
  });

program
  .command("push")
  .description("Push local memory to relay")
  .action(async () => {
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

    const adapter = getAdapter(config.platform);
    const client = new RelayClient(config.relay, kp.privateKey, config.token);

    try {
      const memory = adapter.readMemory();
      if (memory.length === 0) {
        console.log("No memory entries to push.");
        return;
      }

      const entries = memory.map((content, i) => ({
        key: `memory-${i}`,
        value: content,
      }));
      await client.push(config.teamId, entries);
      console.log(`Pushed ${entries.length} memory entries.`);
    } catch (err) {
      console.error("Push failed:", err);
      process.exit(1);
    }
  });

program
  .command("status")
  .description("Show current configuration")
  .action(() => {
    const config = loadConfig();
    if (!config) {
      console.log("TeamBridge is not initialized.");
      console.log("Run `teambridge init` to get started.");
      return;
    }

    console.log("TeamBridge Status:");
    console.log(`  Platform: ${config.platform}`);
    console.log(`  Relay:    ${config.relay}`);
    console.log(`  Token:    ${config.token}`);
    if (config.teamId) {
      console.log(`  Team ID:  ${config.teamId}`);
    }
  });

program.parse();
