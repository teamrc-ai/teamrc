

<!-- teamrc -->
## teamrc Team: product-team

This project has a synced agent team managed by teamrc.

Members:
- **product-manager** — Product manager
- **team-lead** — Team lead
- **ux-designer** — UX designer
- **frontend-dev** — Frontend developer
- **backend-dev** — Backend developer
- **qa-engineer** — QA engineer

Each member is defined as an agent in `.gemini/agents/`. Delegate tasks to them based on their roles.

### Team Rules

#### Write Tests

Every new function, endpoint, or component must have corresponding tests
before the change is considered complete. Prefer unit tests for pure logic
and integration tests for I/O boundaries. If modifying existing code, update
or add tests to cover the changed behavior.


#### Small Commits

Keep each commit focused on a single logical change. A commit should be
reviewable in under five minutes. If a task requires multiple steps, break
it into a sequence of commits that each leave the codebase in a working state.


<!-- /teamrc -->
