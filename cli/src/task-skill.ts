import type { Skill } from "./adapters/base.js";

/** Constant skill ID for the team tasks skill */
export const TEAM_TASKS_SKILL_ID = "team-tasks";

/** Create the team-tasks skill for inclusion in new teams */
export function createTeamTasksSkill(): Skill {
  return {
    id: TEAM_TASKS_SKILL_ID,
    title: "Team Tasks",
    description: "Check for and manage cross-agent tasks",
    alwaysApply: true,
    body: [
      "Check for assigned tasks at the start of each session:",
      "  teamrc task list --mine",
      "",
      "Pick a TODO task and claim it before starting work:",
      "  teamrc task claim <number>",
      "",
      "When finished with a task, mark it done:",
      "  teamrc task done <number>",
      "",
      "If you cannot complete a task, put it back for another agent:",
      "  teamrc task unclaim <number>",
      "",
      "To assign work to another team member:",
      '  teamrc task create "<description>" --assign <member>',
      "",
      "Workflow: always create a branch for your work, commit to the branch,",
      "and push the branch. Never commit or push directly to main.",
    ].join("\n"),
  };
}
