# Scoring Rubric

Score each category from 0 to 10. For every score, state why it lost points and include evidence tags.

## Scoring Scale

| Score | Meaning |
|-------|---------|
| 0-3 | Blocker-level weakness — this will cause failure |
| 4-6 | Risky or incomplete — may work but likely won't |
| 7-8 | Workable with fixes — solid foundation, specific gaps |
| 9-10 | Strong — ready for autonomous execution |

## Categories

### 1. Task Decomposition Quality
Are tasks sized correctly for agent execution (2-8 hours)? Are they vertical slices? Does each produce exactly one PR? Are scopes clear and non-overlapping?

#### 9 vs 10
- **10:** Every task 3-5h estimated. Every task has explicit In Scope / Out of Scope sections. Every task touches 1-2 directories max. Zero tasks require implicit or tribal knowledge. Acceptance criteria are all machine-checkable (test passes, type-checks, lint clean). No task duplicates work from another task.
- **9:** All tasks within 3-8h but one or two at 6-8h. Scope boundaries present but one task missing explicit Out of Scope. All acceptance criteria are testable but one or two require manual verification (e.g., "UI looks correct"). Directory boundaries mostly clean with one task touching 3 directories.

### 2. Parallelization Safety
Can the parallelized tasks actually run concurrently without interference? Are shared resources identified? Are race conditions prevented?

#### 9 vs 10
- **10:** Every parallel group explicitly lists shared resources (files, ports, DB tables, env vars). No two concurrent tasks write to the same file. Port allocations are unique per task. Database isolation strategy is defined (separate schemas, transactions, or test databases). CI runners can execute all parallel tasks simultaneously without coordination.
- **9:** Shared resources identified for all parallel groups but one group lacks explicit port or DB isolation strategy. All file-write conflicts prevented. One parallel group has a theoretical race condition on a shared config file that is unlikely but not structurally prevented.

### 3. Dependency Sequencing Quality
Is the dependency DAG valid? Are there circular dependencies? Dangling references? Are dependency reasons concrete (shared file, shared schema, shared API, shared type, pattern reference)?

#### 9 vs 10
- **10:** DAG is acyclic and verified. Every dependency edge has a concrete reason citing the exact artifact (file path, schema name, type name, API endpoint). Zero dangling references — every dependency target exists in the plan. Critical path is identified and minimized. No unnecessary sequential constraints (maximum parallelism achieved).
- **9:** DAG is acyclic with all dependencies justified. One or two dependency reasons are category-level ("needs auth module") rather than artifact-level ("needs `src/auth/middleware.ts` export `verifyToken`"). Critical path is identifiable but not explicitly called out. One dependency could potentially be relaxed to increase parallelism.

### 4. Instruction Clarity for Coding Agents
Could a coding agent execute each task from the instructions alone, without asking questions? Are inputs, outputs, and constraints explicit? No tribal knowledge required?

#### 9 vs 10
- **10:** Every task specifies: exact files to create/modify, function signatures or type interfaces, input/output contracts, error handling behavior, and test file locations. Code examples or pseudocode included for non-obvious logic. Framework versions and API versions pinned. Zero ambiguous phrases ("appropriate," "as needed," "standard approach").
- **9:** All tasks have file paths, input/output contracts, and test expectations. One or two tasks use a mildly ambiguous phrase that an experienced agent could resolve from context (e.g., "follow the existing pattern in `src/utils`" without specifying which pattern). All framework references present but one missing a pinned version.

### 5. Determinism of Setup and Execution
Can agents bootstrap from a fresh isolated workspace? Are all setup steps scripted? Are there non-deterministic steps (manual installs, GUI interactions, "configure as needed")?

#### 9 vs 10
- **10:** Single command bootstrap (`make setup` or `./scripts/bootstrap.sh`). All dependencies pinned with lockfiles. All environment variables have defaults or are generated. Zero manual steps. Setup is idempotent — running it twice produces the same result. Docker or nix used for system-level dependencies. Seed data scripted.
- **9:** Bootstrap scripted and mostly single-command. All language-level dependencies pinned. One system-level dependency (e.g., a database or Redis) requires a pre-existing install but has a Docker fallback documented. All env vars documented with examples. One optional step marked "recommended" but not scripted.

### 6. Worktree / Branch / PR Friendliness
Do tasks work in isolated worktrees/branches? Can PRs be reviewed independently? Are merge sequences defined?

#### 9 vs 10
- **10:** Every task names its branch. Merge order is an explicit numbered list. Every PR has a self-contained description template. No PR requires reviewing another PR to understand context. Conflict resolution instructions provided for known hotspot files. Worktree isolation tested — each task runs in its own worktree with no cross-worktree references.
- **9:** Branch naming convention defined. Merge order specified per phase but not as a single global sequence. All PRs self-contained except one that references a prior PR for schema context. Worktree isolation assumed but not explicitly validated. One shared config file lacks merge-order instructions.

### 7. CI/CD Readiness
Are CI pipelines defined? Do they cover lint, typecheck, build, and test? Are green conditions explicit? Are merge gates defined?

#### 9 vs 10
- **10:** CI pipeline config files included in the plan (`.github/workflows/*.yml` or equivalent). Pipeline covers lint, typecheck, build, unit test, integration test as separate stages. Green conditions are explicit per stage (exit code 0, coverage threshold, zero warnings policy). Merge gates require all checks green plus approval. Pipeline runs in under 10 minutes. Cache strategy defined.
- **9:** CI pipeline defined with all major stages (lint, typecheck, build, test). Green conditions stated but one stage missing an explicit threshold (e.g., coverage target mentioned but not a number). Merge gates defined but missing one gate (e.g., no required approval count). Pipeline estimated under 15 minutes.

### 8. Test Strategy Completeness
Is there a test pyramid (unit, integration, contract, e2e)? Are there fast test layers for CI iteration? Missing contract tests? Missing migration tests? Over-reliance on slow e2e?

#### 9 vs 10
- **10:** Test pyramid explicitly defined with target counts per layer. Unit tests cover all business logic with >90% branch coverage target. Integration tests cover all API endpoints and DB queries. Contract tests defined for every service boundary. Migration tests verify up and down paths. Fast test suite (unit + integration) runs in under 2 minutes. E2e tests exist but are not the primary validation layer. Test data factories defined.
- **9:** Test pyramid defined with unit, integration, and e2e layers. Coverage target stated but at file level not branch level. Contract tests present for external service boundaries but missing one internal boundary. Migration tests cover up path but not down path. Fast test suite under 5 minutes. One area relies on e2e where an integration test would suffice.

### 9. Merge-Conflict Risk Management
Are shared-file hotspots identified? Are root config bottlenecks (package.json, tsconfig, schema files, router files) managed? Is there a merge sequence strategy?

#### 9 vs 10
- **10:** Every shared file listed with which tasks touch it and in what order. Root configs (package.json, tsconfig.json, schema files, router/route files, migration indexes) have explicit merge-order rules. Conflict resolution snippets provided for predictable conflicts (e.g., "append to routes array, do not reorder"). Tasks that touch shared files are serialized or have non-overlapping edit regions documented.
- **9:** Shared-file hotspots identified and most have merge-order rules. Root config files accounted for but one (e.g., a barrel export file or route index) lacks explicit merge instructions. Tasks that touch shared files are sequenced but one pair has a potential conflict region without a resolution snippet.

### 10. Human-in-the-Loop Burden
How many human decisions are required? Are approval points clearly marked? Is the human burden realistic? Could review loops stall forever?

#### 9 vs 10
- **10:** Total human decision count stated (e.g., "5 approvals across 20 tasks"). Every approval point is a named gate with pass/fail criteria. No open-ended review ("looks good" is not a gate criterion). Maximum human latency budgeted (e.g., "review within 4h or auto-proceed"). Escalation path defined for stalled reviews. Human decisions are batched where possible.
- **9:** Human decision points identified and most have criteria. Total count not explicitly stated but calculable. One approval point has subjective criteria ("confirm the UX feels right"). No explicit latency budget but approval points are at phase boundaries, implying batch review. No escalation path for stalls.

### 11. Secrets / Config / Environment Handling
Are all env vars documented? Are secrets provisioned? Is there an env matrix? Do clean workspaces have what they need? Are there missing bootstrap scripts?

#### 9 vs 10
- **10:** Complete env var manifest with name, description, required/optional, default value, and source (vault, CI secret, generated). `.env.example` file included or generated by bootstrap. Env matrix covers local, CI, staging, and production. Secrets provisioning is scripted (vault read, CI variable injection). No secret appears in plain text anywhere in the plan. Bootstrap validates all required env vars on startup.
- **9:** All env vars documented with descriptions and defaults. `.env.example` provided. Env matrix covers local and CI but staging/production noted as "follow deployment docs." One secret's provisioning method is described in prose rather than scripted. Bootstrap checks for required vars but doesn't validate format/connectivity.

### 12. Data Migration and State Transition Safety
Are migrations ordered correctly? Are destructive migrations flagged? Are rollback paths defined? Are state transitions safe under concurrent execution?

#### 9 vs 10
- **10:** Migrations numbered and ordered in the DAG. Every destructive migration (drop column, delete data, rename) is flagged with a warning and has a rollback migration. State transitions are idempotent — re-running a migration is safe. Concurrent migration execution prevented by lock strategy. Data backups scripted before destructive operations. Migration dry-run step included in CI.
- **9:** Migrations ordered and destructive ones flagged. Rollback paths defined for most destructive migrations but one complex migration has rollback marked as "manual SQL required." Idempotency addressed for all migrations except one that uses a raw SQL statement. No explicit concurrent migration lock but framework default is noted.

### 13. Failure Recovery / Rollback Design
What happens when a task fails? Can the system recover without manual intervention? Are there idempotency guarantees? Are partial deployments handled?

#### 9 vs 10
- **10:** Every task has a defined failure mode and recovery action. Re-running any failed task from scratch produces the correct result (idempotent). Partial deployment states are enumerated with recovery steps. Circuit breaker or health check defined for deployment verification. Rollback is a single command per task. No task leaves the system in an unrecoverable state on failure.
- **9:** Failure modes defined for all tasks. Most tasks are idempotent on re-run. One task's failure recovery requires a manual cleanup step (e.g., "delete the partial migration before re-running"). Rollback commands defined but one requires two steps instead of one. Partial deployment handling described but not automated.

### 14. Observability / Debugging Readiness
Can operators see what agents are doing? Are there logging hooks? Can failures be diagnosed from CI output alone? Are error states distinguishable?

#### 9 vs 10
- **10:** Every task emits structured logs with task ID, phase, and status. CI output includes timestamps, step durations, and exit codes for every command. Error states have unique error codes or messages — no two failures produce the same output. Log aggregation strategy defined for multi-agent execution. Debug mode available that increases verbosity. Health check endpoints defined for running services.
- **9:** Logging defined for all tasks with task ID and status. CI output includes step-level results. Most error states distinguishable but two error paths produce similar output requiring log inspection to differentiate. No explicit log aggregation strategy but CI artifacts capture all logs. Debug mode not defined but verbosity is adequate for diagnosis.

### 15. Likelihood of One-Pass Success
Given everything above, what is the realistic probability that an orchestrator executes this plan end-to-end without major rescue, re-planning, or manual intervention?

#### 9 vs 10
- **10:** All other 14 categories score 8 or above. Zero blockers. No category has a split opinion across reviewers. The plan has been validated against a similar prior execution or dry-run. Estimated total execution time stated and realistic. Contingency buffer built into timeline. Every known risk has a mitigation.
- **9:** All other categories score 7 or above with at most two at 7. Zero blockers but one or two categories have minor gaps that could cause a single retry. No dry-run validation but the plan follows a proven template. Execution time estimated but without contingency buffer. One low-probability risk lacks explicit mitigation.
