# Project Configuration

## TeamBridge Team: product-team

This project has a synced agent team managed by TeamBridge.

Members:
- **product-manager** — Define requirements, prioritize the backlog, write user stories and acceptance criteria
- **team-lead** — Break down work, coordinate across agents, make technical decisions, unblock the team
- **ux-designer** — Design user flows, wireframes, and UI components. Ensure accessibility and usability
- **frontend-dev** — Build UI components, integrate APIs, implement responsive layouts and interactions
- **backend-dev** — Design APIs, write business logic, manage data models and database queries
- **qa-engineer** — Write test plans, automate E2E and integration tests, validate edge cases and regressions

Each member is defined as a subagent in `.claude/agents/`. Delegate tasks to them based on their roles.

### Team Knowledge
Shared findings and decisions are stored in `.claude/team-knowledge.md`. Read this file at the start of every session for context from other agents and machines. When you discover something important (architecture decisions, gotchas, debugging insights), append it to this file so other team members can benefit.
