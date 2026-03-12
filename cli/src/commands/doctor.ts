import type { Command } from "commander";
import * as p from "@clack/prompts";
import { loadKeypair } from "../auth.js";
import { loadConfig, detectPlatforms, getRelayUrl } from "../config.js";
import { getAdapter } from "../adapters/base.js";
import { readTeamYaml, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";

export function registerDoctor(program: Command): void {
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
        const doctorRelayUrl = getRelayUrl();
        try {
          const start = Date.now();
          await fetch(`${doctorRelayUrl}/api/teams/${encodeURIComponent(config.token)}`);
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
}
