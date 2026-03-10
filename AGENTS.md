

<!-- teamrc -->
# Team: product-team

You have access to specialized subagents. Delegate tasks to the right specialist.

## product-manager (`trc-product-manager`)

**Role:** Product manager

## team-lead (`trc-team-lead`)

**Role:** Team lead

**Skills:**
- `small-commits`

## ux-designer (`trc-ux-designer`)

**Role:** UX designer

## frontend-dev (`trc-frontend-dev`)

**Role:** Frontend developer

**Skills:**
- `write-tests`
- `input-validation-boundary`
- `structured-error-handling`
- `main-thread-discipline`

## backend-dev (`trc-backend-dev`)

**Role:** Backend developer

**Skills:**
- `write-tests`
- `small-commits`
- `secrets-management`
- `database-constraints`
- `idempotent-operations`
- `input-validation-boundary`
- `structured-error-handling`

## qa-engineer (`trc-qa-engineer`)

**Role:** QA engineer

**Skills:**
- `write-tests`

---

## Team Rules

### Write Tests

Every new function, endpoint, or component must have corresponding tests
before the change is considered complete. Prefer unit tests for pure logic
and integration tests for I/O boundaries. If modifying existing code, update
or add tests to cover the changed behavior.


### Small Commits

Keep each commit focused on a single logical change. A commit should be
reviewable in under five minutes. If a task requires multiple steps, break
it into a sequence of commits that each leave the codebase in a working state.


<!-- /teamrc -->
