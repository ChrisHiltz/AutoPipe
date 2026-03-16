# Fix Pattern Library — Build Plan Review

Reference for scoring and remediating build plans across 15 rubric categories.
Each category: what excellence looks like, common defects, and concrete fix actions.

---

## 1. Task Decomposition Quality

**What 10/10 looks like:**
- Every task is 2-8 hours estimated, produces exactly one PR, and delivers a vertical slice (schema + logic + test + migration if applicable).
- Task scope boundaries are explicit: "This task DOES X. This task DOES NOT do Y."
- Each task has a single acceptance-testable outcome stated in the AC block.

**What 9/10 looks like:**
- Tasks are well-sized but 1-2 tasks bundle two concerns (e.g., "set up DB and implement auth middleware") that should be separate PRs.
- Scope boundaries exist but rely on implicit context rather than explicit exclusions.

**Common 7-8 defects:**
- Tasks exceed 8 hours because they combine infrastructure setup with feature logic.
- Tasks described as horizontal layers ("build all API routes") instead of vertical slices.
- No explicit scope exclusions, leading agents to gold-plate or under-deliver.

**Fix actions when score < 9:**
1. Split any task estimated >8h into sub-tasks, each producing one PR with one testable outcome.
2. Convert horizontal-layer tasks into vertical slices: each task touches schema, service logic, route handler, and test file for ONE feature.
3. Add explicit scope fences to every task: `### Scope: Does / Does Not` section listing inclusions and exclusions.
4. Ensure every task AC ends with a concrete verification command: `npm test -- --grep "feature-name"` or `curl localhost:3000/endpoint | jq .field`.
5. Add estimated hours to every task. Flag any task without an estimate.

---

## 2. Parallelization Safety

**What 10/10 looks like:**
- Parallel task groups are explicitly labeled (e.g., "Phase 2: Tasks 2.1-2.4 run concurrently").
- Shared resources (DB tables, config files, shared modules) are listed per task with read/write annotations.
- No two concurrent tasks write to the same file or DB table without an explicit coordination note.

**What 9/10 looks like:**
- Parallel groups are defined but one shared resource (e.g., `schema.prisma`, `docker-compose.yml`) is written by two concurrent tasks without a noted merge strategy.
- Race conditions in runtime are addressed but file-level conflicts during development are not.

**Common 7-8 defects:**
- Plan says tasks are parallel but multiple tasks modify `package.json`, `tsconfig.json`, or shared config files.
- No shared-resource inventory — parallelism is assumed safe without analysis.
- Runtime concurrency risks (e.g., two services writing to the same DB table) are unaddressed.

**Fix actions when score < 9:**
1. Add a `### Shared Resources` section to each task listing files and tables it reads/writes.
2. Create a shared-resource conflict matrix in the plan: rows = resources, columns = tasks, cells = R/W.
3. For every file written by 2+ concurrent tasks, add one of: (a) serialize those tasks, (b) assign file ownership to one task with others consuming via import, (c) document a merge sequence.
4. Add runtime concurrency notes for tasks that write to the same DB table: specify row-level locking, optimistic concurrency, or queue-based serialization.
5. Move shared config changes (e.g., `docker-compose.yml` service additions) to a dedicated prerequisite task that runs before the parallel group.

---

## 3. Dependency Sequencing Quality

**What 10/10 looks like:**
- Dependencies form a valid DAG with no cycles; every `depends_on` references a concrete task ID and states the reason (e.g., "needs User table from T-1.2").
- Critical path is identified and sequenced to minimize total wall-clock time.
- No implicit dependencies — if Task B reads a file Task A creates, the dependency is declared.

**What 9/10 looks like:**
- DAG is valid but 1-2 dependency reasons are vague ("depends on prior setup") instead of citing a specific artifact.
- One non-critical dependency is over-constrained (tasks serialized unnecessarily).

**Common 7-8 defects:**
- Circular dependencies exist (A depends on B depends on C depends on A).
- Dependencies reference phase names instead of specific task IDs.
- Implicit ordering assumed from document position rather than declared edges.

**Fix actions when score < 9:**
1. Convert every `depends_on` value to a specific task ID with artifact reason: `depends_on: [T-1.2] # needs users table migration`.
2. Validate the DAG: ensure no circular references. Draw or describe the graph explicitly in the plan.
3. Remove false dependencies: for each edge, ask "can this task start with a stub/mock instead?" If yes, remove the hard dependency and add a stub note.
4. Add a critical-path summary showing the longest sequential chain and its total estimated hours.
5. Replace phase-level ordering with task-level ordering. "Phase 2 after Phase 1" becomes explicit per-task edges.

---

## 4. Instruction Clarity for Coding Agents

**What 10/10 looks like:**
- Every task specifies: input artifacts (files/schemas/APIs it reads), output artifacts (files/endpoints it creates), constraints (libraries to use, patterns to follow), and verification commands.
- No task requires the agent to make architectural decisions — all decisions are pre-made and referenced (DA-N, BL-N from DECISIONS-LOCKED.md).
- Code examples or pseudocode are provided for non-obvious patterns.

**What 9/10 looks like:**
- Instructions are clear but 1-2 tasks leave a technology choice open (e.g., "use a suitable validation library") instead of specifying one.
- Decision references exist but not every AC links back to its governing decision.

**Common 7-8 defects:**
- Tasks describe goals ("implement authentication") without specifying the approach, library, or pattern.
- No input/output artifact lists — agents must infer what files to read and create.
- Ambiguous ACs like "works correctly" or "handles errors properly."

**Fix actions when score < 9:**
1. Add `### Inputs`, `### Outputs`, and `### Constraints` sections to every task.
2. Replace every ambiguous AC with a concrete assertion: "returns 401 with `{error: 'unauthorized'}` when token is expired" instead of "handles auth errors."
3. Add decision cross-references (DA-N, BL-N, CC-N) to every AC that implements a locked decision from DECISIONS-LOCKED.md.
4. For every task that uses a library, specify the exact package name and version constraint: `zod@^3.22` not "a validation library."
5. Add pseudocode or signature stubs for any function the agent must implement that follows a non-obvious pattern.
6. Replace "follow best practices" with explicit pattern references: "use the repository pattern from `src/repositories/base.repository.ts`."

---

## 5. Determinism of Setup and Execution

**What 10/10 looks like:**
- A single `bootstrap.sh` or equivalent script takes a fresh workspace from zero to running: installs deps, provisions local services, seeds data, runs migrations.
- All tool versions are pinned (Node, pnpm, Terraform, etc.) via `.tool-versions`, `engines`, or Dockerfile.
- No manual steps — the entire setup is idempotent and scriptable.

**What 9/10 looks like:**
- Bootstrap script exists but one step requires a manual action (e.g., "create a GitHub OAuth app and paste the client ID").
- Tool versions are pinned in most places but one tool relies on "latest."

**Common 7-8 defects:**
- Setup instructions are prose paragraphs, not executable scripts.
- Tool versions are unpinned — `npm install` resolves differently on different machines.
- Local services (Postgres, Redis) assumed to be pre-installed rather than provisioned by the plan.

**Fix actions when score < 9:**
1. Create or require a `bootstrap.sh` task that scripts every setup step: `docker compose up -d`, `pnpm install`, `pnpm db:migrate`, `pnpm db:seed`.
2. Pin all tool versions: add `.tool-versions` or `.nvmrc` for Node, `engines` field in `package.json`, version tags in `docker-compose.yml` images.
3. Replace every prose setup instruction with a shell command in a script file.
4. Add `docker-compose.yml` with all infrastructure dependencies (DB, cache, queue) versioned and health-checked.
5. Add a `bootstrap-verify` step that asserts setup succeeded: DB reachable, migrations applied, seed data present, services healthy.
6. For any unavoidable manual step (OAuth app creation, API key provisioning), add it to a `MANUAL_STEPS.md` with exact instructions and mark which tasks are blocked until it completes.

---

## 6. Worktree / Branch / PR Friendliness

**What 10/10 looks like:**
- Each task specifies its branch name (`feature/T-2.1-user-auth`) and targets a defined base branch.
- Tasks are designed for isolated git worktrees: no task requires files uncommitted by another in-progress task.
- Merge sequence is explicit: "Merge T-1.1 first, then rebase T-1.2 onto main before merging."

**What 9/10 looks like:**
- Branch naming and base branches are defined but merge sequence for 1-2 tasks is implicit.
- One task pair has a soft file overlap that would cause a trivial merge conflict.

**Common 7-8 defects:**
- No branch naming convention — agents invent names, causing confusion.
- Tasks assume a shared working directory instead of isolated worktrees.
- Merge order is unspecified — agents merge in arbitrary order, causing integration failures.

**Fix actions when score < 9:**
1. Add `branch: feature/T-{id}-{slug}` and `base: main` (or appropriate base) to every task.
2. Add a merge-order section: numbered list of PR merge sequence respecting dependency DAG.
3. Verify each task can run in an isolated worktree: no references to uncommitted files from sibling tasks.
4. For tasks that must build on another task's branch, specify `base: feature/T-{parent-id}-{slug}` explicitly.
5. Add post-merge rebase instructions for any task whose base branch changes after a sibling merges.
6. Define a PR template or checklist that every task's PR must satisfy before merge.

---

## 7. CI/CD Readiness

**What 10/10 looks like:**
- CI pipeline config (`.github/workflows/*.yml` or equivalent) is either already present or a task creates it early in the plan.
- Pipeline covers: lint, typecheck, unit tests, integration tests, build, and any migration validation.
- Merge gates are explicit: "PR cannot merge unless CI passes and at least one approval is given."

**What 9/10 looks like:**
- CI pipeline exists but one check is missing (e.g., typecheck runs but migration validation does not).
- Merge gates are implied but not explicitly stated in the plan.

**Common 7-8 defects:**
- No CI pipeline task in the plan — CI is assumed to exist or will be "added later."
- Pipeline covers lint and build but skips integration tests or migration checks.
- No merge-gate definition — PRs can merge with failing checks.

**Fix actions when score < 9:**
1. Add a task in Phase 1 to create/update `.github/workflows/ci.yml` covering: lint, typecheck, `pnpm build`, unit tests, integration tests.
2. Add migration validation to CI: run `pnpm db:migrate` against a fresh test DB in the pipeline.
3. Define merge gates explicitly in the plan: "All PRs require: CI green, no type errors, test coverage >= N%."
4. Add a `pnpm typecheck` step (e.g., `tsc --noEmit`) to the CI pipeline if TypeScript is used.
5. For monorepos, ensure CI runs only affected workspace checks using `turbo run test --filter=...[origin/main]` or equivalent.
6. Add a smoke-test step post-deploy: hit health endpoint, verify response, fail pipeline if unhealthy.

---

## 8. Test Strategy Completeness

**What 10/10 looks like:**
- Test pyramid is explicit: unit tests for business logic, integration tests for API routes + DB, contract tests for external service boundaries, E2E for critical user flows.
- Every task AC includes the test type and location: "Unit test in `src/services/__tests__/auth.test.ts`."
- Migration tasks have rollback tests; event-driven tasks have idempotency tests.

**What 9/10 looks like:**
- Test pyramid is defined but contract tests for one external service boundary are missing.
- Test file locations are specified for most tasks but 1-2 tasks say "add tests" without specifying where.

**Common 7-8 defects:**
- Only unit tests mentioned — no integration or contract tests.
- Test locations unspecified — agents create tests in inconsistent locations.
- No tests for error paths, only happy paths.
- Migration rollback is untested.

**Fix actions when score < 9:**
1. Add a test strategy section to the plan defining the pyramid: unit, integration, contract, E2E with file path conventions for each layer.
2. Add test file path to every task AC: `test: src/services/__tests__/{feature}.test.ts` for unit, `test: src/routes/__tests__/{feature}.integration.test.ts` for integration.
3. Add error-path test ACs for every task that calls an external service: timeout, 4xx, 5xx, network failure.
4. Add contract test ACs for every external API boundary: mock server validates request shape, test validates response parsing.
5. Add migration rollback test: run migrate up, seed data, migrate down, verify schema reverts cleanly.
6. Add idempotency test for every event handler: process same event twice, assert no duplicate side effects.
7. Specify test runner config if non-default: `vitest.config.ts` workspace paths, `jest.config.js` module mapping.

---

## 9. Merge-Conflict Risk Management

**What 10/10 looks like:**
- Shared-file hotspots are identified (e.g., `schema.prisma`, `package.json`, `index.ts` barrel files, route registrations) with a mitigation for each.
- Root config files are modified by at most one task per parallel group, or changes are serialized.
- Barrel-file / route-registration conflicts are handled via an explicit "integration task" at the end of each phase.

**What 9/10 looks like:**
- Hotspots are identified but one mitigation is weak (e.g., "merge carefully" instead of a concrete strategy).
- One barrel-file update is spread across parallel tasks without a designated owner.

**Common 7-8 defects:**
- No hotspot analysis — shared files discovered only at merge time.
- Multiple parallel tasks add entries to `schema.prisma`, `routes/index.ts`, or `docker-compose.yml`.
- No integration task to reconcile shared-file changes.

**Fix actions when score < 9:**
1. Audit the plan for files written by 2+ tasks. List them in a `### Merge Hotspots` section.
2. For `schema.prisma` or equivalent: assign all schema additions to a single prerequisite task, or serialize schema tasks.
3. For barrel files (`index.ts`, `routes.ts`): create a dedicated integration task at the end of each parallel group that adds all new exports/routes.
4. For `package.json`: consolidate dependency additions into one task per phase or use a `pnpm add` step in each task with an explicit merge note.
5. For `docker-compose.yml`: assign one task to own the file; other tasks document their service requirements for that task to add.
6. Add merge-conflict resolution instructions: "After merging T-2.1, rebase T-2.2 onto main and resolve `schema.prisma` by keeping both model additions."

---

## 10. Human-in-the-Loop Burden

**What 10/10 looks like:**
- Approval points are explicitly marked with `[HUMAN]` tags: what needs review, what decision is needed, and what the agent should do while waiting.
- Total human touchpoints are <= 3-5 for the entire plan (realistic for async review).
- No stall points: if a human blocker exists, parallel work is available for agents to continue with.

**What 9/10 looks like:**
- Approval points are marked but one stall point exists where all agents are blocked waiting for a single human decision.
- Human burden is reasonable but one approval could be eliminated by pre-making the decision.

**Common 7-8 defects:**
- Every task requires human approval before the next starts — fully serial human bottleneck.
- Approval points exist but criteria for approval are vague ("review and approve").
- No parallel work available during human review periods.

**Fix actions when score < 9:**
1. Add `[HUMAN]` tags to every point requiring human input. Specify: what artifact to review, what decision to make, what "approved" means.
2. Reduce approval points: pre-make decisions in DECISIONS-LOCKED.md to eliminate mid-plan human decisions.
3. For each `[HUMAN]` gate, identify parallel tasks agents can work on while waiting.
4. Add approval criteria checklists: "Approve if: tests pass, schema matches ERD, no new dependencies added."
5. Consolidate approvals: batch related reviews into a single checkpoint (e.g., "review all Phase 1 PRs together") instead of per-task gates.
6. Add timeout/escalation instructions: "If no approval within 4h, proceed with default option X and flag for post-hoc review."

---

## 11. Secrets / Config / Environment Handling

**What 10/10 looks like:**
- `.env.template` (or `.env.example`) exists with every required variable documented: name, description, example value, which service needs it.
- Bootstrap script validates all required env vars are set before proceeding.
- Secrets are provisioned via a documented process (vault, CI secrets, manual) with a task to set them up.

**What 9/10 looks like:**
- `.env.template` exists but one service's variables are missing or undocumented.
- Secret provisioning is documented but no validation step checks that secrets are present at startup.

**Common 7-8 defects:**
- No `.env.template` — agents must discover required env vars by reading code.
- Secrets referenced in tasks but no provisioning instructions.
- Different services need different env files but the plan does not specify per-service config.

**Fix actions when score < 9:**
1. Create `.env.template` with all required environment variables documented: `# DATABASE_URL - Postgres connection string for primary DB (required)`.
2. Add env var validation to the bootstrap script: check every required var is set, fail with a clear message listing missing vars.
3. Add a secrets provisioning task: list every secret, where it comes from, and how to set it (CI secret, vault path, manual).
4. For multi-service setups, create per-service `.env.template` files: `services/api/.env.template`, `services/worker/.env.template`.
5. Add startup validation in application code: use `zod` or `envalid` schema to validate env vars at boot, fail fast with descriptive errors.
6. Document which env vars are needed for CI vs. local dev vs. production in the template comments.

---

## 12. Data Migration and State Transition Safety

**What 10/10 looks like:**
- Migrations are ordered and each task specifies which migration files it creates with explicit up/down logic.
- Destructive operations (column drops, table renames, data transforms) are flagged with `[DESTRUCTIVE]` and have rollback paths.
- State transitions are documented: "before migration: schema A. After migration: schema B. Data transform: X."

**What 9/10 looks like:**
- Migrations are ordered but one destructive operation lacks an explicit rollback path.
- State transitions are documented for schema changes but not for data transforms.

**Common 7-8 defects:**
- Migration order is implicit — no sequence numbers or dependency declarations.
- Destructive operations are not flagged; column drops happen without data backup steps.
- No rollback strategy for migrations that transform data in place.

**Fix actions when score < 9:**
1. Number all migration files explicitly in the plan: `001_create_users.sql`, `002_add_roles.sql` matching task order.
2. Flag every destructive operation with `[DESTRUCTIVE]`: column drops, table renames, type changes, data deletes.
3. Add rollback path for every destructive migration: "Down migration restores column with default value" or "backup table created before transform."
4. Add pre-migration data validation: "Assert: all rows in `users` have non-null `email` before running `003_add_email_constraint.sql`."
5. Add post-migration verification AC: "After migrate up: `SELECT count(*) FROM users WHERE email IS NULL` returns 0."
6. For data transforms, add a separate task that runs the transform with progress logging and can be re-run safely (idempotent).
7. Require migration tests: up, verify, down, verify, up again — assert clean round-trip.

---

## 13. Failure Recovery / Rollback Design

**What 10/10 looks like:**
- Every task that calls an external service has error-path ACs: timeout handling, retry with backoff, circuit breaker threshold.
- Idempotency keys are specified for all event-producing and event-consuming operations.
- Rollback procedures are documented per-task: "If deploy fails: revert migration, redeploy previous image, clear cache."

**What 9/10 looks like:**
- Error paths exist for most external calls but one integration (e.g., payment webhook) lacks retry/idempotency specification.
- Rollback is documented at the plan level but not per-task.

**Common 7-8 defects:**
- No error-path ACs — only happy-path behavior specified.
- No idempotency design for event handlers — duplicate processing possible.
- Rollback is "revert the PR" with no consideration of data state.

**Fix actions when score < 9:**
1. Add error-path ACs to every task that calls an external service: LLM timeout/error fallback, external API failure retry, database transaction rollback, concurrent request conflict (HTTP 409).
2. Add idempotency key requirement to all event-producing tasks: use `{entity_id}:{event_name}:{timestamp}` or `{event_id}:{step_name}` pattern.
3. Add retry policy specification for each external call: max retries, backoff strategy (exponential with jitter), timeout duration.
4. Add circuit breaker AC for services with external dependencies: "After N consecutive failures, open circuit for M seconds, return fallback response."
5. Add per-task rollback notes: what data was created, how to undo it, what downstream effects to reverse.
6. Add dead-letter queue handling for async operations: failed events go to DLQ, alert fires, manual retry available.
7. Add transaction boundary specification: which operations are atomic, where savepoints are needed.

---

## 14. Observability / Debugging Readiness

**What 10/10 looks like:**
- Health check endpoint defined: `GET /health` returns `{status, version, timestamp, dependencies: {db: "ok", redis: "ok"}}`.
- Structured logging with correlation IDs specified: every request gets a `requestId` propagated through all service calls.
- Error tracking integration specified: Sentry/equivalent with source maps, environment tags, user context.

**What 9/10 looks like:**
- Health check and logging are defined but one dependency health check is missing (e.g., Redis or external API).
- Correlation IDs exist but not propagated across async job boundaries.

**Common 7-8 defects:**
- No health check endpoint in any task.
- Logging is `console.log` without structure — no JSON format, no levels, no correlation IDs.
- No error tracking integration — errors only visible in container logs.

**Fix actions when score < 9:**
1. Add health check endpoint AC: `GET /health` returns `{status, version, timestamp}`, verifies connectivity to all dependencies (DB, cache, queues), returns 503 if any dependency is down.
2. Add structured logging AC: use `pino` or `winston` with JSON output, include `requestId`, `userId`, `service`, `level` in every log line.
3. Add correlation ID middleware AC: generate `X-Request-ID` on ingress, propagate to all downstream calls and async jobs.
4. Add error tracking setup task: configure Sentry/equivalent with source maps upload in CI, environment tagging, PII scrubbing.
5. Add key operational metrics AC: request latency histogram, error rate counter, queue depth gauge, DB connection pool utilization.
6. Add log-level configuration: default to `info` in production, `debug` in development, configurable via env var `LOG_LEVEL`.
7. Add async job observability: log job start/complete/fail with `jobId`, `duration`, `attempt` fields.

---

## 15. Likelihood of One-Pass Success

**What 10/10 looks like:**
- All 14 categories above score 9+; no single category is a blocking risk.
- End-to-end execution flow is walkable: from bootstrap to all PRs merged, every step has a concrete command or artifact.
- Edge cases are pre-analyzed: the plan explicitly addresses what happens when things go wrong during execution.

**What 9/10 looks like:**
- 13/14 categories score 9+, one scores 8 with a known mitigation.
- Execution flow is clear but one phase transition (e.g., "after all Phase 2 PRs merge, run integration test suite") lacks a specific command.

**Common 7-8 defects:**
- 3+ categories score below 8, creating compounding risk.
- Plan reads well but is not mechanically executable — agents will need to ask questions.
- Cross-cutting concerns (auth, error handling, logging) are inconsistently specified across tasks.

**Fix actions when score < 9:**
1. Address all categories scoring <9 using the fix actions listed above — this category cannot score 10 if others are weak.
2. Add a `### Execution Walkthrough` section: numbered steps from `git clone` to "all PRs merged and deployed," each with a concrete command.
3. Add cross-cutting concern checklist: verify every task that touches auth references the same auth pattern, every external call has error handling, every new endpoint has logging.
4. Add a pre-flight checklist task at plan start: verify all tools installed, env vars set, services running, base branch up to date.
5. Add phase-transition gates: "Before starting Phase 3: verify all Phase 2 PRs are merged, run `pnpm test:integration`, confirm zero failures."
6. Add a known-risks section: list 3-5 things most likely to cause a re-run, with preemptive mitigations for each.
7. Verify every task can be completed by an agent reading ONLY the plan and referenced decision docs — no tribal knowledge required.

---

## Quick Reference: Universal Fix Checklist

When reviewing any plan, verify these cross-cutting items:

- [ ] Every task has: estimated hours, branch name, base branch, single PR scope
- [ ] Every AC is pass/fail testable with a concrete command or assertion
- [ ] Every external service call has: timeout, retry, error-path AC
- [ ] Every shared file has: single owner per parallel group, or explicit merge strategy
- [ ] Every env var is in `.env.template` with description
- [ ] Every migration has: sequence number, up/down logic, rollback verification
- [ ] Every decision reference (DA-N, BL-N, CC-N) links to DECISIONS-LOCKED.md
- [ ] Bootstrap script goes from fresh clone to running app with zero manual steps
- [ ] CI pipeline covers: lint, typecheck, build, unit test, integration test, migration validation
- [ ] Health check endpoint verifies all runtime dependencies
- [ ] Merge order is explicitly documented and respects the dependency DAG
- [ ] Human approval points are tagged, bounded, and non-blocking for parallel work
- [ ] Idempotency keys are specified for all async event operations
- [ ] Structured logging with correlation IDs is required in every service task
- [ ] At least one task explicitly sets up the test infrastructure (runner config, fixtures, factories)
