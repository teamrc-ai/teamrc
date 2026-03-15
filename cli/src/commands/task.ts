import type { Command } from "commander";
import * as p from "@clack/prompts";
import { requireRelayContext, isNonInteractive, handleCancel, cliCmd } from "../utils.js";
import type { TaskItem } from "../client.js";
import { readLocalYaml } from "../team-yaml.js";

const STATUS_LABELS: Record<string, string> = {
  todo: "TODO",
  in_progress: "IN PROGRESS",
  done: "DONE",
  cancelled: "CANCELLED",
  failed: "FAILED",
};

function formatTask(task: TaskItem): string {
  let line = `  #${task.number}  ${task.assignee.padEnd(14)} ${task.description}`;
  if (task.result && (task.status === "done" || task.status === "failed")) {
    const truncated = task.result.length > 120 ? task.result.slice(0, 117) + "..." : task.result;
    line += `\n      ${truncated}`;
  }
  return line;
}

export function registerTask(program: Command): void {
  const task = program
    .command("task")
    .description("Manage team tasks");

  task
    .command("create")
    .description("Create a new task")
    .argument("<description>", "Task description")
    .option("--assign <member>", "Assign to team member")
    .action(async (description: string, opts: { assign?: string }) => {
      p.intro("teamrc");
      const ctx = requireRelayContext();
      const memberNames = ctx.team.members.map((m) => m.name);

      let assignee = opts.assign;
      if (!assignee) {
        if (isNonInteractive()) {
          p.log.error("--assign is required in non-interactive mode.");
          process.exit(1);
        }
        const choice = await p.select({
          message: "Assign to",
          options: ctx.team.members.map((m) => ({
            value: m.name,
            label: m.name,
            hint: m.role,
          })),
        });
        handleCancel(choice);
        assignee = choice as string;
      }

      if (!memberNames.includes(assignee)) {
        p.log.error(`"${assignee}" is not a team member. Members: ${memberNames.join(", ")}`);
        process.exit(1);
      }

      try {
        const created = await ctx.client.createTask(description, assignee);
        p.log.step(`Task #${created.number} created → ${created.assignee}`);
        p.outro("Done.");
      } catch (err) {
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });

  task
    .command("list")
    .description("List team tasks")
    .option("--status <status>", "Filter by status")
    .option("--mine", "Show only tasks assigned to active members")
    .action(async (opts: { status?: string; mine?: boolean }) => {
      p.intro("teamrc");
      const ctx = requireRelayContext();

      try {
        const listOpts: { status?: string; assignee?: string } = {};
        if (opts.status) listOpts.status = opts.status;

        let tasks = await ctx.client.listTasks(listOpts);

        // Filter --mine: use activeMembers from local.yaml, or all members
        if (opts.mine) {
          const localConfig = readLocalYaml();
          const activeNames = localConfig.activeMembers ?? ctx.team.members.map((m) => m.name);
          tasks = tasks.filter((t) => activeNames.includes(t.assignee));
        }

        if (tasks.length === 0) {
          p.log.info("No tasks found.");
          p.outro("Done.");
          return;
        }

        // Group by status
        const grouped: Record<string, TaskItem[]> = {};
        for (const t of tasks) {
          (grouped[t.status] ??= []).push(t);
        }

        const lines: string[] = [];
        for (const status of ["todo", "in_progress", "done", "cancelled", "failed"]) {
          if (!grouped[status]) continue;
          lines.push(`\n${STATUS_LABELS[status] ?? status}`);
          for (const t of grouped[status]) {
            lines.push(formatTask(t));
          }
        }

        p.log.info(lines.join("\n"));
        p.outro(`${tasks.length} task(s).`);
      } catch (err) {
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });

  task
    .command("done")
    .description("Mark a task as done")
    .argument("<number>", "Task number")
    .action(async (numberStr: string) => {
      p.intro("teamrc");
      const ctx = requireRelayContext();
      const number = parseInt(numberStr, 10);
      if (isNaN(number)) { p.log.error("Invalid task number."); process.exit(1); }

      try {
        const updated = await ctx.client.updateTask(number, "done");
        p.log.step(`Task #${updated.number} marked done.`);
        p.outro("Done.");
      } catch (err) {
        const msg = (err as Error).message;
        if (msg.includes("invalid status transition")) {
          p.log.error(`Task #${number} must be claimed first. Run \`${cliCmd(`task claim ${number}`)}\` then retry.`);
        } else {
          p.log.error(msg);
        }
        process.exit(1);
      }
    });

  task
    .command("claim")
    .description("Claim a task (set to in_progress)")
    .argument("<number>", "Task number")
    .action(async (numberStr: string) => {
      p.intro("teamrc");
      const ctx = requireRelayContext();
      const number = parseInt(numberStr, 10);
      if (isNaN(number)) { p.log.error("Invalid task number."); process.exit(1); }

      try {
        const updated = await ctx.client.updateTask(number, "in_progress");
        p.log.step(`Task #${updated.number} claimed.`);
        p.outro("Done.");
      } catch (err) {
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });

  task
    .command("unclaim")
    .description("Put a task back (in_progress → todo)")
    .argument("<number>", "Task number")
    .action(async (numberStr: string) => {
      p.intro("teamrc");
      const ctx = requireRelayContext();
      const number = parseInt(numberStr, 10);
      if (isNaN(number)) { p.log.error("Invalid task number."); process.exit(1); }

      try {
        const updated = await ctx.client.updateTask(number, "todo");
        p.log.step(`Task #${updated.number} unclaimed.`);
        p.outro("Done.");
      } catch (err) {
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });

  task
    .command("cancel")
    .description("Cancel a task")
    .argument("<number>", "Task number")
    .action(async (numberStr: string) => {
      p.intro("teamrc");
      const ctx = requireRelayContext();
      const number = parseInt(numberStr, 10);
      if (isNaN(number)) { p.log.error("Invalid task number."); process.exit(1); }

      try {
        const updated = await ctx.client.updateTask(number, "cancelled");
        p.log.step(`Task #${updated.number} cancelled.`);
        p.outro("Done.");
      } catch (err) {
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
