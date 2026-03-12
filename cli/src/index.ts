#!/usr/bin/env node

import { program } from "./utils.js";
import { registerInit } from "./commands/init.js";
import { registerJoin } from "./commands/join.js";
import { registerApply } from "./commands/apply.js";
import { registerImport } from "./commands/import.js";
import { registerDiff } from "./commands/diff.js";
import { registerSync } from "./commands/sync.js";
import { registerPush } from "./commands/push.js";
import { registerPull } from "./commands/pull.js";
import { registerStatus } from "./commands/status.js";
import { registerDaemon } from "./commands/daemon.js";
import { registerExport } from "./commands/export.js";
import { registerLogin } from "./commands/login.js";
import { registerClone } from "./commands/clone.js";
import { registerDashboard } from "./commands/dashboard.js";
import { registerInvite } from "./commands/invite.js";
import { registerShare } from "./commands/share.js";
import { registerClaim } from "./commands/claim.js";
import { registerWhoami } from "./commands/whoami.js";
import { registerDoctor } from "./commands/doctor.js";
import { registerDelete } from "./commands/delete.js";
import { registerAddMember } from "./commands/add-member.js";
import { registerListTemplates } from "./commands/list-templates.js";
import { registerListAgents } from "./commands/list-agents.js";
import { registerErase } from "./commands/erase.js";

// Register all commands
registerInit(program);
registerJoin(program);
registerApply(program);
registerImport(program);
registerDiff(program);
registerSync(program);
registerPush(program);
registerPull(program);
registerStatus(program);
registerDaemon(program);
registerExport(program);
registerLogin(program);
registerClone(program);
registerDashboard(program);
registerInvite(program);
registerShare(program);
registerClaim(program);
registerWhoami(program);
registerDoctor(program);
registerDelete(program);
registerAddMember(program);
registerListTemplates(program);
registerListAgents(program);
registerErase(program);

// Use parseAsync so the process exits cleanly after async commands complete
// (Node's fetch keep-alive connections would otherwise hold the event loop open)
program.parseAsync().then(() => process.exit(0));
