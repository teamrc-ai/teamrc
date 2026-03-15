import * as os from "node:os";
import { Command } from "commander";
import * as p from "@clack/prompts";
import { createRequire } from "node:module";
import {
  generateKeypair,
  saveKeypair,
  loadKeypair,
  toToken,
} from "./auth.js";
import { TeamrcClient, TeamNotFoundError } from "./client.js";
import {
  loadConfig,
  saveConfig,
  detectPlatforms,
  detectInstalledPlatforms,
  getRelayUrl,
} from "./config.js";
import { getAdapter, slugify, VALID_PLATFORMS, SUPPORTED_PLATFORMS, UNIMPLEMENTED_PLATFORMS, GLOBAL_ONLY_PLATFORMS, PROJECT_ONLY_PLATFORMS, type TeamScope, type TeamDefinition, type PlatformAdapter } from "./adapters/base.js";
import { resolveTeam, listTeams, type TeamTemplate } from "./catalog.js";
import { readTeamYaml, writeTeamYaml, validateTeamName, TEAM_YAML, GLOBAL_TEAM_YAML } from "./team-yaml.js";
import { writeSyncState } from "./sync-state.js";
import type { TeamrcConfig } from "./config.js";
import { openBrowserIfSameOrigin } from "./browser.js";

// ---------------------------------------------------------------------------
// CLI name detection  --  use the right invocation form in messages
// ---------------------------------------------------------------------------
function detectCliName(): string {
  const scriptPath = process.argv[1] || "";
  if (scriptPath.includes("_npx") || process.env.npm_command === "exec") {
    return "npx @teamrc/cli";
  }
  return "teamrc";
}

/** The CLI command prefix, e.g. "teamrc" or "npx @teamrc/cli" */
export const CLI_NAME = detectCliName();

/** Format a CLI command for display, e.g. cliCmd("init") → "teamrc init" or "npx @teamrc/cli init" */
export function cliCmd(subcommand: string): string {
  return `${CLI_NAME} ${subcommand}`;
}

// ---------------------------------------------------------------------------
// Program definition  --  single shared instance
// ---------------------------------------------------------------------------
const require = createRequire(import.meta.url);
const { version: CLI_VERSION } = require("../package.json") as { version: string };

export const program = new Command();

program
  .name(CLI_NAME)
  .description("teamrc -- sync multi-agent teams across platforms")
  .version(CLI_VERSION)
  .option("--json", "Output as JSON")
  .option("-y, --yes", "Skip all prompts, use defaults")
  .option("--no-color", "Disable colored output")
  .option("-v, --verbose", "Show detailed output");

// ---------------------------------------------------------------------------
// Global options  --  parsed from root program, threaded through all commands
// ---------------------------------------------------------------------------
export interface GlobalOpts {
  json?: boolean;
  yes?: boolean;
  verbose?: boolean;
  color?: boolean;  // Commander flips --no-color → color=false
}

export function globals(): GlobalOpts {
  return program.opts() as GlobalOpts;
}

/** True when running in a non-interactive environment. */
export function isNonInteractive(): boolean {
  return !process.stdin.isTTY || !!globals().yes;
}

/**
 * Require interactive input or bail with a helpful error message.
 * Pass the flag name that would skip the prompt (e.g. "--yes", "--platform").
 */
export function requireTTY(flagHint: string): void {
  if (!process.stdin.isTTY && !globals().yes) {
    p.log.error(
      `This command requires interactive input but stdin is not a TTY.\n` +
      `  Use ${flagHint} to skip this prompt.`,
    );
    process.exit(1);
  }
}

// ---------------------------------------------------------------------------
// Cancel handler  --  graceful Ctrl-C for all prompts
// ---------------------------------------------------------------------------
export function handleCancel(value: unknown): void {
  if (p.isCancel(value)) {
    p.cancel("Cancelled.");
    process.exit(0);
  }
}

// ---------------------------------------------------------------------------
// Platform resolution with clack multiselect
// ---------------------------------------------------------------------------
export async function requirePlatforms(override?: string, scope?: TeamScope): Promise<string[]> {
  if (override) {
    const requested = override.split(",").map((s) => s.trim()).filter(Boolean);
    for (const pl of requested) {
      if (!VALID_PLATFORMS.includes(pl as typeof VALID_PLATFORMS[number])) {
        p.log.error(`Unknown platform: ${pl}. Valid options: ${SUPPORTED_PLATFORMS.join(", ")}`);
        process.exit(1);
      }
      if (UNIMPLEMENTED_PLATFORMS.includes(pl)) {
        p.log.error(`Platform "${pl}" is not yet supported. Available: ${SUPPORTED_PLATFORMS.join(", ")}`);
        process.exit(1);
      }
    }
    return requested;
  }

  // Use installed-platform detection (folder exists) so init/join can target
  // platforms before any trc-* agent files have been written.
  const detected = detectInstalledPlatforms();
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

  const selectablePlatforms = VALID_PLATFORMS.filter(
    (pl) => !UNIMPLEMENTED_PLATFORMS.includes(pl),
  );

  const isDisabled = (pl: string): boolean => {
    if (scope === "project" && GLOBAL_ONLY_PLATFORMS.includes(pl)) return true;
    if (scope === "global" && PROJECT_ONLY_PLATFORMS.includes(pl)) return true;
    return false;
  };

  const scopeHint = (pl: string): string | undefined => {
    if (scope === "project" && GLOBAL_ONLY_PLATFORMS.includes(pl)) return "global only";
    if (scope === "global" && PROJECT_ONLY_PLATFORMS.includes(pl)) return "project only";
    return detected.includes(pl) ? "detected" : undefined;
  };

  const selected = await p.multiselect({
    message: "Which platforms?",
    options: selectablePlatforms.map((pl) => ({
      value: pl,
      label: pl,
      hint: scopeHint(pl),
      disabled: isDisabled(pl),
    })),
    initialValues: detected.filter(
      (pl) => !(UNIMPLEMENTED_PLATFORMS as readonly string[]).includes(pl) && !isDisabled(pl),
    ),
    required: true,
  });
  handleCancel(selected);
  return selected as string[];
}

// ---------------------------------------------------------------------------
// Keypair helper
// ---------------------------------------------------------------------------
export async function requireKeypair() {
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
export interface TeamContext {
  team: TeamDefinition;
  scope: TeamScope;
  config: TeamrcConfig;
  client: TeamrcClient | null;
  platforms: string[];
  adapters: PlatformAdapter[];
}

export function requireTeamContext(): TeamContext {
  const config = loadConfig();
  if (!config) {
    p.log.error(`Not initialized. Run \`${cliCmd("init")}\` first.`);
    process.exit(1);
  }
  const kp = loadKeypair();
  if (!kp) {
    p.log.error(`No keypair found. Run \`${cliCmd("init")}\` first.`);
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
    const relay = getRelayUrl(undefined, yamlTeam.relay);
    const platforms = yamlTeam.platforms ?? detectPlatforms();
    const client = new TeamrcClient(relay, kp.privateKey, config.token, yamlTeam.teamId);
    return {
      team: yamlTeam,
      scope: "project",
      config,
      client,
      platforms,
      adapters: platforms.map((pl) => getAdapter(pl, slugify(yamlTeam.name))),
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
    const relay = getRelayUrl(undefined, globalTeam.relay);
    const platforms = globalTeam.platforms ?? detectPlatforms();
    const client = new TeamrcClient(relay, kp.privateKey, config.token, globalTeam.teamId);
    return {
      team: globalTeam,
      scope: "global",
      config,
      client,
      platforms,
      adapters: platforms.map((pl) => getAdapter(pl, slugify(globalTeam.name))),
    };
  }

  // Check project YAML: local-only vs cloned
  if (yamlTeam && !yamlTeam.teamId) {
    if (yamlTeam.cloneToken) {
      p.log.error(`This is a cloned team (read-only). Run \`${cliCmd("init")}\` to create your own team, or \`${cliCmd("pull")}\` to fetch updates.`);
      process.exit(1);
    }
    const platforms = yamlTeam.platforms ?? detectPlatforms();
    return {
      team: yamlTeam,
      scope: "project",
      config,
      client: null,
      platforms,
      adapters: platforms.map((pl) => getAdapter(pl, slugify(yamlTeam.name))),
    };
  }

  // Check global YAML: local-only vs cloned
  if (globalTeam && !globalTeam.teamId) {
    if (globalTeam.cloneToken) {
      p.log.error(`This is a cloned team (read-only). Run \`${cliCmd("init")}\` to create your own team, or \`${cliCmd("pull")}\` to fetch updates.`);
      process.exit(1);
    }
    const platforms = globalTeam.platforms ?? detectPlatforms();
    return {
      team: globalTeam,
      scope: "global",
      config,
      client: null,
      platforms,
      adapters: platforms.map((pl) => getAdapter(pl, slugify(globalTeam.name))),
    };
  }

  p.log.error(`No team configured. Run \`${cliCmd("init")}\` or \`${cliCmd("join")}\`.`);
  process.exit(1);
}

export function requireRelayContext(): TeamContext & { client: TeamrcClient } {
  const ctx = requireTeamContext();
  if (!ctx.client) {
    p.log.error(
      `This team is local-only (not connected to a relay).\n` +
      `Run \`${cliCmd("push")}\` to connect it to teamrc.ai.`
    );
    process.exit(1);
  }
  return ctx as TeamContext & { client: TeamrcClient };
}

// ---------------------------------------------------------------------------
// Device auth flow with spinner
// ---------------------------------------------------------------------------
export async function deviceAuthFlow(client: TeamrcClient, machineName: string, relayUrl: string): Promise<boolean> {
  p.log.info(`Your machine name ("${machineName}") will be visible to the team owner.`);

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

  const verifyUrl = `${deviceAuth.verification_url}?code=${encodeURIComponent(deviceAuth.user_code)}`;

  p.note(
    `Open in browser: ${verifyUrl}\nCode: ${deviceAuth.user_code}`,
    "Authenticate",
  );

  // Only auto-open URLs that point back to the configured relay.
  openBrowserIfSameOrigin(verifyUrl, relayUrl);

  s.start("Waiting for confirmation... (press Ctrl-C to cancel)");

  const MAX_EXPIRES_SEC = 900;
  const MIN_INTERVAL_SEC = 1;
  const MAX_INTERVAL_SEC = 30;
  const startTime = Date.now();
  const timeoutMs = Math.min(deviceAuth.expires_in, MAX_EXPIRES_SEC) * 1000;
  const intervalMs = Math.max(MIN_INTERVAL_SEC, Math.min(deviceAuth.interval, MAX_INTERVAL_SEC)) * 1000;

  const MAX_RETRIES = 5;
  let consecutiveErrors = 0;
  let cancelled = false;

  const onSigint = () => { cancelled = true; };
  process.once("SIGINT", onSigint);

  try {
    while (!cancelled && Date.now() - startTime < timeoutMs) {
      await new Promise((resolve) => setTimeout(resolve, intervalMs));
      if (cancelled) break;

      try {
        const result = await client.pollDeviceAuth(deviceAuth.device_code);
        consecutiveErrors = 0; // reset on success
        if (result.status === "confirmed") {
          s.stop("Authenticated.");

          p.log.success(`Signed in as ${result.email}`);
          p.log.info(`Machine "${machineName}" linked.`);

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
        consecutiveErrors++;
        if (consecutiveErrors >= MAX_RETRIES) {
          s.error("Too many polling errors. Please check your connection and try again.");
          if (globals().verbose) {
            p.log.error(String(err));
          }
          return false;
        }
        // Continue polling  --  transient error
      }
    }
  } finally {
    process.removeListener("SIGINT", onSigint);
  }

  if (cancelled) {
    s.stop("Canceled.");
    return false;
  }

  s.error("Device authorization timed out. Please try again.");
  return false;
}

// ---------------------------------------------------------------------------
// Scope selection with clack select
// ---------------------------------------------------------------------------
export async function selectScope(opts: { scope?: string; global?: boolean }): Promise<TeamScope> {
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

/** Resolve effective scope for a platform (respects global-only and project-only constraints) */
export function effectiveScope(platform: string, scope: TeamScope): TeamScope {
  if (GLOBAL_ONLY_PLATFORMS.includes(platform)) return "global";
  if (PROJECT_ONLY_PLATFORMS.includes(platform)) return "project";
  return scope;
}

// ---------------------------------------------------------------------------
// JSON output helper
// ---------------------------------------------------------------------------
export function jsonOutput(data: unknown): void {
  process.stdout.write(JSON.stringify(data, null, 2) + "\n");
}

// ---------------------------------------------------------------------------
// Template selection helpers
// ---------------------------------------------------------------------------

/** Prompt the user to select a team template, or resolve from --team flag */
export async function selectTemplate(teamFlag?: string): Promise<TeamTemplate> {
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
export async function promptTeamName(defaultName: string): Promise<string> {
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

// ---------------------------------------------------------------------------
// Team not found recovery  --  re-create team on relay
// ---------------------------------------------------------------------------

/**
 * Handle a TeamNotFoundError by offering to re-create the team on the relay.
 * Returns true if the team was re-created, false if the user declined.
 */
export async function handleTeamNotFound(ctx: TeamContext & { client: TeamrcClient }): Promise<boolean> {
  p.log.warn("This team no longer exists on the relay.");

  if (isNonInteractive()) {
    p.log.info(`Run \`${cliCmd("push")}\` to create a new team from your local definition, or \`${cliCmd("delete")}\` to clean up.`);
    return false;
  }

  const shouldRecreate = await p.confirm({
    message: "Create a new team on the relay from your local definition? (new team ID, new invites)",
    initialValue: true,
  });
  handleCancel(shouldRecreate);
  if (!shouldRecreate) {
    p.log.info(`Run \`${cliCmd("delete")}\` to clean up local files.`);
    return false;
  }

  const { client, team, adapters } = ctx;
  const adapter = adapters[0];
  const knowledge = adapter.readKnowledge();

  const s = p.spinner();
  s.start("Creating new team on relay...");
  const relayTeam = await client.createTeam(
    team.name,
    team.members.map((m) => ({
      name: m.name,
      role: m.role,
      ...(m.skills?.length ? { skills: m.skills } : {}),
    })),
    team.skills,
    knowledge || undefined,
  );
  s.stop("New team created.");

  // Update local state with new team ID
  team.teamId = relayTeam.id;
  client.setTeamId(relayTeam.id);

  const yamlPath = ctx.scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML;
  writeTeamYaml(yamlPath, team);
  writeSyncState({});

  if (relayTeam.owner_claim_secret) {
    const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
    const yellow = (s: string) => `\x1b[33m${s}\x1b[0m`;
    p.log.warn(
      `${yellow("Save this to claim ownership:")}  ${relayTeam.owner_claim_secret}\n` +
      `${dim(`Run \`${cliCmd("claim <token>")}\` anytime, or link your account now to claim automatically.`)}`,
    );

    if (!isNonInteractive()) {
      const shouldLink = await p.confirm({
        message: "Link your account? (claims ownership automatically)",
        initialValue: true,
      });
      if (!p.isCancel(shouldLink) && shouldLink) {
        const machineName = os.hostname();
        const relayUrl = getRelayUrl(undefined, team.relay);
        const success = await deviceAuthFlow(client, machineName, relayUrl);
        if (success) {
          try {
            await client.claimOwnership(relayTeam.owner_claim_secret);
            p.log.step("Ownership claimed.");
          } catch {
            p.log.warn(`Account linked, but ownership claim failed. Run \`${cliCmd("claim <token>")}\` later.`);
          }
        }
      }
    }
  } else {
    p.log.step("You own this team.");
  }

  return true;
}

// ---------------------------------------------------------------------------
// Active-member selection  --  interactive picker or --members flag parsing
// ---------------------------------------------------------------------------
export async function selectActiveMembers(
  allMembers: { name: string; role: string }[],
  membersFlag?: string,
): Promise<string[] | undefined> {
  const allNames = allMembers.map((m) => m.name);

  if (membersFlag) {
    const names = membersFlag.split(",").map((s) => s.trim()).filter(Boolean);
    for (const n of names) {
      if (!allNames.includes(n)) {
        p.log.error(`"${n}" is not a team member. Members: ${allNames.join(", ")}`);
        process.exit(1);
      }
    }
    return names.length === allNames.length && allNames.every((n) => names.includes(n))
      ? undefined
      : names;
  }

  if (isNonInteractive()) return undefined;

  const choices = await p.multiselect({
    message: "Which agents should be active on this machine?",
    options: allMembers.map((m) => ({
      value: m.name,
      label: m.name,
      hint: m.role,
    })),
    initialValues: allNames,
    required: true,
  });
  handleCancel(choices);
  const selected = choices as string[];

  return selected.length === allNames.length && allNames.every((n) => selected.includes(n))
    ? undefined
    : selected;
}
