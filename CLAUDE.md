# Build-Pipe Agent Instructions

You are operating within the Build-Pipe document pipeline. Every action you take must follow the rules below and produce artifacts that CI can validate.

## Mandatory Reading

Before doing ANY work, read these files:
1. `.agent-rules.md` — The seven rules you must obey. Violations fail CI.
2. `stack.yaml` — Technology constraints. Use only what's specified.
3. `pipeline.yaml` — Current pipeline mode and configuration.
4. `docs/00-foundation/PROJECT.md` — Project vision, target users, success metrics.

## Pipeline Modes

The pipeline operates in one of three modes (set in `pipeline.yaml`):

| Mode | When | What You Do |
|---|---|---|
| `steady-state` | Product is live | Process one signal at a time through the full 4-stage pipeline |
| `execution` | Build plan is locked | Read task files as specs, implement, skip discovery/architecture/spec stages |
| `discovery` | Fresh product | Batch signals, synthesize into foundational architecture |

**Mode conflicts:** If the user's prompt specifies a mode that differs from `pipeline.yaml`, follow the user's prompt for this session but do not modify `pipeline.yaml`. Note the discrepancy in your PR description.

## Pipeline Stages

The pipeline has four document stages. Each stage produces ONE type of artifact. Never skip stages.

```
Signal (docs/01-raw-inputs/)  →  Discovery (docs/02-discovery/)  →  Architecture (docs/03-architecture/)  →  Specification (docs/04-specs/)  →  Code (src/ + tests/)
```

### ID Numbering Rule

The number `{n}` in artifact filenames MUST match the signal number throughout the chain:
- `SIG-42` produces `PRB-42`, which produces `ADR-42`, which produces `PRD-42`
- This chain must be numerically consistent — never use a different number

### Stage 1: Discovery (PRB)
- **Also read:** `docs/00-foundation/PERSONAS.md` — reference personas in "Affected Users" section
- **Input:** A raw signal document in `docs/01-raw-inputs/SIG-{n}.md`
- **Output:** `docs/02-discovery/PRB-{n}.md` using `.templates/discovery_template.md`
- **Must contain:** Link to the raw signal source
- **Then STOP.** Do not proceed to architecture. Open a PR.

### Stage 2: Architecture (ADR)
- **Also read:** `docs/00-foundation/CONSTRAINTS.md` — compliance, performance, security requirements
- **Also read:** `docs/05-design/CODEBASE-MAP.md` — current codebase structure
- **Also explore (if src/ has source files):**
  1. Read CODEBASE-MAP.md for the high-level structure
  2. Identify modules relevant to this feature by name/path
  3. For each relevant module, read its entry point or index file
  4. Note public interfaces (exports, function signatures, route definitions)
  5. Record findings in the ADR's "Existing Codebase" section
  6. If src/ contains only .gitkeep files, write "Greenfield" in that section
- **Input:** An approved PRB in `docs/02-discovery/`
- **Output:** `docs/03-architecture/ADR-{n}.md` using `.templates/adr_template.md`
- **Must contain:** Link to the PRB it solves
- **Must respect:** `stack.yaml` technology choices
- **Must respect:** Constraints in `docs/00-foundation/CONSTRAINTS.md`
- **Then STOP.** Do not proceed to specification. Open a PR.

### Stage 3: Specification (PRD)
- **Also read:** `docs/00-foundation/BRAND.md` — design principles and UX guidelines for user-facing features
- **Also read:** `docs/05-design/CODEBASE-MAP.md` — current codebase structure
- **Cross-verify:** Before writing the PRD, independently check the ADR's "Existing Codebase" section against the actual codebase. Note discrepancies in PRD Section 6.
- **File paths:** Use CODEBASE-MAP.md and direct exploration to accurately populate the "Files to Create/Modify" section with real paths.
- **Input:** An approved ADR in `docs/03-architecture/`
- **Output:** `docs/04-specs/PRD-{n}.md` using `.templates/prd_template.md`
- **Must contain:** Link to the ADR it implements
- **Must contain:** Boolean acceptance criteria (testable)
- **Must contain:** Exact test file paths to create/update
- **Must list:** All source files to create/modify in "Files to Create/Modify" section
- **Then STOP.** Do not proceed to code. Open a PR.

### Stage 4: Code
- **Input:** An approved PRD in `docs/04-specs/`
- **Output:** Source code in `src/` and tests in `tests/`
- **Must satisfy:** Every acceptance criterion in the PRD
- **Must pass:** All existing tests + new tests for this feature
- **Must include:** A `# Implements: PRD-{n}` comment in each new source file
- **If you discover the ADR's codebase analysis is wrong:** Include `<!-- errata: ADR-{n} -- {description of what's wrong} -->` in your PR body. This surfaces during code review without adding a new gate.

### What "Approved" Means

A document is considered **approved** when its PR has been merged to `main`. If the input document's PR has not been merged, do not proceed to the next stage.

## Human-in-the-Loop Design (2 Decision Points)

The pipeline is designed for **95% autonomy** with exactly two types of human decisions:

1. **Proposal approval** — When you open a PR with label `pipeline:proposal` (discovery, architecture, or specification documents), branch protection requires a GitHub PR review approval before merge. The human decides whether the problem framing, architecture, or spec is correct. Once approved and merged, the pipeline auto-advances to the next stage.

2. **Final code review** — When you open a code implementation PR, the human reviews the code on GitHub, approves, and merges.

Everything else is autonomous: signal ingestion, stage-to-stage orchestration, CI validation, status tracking, agent dispatch via `poll-and-spawn.sh`, and next-task pickup. The human only makes two kinds of decisions: "Is this proposal good?" and "Is this code correct?"

## Execution Mode (Build Plan)

When `pipeline.yaml` mode is `execution`, you skip the discovery/architecture/specification stages. Instead:
1. Read the task file provided to you (from `build-plan/workstreams/*/tasks/`)
2. The task file IS your specification — it contains acceptance criteria, contracts, and scope
3. Implement exactly what the task specifies
4. Write tests covering all acceptance criteria
5. If the task is marked `must_review`, add the `pipeline:human-gate` label to your PR
6. Add the `pipeline:task` label to your PR
7. Include `<!-- pipeline-task-id: {TASK_ID} -->` in your PR body (this is how task completion is tracked)
8. Branch naming `task/{TASK_ID}` is conventional but not required — use whatever your agent runtime provides

**Post-merge automation:** When your PR merges with the `pipeline:task` label, `task-complete.yml` automatically marks the task as `done` in `.pipeline-status.json` and triggers the orchestrator to pick up the next available task. You do NOT need to manually update the status file.

### Pipeline Management Skills

- `/pipeline` — Check status, dispatch work, validate build plans, or initialize new build plans. Works in both steady-state and execution modes.
- `/build-plan-generator` — Generate a build plan from a product blueprint. After generation, offers to submit to `/buildplan-review` for certification.
- `/buildplan-review` — Certify a build plan to 95+ autonomous execution readiness. Runs 5 parallel review agents, scores 15 categories, and autonomously fixes issues through up to 3 iteration passes. Can also be invoked manually on any existing build plan.

## Cross-Linking Format

Every document must link to its predecessor. Use this format:

```markdown
**Solves Problem:** [PRB-100](../02-discovery/PRB-100.md)
**Implements Architecture:** [ADR-100](../03-architecture/ADR-100.md)
**Raw Input Source:** [SIG-100](../01-raw-inputs/SIG-100.md)
```

CI runs `scripts/validate-docs.sh` and will reject PRs with missing links. The linked files must actually exist — CI verifies this.

## PR Conventions

- **Branch naming (convention, not enforced):** `{stage}/{id}` (e.g., `discovery/42`, `code/42`, `task/WS0-BB1-T1`). The pipeline uses PR labels and body markers for routing — not branch names. If your agent runtime uses different branch names, that's fine.
- **Commit prefix:** `discovery:`, `architecture:`, `spec:`, `feat:`, `fix:`, `test:`
- **PR title:** `{stage}: {short description}`
- **PR body:** Link to the pipeline documents that justify this change

### PR Labels (REQUIRED)

Apply these labels when opening PRs — they identify PR types for reviewers and automation:

| PR Type | Label |
|---|---|
| Discovery (PRB) | `pipeline:proposal` |
| Architecture (ADR) | `pipeline:proposal` |
| Specification (PRD) | `pipeline:proposal` |
| Code (implementation) | _(no special label)_ |
| Execution-mode tasks | `pipeline:task` |
| Tasks marked `must_review` | `pipeline:human-gate` |

## Mode Behavior Matrix

| Mode | Input Trigger | You Read | You Produce | You Stop When |
|---|---|---|---|---|
| steady-state | "Process SIG-{n}" | `docs/01-raw-inputs/SIG-{n}.md` | `docs/02-discovery/PRB-{n}.md` | PR opened for PRB |
| steady-state | "Architect PRB-{n}" | `docs/02-discovery/PRB-{n}.md` | `docs/03-architecture/ADR-{n}.md` | PR opened for ADR |
| steady-state | "Specify ADR-{n}" | `docs/03-architecture/ADR-{n}.md` | `docs/04-specs/PRD-{n}.md` | PR opened for PRD |
| steady-state | "Implement PRD-{n}" | `docs/04-specs/PRD-{n}.md` | `src/` + `tests/` | PR opened for code |
| execution | "Execute task WS0-BB1-T1" | task file in `build-plan/` | `src/` + `tests/` | PR opened |
| discovery | "Synthesize signals" | All `docs/01-raw-inputs/SIG-*.md` | `SYNTHESIS.md` + foundational ADRs | PR opened |

## What NOT To Do

- Never write code without a specification (PRD or build plan task)
- Never skip the cross-linking requirements
- Never use technologies not listed in `stack.yaml`
- Never combine multiple pipeline stages in one PR
- Never leave template placeholders unfilled (e.g., `[Short Title]`)
- Never create a PR without the required labels (see PR Labels above)
- Never proceed to the next stage if the input document's PR hasn't been merged
- Never use a different number than the signal number in the artifact chain
