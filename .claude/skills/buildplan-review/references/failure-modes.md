# Failure Modes to Hunt For

All reviewers must actively hunt for these failure classes. This is not a checklist to skim — each item represents a real way autonomous builds break.

## Task-Level Failures
- Tasks too large for agents (>8 hours, touching >2 directories)
- Tasks too vague ("implement the feature", "set up properly")
- Hidden prerequisites not listed in dependencies
- Dependency ordering mistakes (consumer before producer)
- Unsafe parallelization (two tasks touching same files concurrently)

## Merge and Conflict Failures
- Merge conflict hotspots (multiple tasks editing same file)
- Shared-file bottlenecks (package.json, tsconfig, schema files, router files, type definition files)
- Lockfile or manifest conflicts (package-lock.json, yarn.lock, go.sum)
- Schema/router/type/config bottlenecks (central files many tasks depend on)
- Codegen steps that produce files other tasks also modify

## Setup and Environment Failures
- Missing bootstrap scripts (agent can't set up from scratch)
- Missing seed data (database is empty, app crashes)
- Missing env variable matrix (which vars, which values, which environments)
- Missing secrets provisioning (API keys, tokens not available)
- Missing local setup instructions (agent doesn't know how to start)
- Non-deterministic setup steps ("install the right version", "configure as needed")
- Steps that fail in fresh isolated workspaces (rely on host state, cached artifacts, or manual setup)

## CI/Test Failures
- Missing lint/typecheck/build/test split (one monolithic CI step)
- Over-reliance on e2e tests (slow, flaky, expensive)
- Flaky tests (pass sometimes, fail others)
- Missing contract tests (API producers and consumers disagree)
- Missing migration tests (schema changes untested)
- Missing smoke tests (basic functionality unchecked)
- Weak or subjective acceptance criteria ("looks good", "feels right", "performs well")
- No explicit merge gates (what must pass before merge?)

## Product/Spec Failures
- Undefined API contracts (endpoints without request/response schemas)
- Missing schema definitions (data models referenced but not defined)
- Vague UX/product choices that require human taste
- Missing edge cases (what happens on empty input? Duplicate data? Permission denied?)
- Missing loading states, error states, empty states
- Unclear roles and permissions model
- Missing data ownership rules
- Missing analytics or event definitions
- Missing non-functional requirements (latency, throughput, availability)

## Operational Risk Failures
- Secret leakage risk (credentials in logs, env vars in CI output)
- Unsafe shell patterns (unquoted variables, eval, rm -rf without guards)
- Destructive migrations (DROP TABLE, data-losing ALTER)
- Unsafe retries (non-idempotent operations retried on failure)
- Idempotency gaps (running a task twice produces different results)
- Race conditions (concurrent agents creating conflicting state)
- Concurrency hazards (database locks, file locks, port conflicts)
- Webhook hazards (external callbacks during unstable deployment)
- Partial deployment hazards (frontend deployed but backend isn't, or vice versa)
- Missing rollback plans (what happens when production breaks?)
- Missing observability and debugging hooks (can't tell what went wrong)

## Human Burden Failures
- Too many required human judgment calls (plan says "autonomous" but requires constant decisions)
- Review loops likely to stall forever (no timeout, no escalation, no skip path)
- Assumptions that the orchestrator can self-heal when it probably cannot
- Vague "human review" gates without criteria for what the human is checking

---

# Special Audit Areas

Each reviewer must explicitly inspect the build plan for ALL of the following areas:

## A. Planning Quality
- Missing milestones
- Circular dependencies
- Vague placeholders ("TBD", "to be determined", "as needed")
- Hidden infrastructure assumptions
- Undefined terms
- Oversized work packages
- Founder-brain shortcuts (assumes context only the author has)
- "Magic happens here" sections (hand-waving over complexity)

## B. Orchestrator Compatibility
- Issue-sized taskability (can each task be a GitHub issue?)
- Explicit task inputs and outputs
- Machine-checkable acceptance criteria
- Safe retry behavior
- Clear stop conditions (when does the orchestrator stop trying?)
- Likely CI/review convergence vs. endless looping
- Actual feasibility of one-pass autonomy

## C. Repo Execution Reality
- Shared-file hotspots
- Root config bottlenecks
- Lockfile conflicts
- Dependency manifest conflicts
- Schema/type/router/config bottlenecks
- Codegen steps
- Migration ordering
- Monorepo complexity
- Manual steps that should be scripted

## D. Environment Reality
- Missing bootstrap scripts
- Missing seed data and fixtures
- Missing env variable matrix
- Unclear credentials and service access
- Steps that fail in clean workspaces

## E. CI/Test Reality
- No fast test layers
- Over-reliance on slow end-to-end tests
- Missing contract tests
- Missing migration tests
- Flaky tests
- Weak green conditions
- No explicit merge gates

## F. Product/Spec Ambiguity
- Missing edge cases
- Missing loading/error/empty states
- Vague acceptance criteria
- Unclear roles and permissions
- Unclear data ownership
- Missing API contracts and schema definitions
- Missing analytics/event definitions
- Missing non-functional requirements

## G. Operational Risk
- Secret leakage risk
- Unsafe shell patterns
- Destructive migrations
- Irreversible writes
- Rate-limit hazards
- Retry hazards
- Concurrency hazards
- Partial deploy hazards
- Missing rollback and recovery paths
