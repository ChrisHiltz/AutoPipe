# Build-Pipe

An autonomous product pipeline that turns raw signals (customer feedback, bugs, feature ideas arriving as GitHub Issues) into shipped, tested code through an enforced document chain.

**Design goal:** 95% autonomous. You make two decisions:
1. Approve proposals (discovery, architecture, specification documents) via GitHub PR review
2. Approve final code PRs via GitHub review

Everything else — signal ingestion, stage-to-stage orchestration, agent dispatch, CI validation, dependency resolution, status tracking — runs without you.

## How It Works

```
GitHub Issue (signal:feature)
    │
    ▼  [signal-ingestion.yml — automatic]
docs/01-raw-inputs/SIG-47.md  ──PR──▶  merge to main
    │
    ▼  [pipeline-orchestrate.yml — automatic]
docs/02-discovery/PRB-47.md   ──PR──▶  👤 PR review  ──▶  merge
    │
    ▼  [pipeline-orchestrate.yml — automatic]
docs/03-architecture/ADR-47.md ──PR──▶  👤 PR review  ──▶  merge
    │
    ▼  [pipeline-orchestrate.yml — automatic]
docs/04-specs/PRD-47.md       ──PR──▶  👤 PR review  ──▶  merge
    │
    ▼  [pipeline-orchestrate.yml — automatic]
src/ + tests/                  ──PR──▶  ✅ CI passes  ──▶  👤 Code review  ──▶  merge
```

Every document links to its predecessor. CI verifies the links exist. No orphaned code allowed.

## Project Foundation

Before any signals flow through the pipeline, you define your project context in `docs/00-foundation/`:

| Document | What It Provides | Used By |
|---|---|---|
| `PROJECT.md` | Vision, target users, success metrics, non-goals | All judgment stages |
| `BRAND.md` | Voice, design principles, visual identity, accessibility | Specification stage |
| `PERSONAS.md` | Reusable user persona definitions | Discovery stage |
| `CONSTRAINTS.md` | Business rules, compliance, performance budgets, security | Architecture stage |

Foundation docs feed the *judgment* stages (discovery, architecture, specification) where agents make decisions about problem framing, design, and scope. By the code stage, all decisions are baked into the PRD — the code agent reads the spec, not the brand guide.

The `/setup` wizard walks you through filling these in during onboarding.

## Three Pipeline Modes

| Mode | When to Use | What Happens |
|---|---|---|
| `steady-state` | Product is live, processing incoming signals | One signal at a time through the full 4-stage pipeline |
| `execution` | You have a locked build plan with tasks and dependencies | Reads task files as specs, respects dependency graph, auto-advances on merge |
| `discovery` | Fresh product, collecting customer research | Batches signals, synthesizes into foundational architecture |

Set the mode in `pipeline.yaml` line 1: `mode: steady-state`

---

## Setup Guide (Step by Step)

> **Quick setup:** After copying the template, run `claude` in your repo and type `/setup`. The interactive wizard handles Steps 2-6 automatically.

### Prerequisites

You need:
- A GitHub repository (public or private)
- [Agent Orchestrator](https://github.com/ComposioHQ/agent-orchestrator) installed (recommended — handles agent sessions and CI retries)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed locally (the AI agent)
- [GitHub CLI](https://cli.github.com/) installed and authenticated (`gh auth login`)
- `jq` installed on your machine (used by build-plan scripts)

### Step 1: Copy the Template

Copy the entire contents of this template into your project repository root:

```bash
cp -r . /path/to/your-project/
```

Your repo should now have:
```
your-project/
├── .agent-rules.md              # Six rules agents must obey (CI-enforced)
├── .claude/settings.json        # Claude Code tool permissions
├── .editorconfig                # Editor formatting (UTF-8, LF, 2-space indent)
├── .env.example                 # Documents required/optional env vars
├── .gitattributes               # Forces LF line endings on scripts and config
├── .gitignore                   # Ignores node_modules, .env, IDE files, etc.
├── .github/
│   ├── CODEOWNERS               # Auto-assigns you as PR reviewer
│   └── workflows/
│       ├── signal-ingestion.yml     # Auto-captures signal:* issues as SIG docs
│       ├── pipeline-orchestrate.yml # Routes work to the correct pipeline stage
│       ├── validate-and-test.yml    # CI — doc validation, tests, linting
│       └── task-complete.yml        # Marks tasks done, chains to next task
├── .templates/
│   ├── raw_input_template.md
│   ├── discovery_template.md
│   ├── adr_template.md
│   └── prd_template.md
├── CLAUDE.md                    # Agent instructions — stages, rules, conventions
├── QUICKSTART.md                # One-page reference card for daily use
├── README.md                    # This file
├── agent-orchestrator.yaml      # Config for ao (Agent Orchestrator)
├── docs/
│   ├── 00-foundation/           # Project context (filled during /setup)
│   │   ├── PROJECT.md
│   │   ├── BRAND.md
│   │   ├── PERSONAS.md
│   │   └── CONSTRAINTS.md
│   ├── 01-raw-inputs/           # Ingested signal documents
│   ├── 02-discovery/            # Problem Report Briefs (PRBs)
│   ├── 03-architecture/         # Architecture Decision Records (ADRs)
│   ├── 04-specs/                # Product Requirements Documents (PRDs)
│   └── 06-operations/           # Research strategy, logs (for nightly cycle)
├── pipeline.yaml                # Pipeline mode and settings
├── pipeline-metrics.jsonl       # Append-only health metrics (from nightly cycle)
├── scripts/
│   ├── collect-metrics.sh       # Pulls pipeline health metrics from GitHub API
│   ├── ingest-signal.sh         # Transforms a GitHub Issue into a SIG document
│   ├── nightly-cycle.sh         # Orchestrates the self-improvement cycle
│   ├── poll-and-spawn.sh        # Auto-dispatch — watches for tasks, runs ao spawn
│   ├── read-build-plan.sh       # Manages build plan task ordering and status
│   ├── setup-labels.sh          # Creates all pipeline GitHub labels
│   ├── setup-project-board.sh   # Creates GitHub Project board with stages
│   ├── update-project-board.sh  # Moves items through project board stages
│   └── validate-docs.sh         # Enforces cross-linking and single-stage-per-PR
├── src/                         # Your source code (empty until code phase)
├── stack.yaml                   # Technology constraints (frameworks, testing, hosting)
└── tests/                       # Your tests (empty until code phase)
```

### Step 2: Configure Your Tech Stack

Edit `stack.yaml` to match your project:

```yaml
project_name: "My App"
ui_framework: "shadcn/ui"
frontend_runtime: "Next.js"
backend_framework: "FastAPI"
database: "Supabase"
auth: "Supabase Auth"
testing:
  backend: "pytest"
  frontend: "vitest"
  e2e: "playwright"
hosting: "Vercel"
```

CI will enforce these choices — the agent cannot use technologies not listed here.

### Step 3: Set the Pipeline Mode

Edit `pipeline.yaml`:

```yaml
mode: steady-state  # or: execution, discovery
```

- Starting a new product from scratch? Use `discovery`
- Have a build plan with tasks? Use `execution`
- Product is live, processing bugs/features? Use `steady-state`

### Step 4: Create GitHub Labels

Run the setup script (or create manually in Settings > Labels):

```bash
./scripts/setup-labels.sh
```

| Label | Color | Purpose |
|---|---|---|
| `signal:bug` | `#d73a4a` | Bug report signals |
| `signal:feature` | `#0075ca` | Feature request signals |
| `signal:feedback` | `#e4e669` | User feedback signals |
| `signal:analytics` | `#bfdadc` | Analytics-driven signals |
| `pipeline:signal` | `#c5def5` | Signal ingestion PRs |
| `pipeline:proposal` | `#0e8a16` | Document PRs needing approval |
| `pipeline:agent-task` | `#5319e7` | Work orders for the agent |
| `pipeline:task` | `#5319e7` | Execution-mode task PRs |
| `pipeline:claimed` | `#c2e0c6` | Applied by poll-and-spawn to prevent double-dispatch |
| `pipeline:human-gate` | `#fbca04` | Tasks requiring human review |
| `pipeline:failure` | `#b60205` | Pipeline failure notifications |

### Step 5: Install Agent Orchestrator

1. Install `ao`:
   ```bash
   git clone https://github.com/ComposioHQ/agent-orchestrator.git
   cd agent-orchestrator && bash scripts/setup.sh
   ```

2. Edit `agent-orchestrator.yaml` in your project — set your repo, path, and project name.

3. Start ao:
   ```bash
   ao start
   ```

4. Start the auto-dispatch loop (watches for new tasks and spawns agents):
   ```bash
   ./scripts/poll-and-spawn.sh my-project &
   ```

### Step 6: Set Up CODEOWNERS

Edit `.github/CODEOWNERS` — replace `@your-github-username` with your actual GitHub username. This auto-assigns you as reviewer for proposal and code PRs.

### Step 7: Enable Branch Protection

Go to repo **Settings > Branches > Add rule** for `main`:

- [x] Require pull request reviews before merging (1 approval)
- [x] Require status checks to pass before merging
  - Required checks: `Validate Document Pipeline`, `Run Test Suite`
- [x] Require review from Code Owners
- [x] Do not allow bypassing the above settings

### Step 8: Configure Claude Code

Install Claude Code if you haven't:
```bash
npm install -g @anthropic-ai/claude-code
```

Set your Anthropic API key:
```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

The `.claude/settings.json` in this template pre-configures permissions for the pipeline scripts. Claude Code reads `CLAUDE.md` automatically for project instructions and `.agent-rules.md` for behavioral constraints.

### Step 9: Make Scripts Executable

```bash
chmod +x scripts/ingest-signal.sh
chmod +x scripts/validate-docs.sh
chmod +x scripts/read-build-plan.sh
chmod +x scripts/poll-and-spawn.sh
chmod +x scripts/setup-labels.sh
chmod +x scripts/collect-metrics.sh
chmod +x scripts/nightly-cycle.sh
chmod +x scripts/setup-project-board.sh
chmod +x scripts/update-project-board.sh
```

### Step 10: Push and Verify

```bash
git add -A
git commit -m "feat: initialize Build-Pipe pipeline"
git push origin main
```

Verify workflows are visible in GitHub Actions tab.

---

## Running the Pipeline

### Steady-State Mode: Signal to Shipped Code

**1. Create a signal**

File a GitHub Issue with a `signal:*` label:

> Title: Add dark mode toggle to settings
> Label: `signal:feature`
> Body: Users have been asking for dark mode...

**2. Signal is auto-ingested**

`signal-ingestion.yml` fires, creates `docs/01-raw-inputs/SIG-47.md`, opens a PR on branch `signal/47`. Review and merge this PR.

**3. Pipeline orchestrates the next stage**

On merge, `pipeline-orchestrate.yml` detects the new raw input and creates a `pipeline:agent-task` GitHub Issue instructing the agent to write a discovery document (PRB).

**4. Agent picks up the task**

`poll-and-spawn.sh` detects the new issue and runs `ao spawn` to launch an agent. The agent creates `docs/02-discovery/PRB-47.md`, opens a PR with label `pipeline:proposal`.

**5. You approve the proposal**

Review the PR on GitHub, approve it, and merge.

**6. Repeat for architecture and specification**

The pipeline auto-triggers the next stage on each merge. Agent produces ADR-47, then PRD-47. Each gets a `pipeline:proposal` PR that you review and approve.

**7. Agent writes code**

After the spec PR merges, the agent implements the feature in `src/` and `tests/`, opens a code PR.

**8. You review and merge the code**

CI runs tests and doc validation. You review the code, approve, and merge. Feature shipped.

### Execution Mode: Build Plan Tasks

**1. Prepare your build plan**

Create a directory structure:
```
build-plan/
└── workstreams/
    ├── ws0-foundation/
    │   └── tasks/
    │       └── WS0-BB1-T1-project-scaffolding.md
    ├── ws1-auth/
    │   └── tasks/
    │       ├── WS1-BB1-T1-auth-api.md
    │       └── WS1-BB1-T2-auth-ui.md
    └── ...
```

Each task file should include:
- Task ID in the filename (e.g., `WS0-BB1-T1`)
- Dependencies listed as `WS0-BB1-T1`, `WS1-BB1-T1` etc. in the content
- Acceptance criteria
- `must_review` keyword if it needs human gating

**2. Set mode to execution**

```yaml
# pipeline.yaml
mode: execution
```

**3. Trigger the pipeline**

Go to Actions > Pipeline Orchestrator > Run workflow (or `gh workflow run pipeline-orchestrate.yml`).

**4. Tasks execute in dependency order**

- `read-build-plan.sh` finds the first task with no unmet dependencies
- Agent implements it and opens a PR with `pipeline:task` label and `<!-- pipeline-task-id: WS0-BB1-T1 -->` in the body
- On merge, `task-complete.yml` reads the task ID from the PR body, marks it done, and auto-dispatches the next task
- Tasks with unmet dependencies remain blocked until all predecessors complete

**5. Loop until done**

The chain continues automatically. Each merge triggers the next eligible task. You only intervene for `must_review` tasks (gated by `pipeline:human-gate` label) and final code reviews.

### Discovery Mode: Fresh Product

**1. Set mode to discovery**

```yaml
# pipeline.yaml
mode: discovery
discovery:
  synthesis_threshold: 5
```

**2. Collect signals**

File GitHub Issues with `signal:*` labels. Each gets auto-ingested as a SIG document.

**3. Synthesis triggers at threshold**

When the number of SIG files reaches `synthesis_threshold` (default 5), the pipeline creates an agent task to synthesize all signals into a product vision and foundational architecture decisions.

**4. Review the synthesis**

The agent produces a `SYNTHESIS.md` plus foundational ADRs, opens a PR with `pipeline:proposal`. You review the product direction and approve.

---

## Using Agent Orchestrator

Agent Orchestrator (`ao`) is the execution layer that runs AI agents in isolated worktrees. Build-Pipe creates the work orders; `ao` executes them.

### The Autonomous Loop

```
You merge a PR
    → pipeline-orchestrate.yml creates a pipeline:agent-task issue
    → poll-and-spawn.sh detects it, runs ao spawn
    → ao creates a worktree + tmux session
    → agent works autonomously → opens a PR
    → ao auto-retries CI failures (up to 3x)
    → ao forwards review comments to agent
    → you review and merge → loop continues
```

### Common Commands

```bash
# Start ao
ao start

# Start auto-dispatch (watches for new tasks)
./scripts/poll-and-spawn.sh my-project &

# Check agent sessions
ao status

# Manually spawn an agent for a specific issue
ao spawn my-project <issue-number>

# View the web dashboard
ao dashboard

# Stop auto-dispatch
pkill -f poll-and-spawn
```

### Without Agent Orchestrator

Everything works without `ao`. The pipeline creates `pipeline:agent-task` GitHub Issues as work orders. You can process them manually with Claude Code:

```bash
# Find pending work
gh issue list --label "pipeline:agent-task" --state open

# Work on an issue manually
claude  # then follow the instructions in the issue body
```

---

## Project Board (Visual Pipeline Tracking)

Build-Pipe can create a GitHub Project board that auto-updates as signals flow through the pipeline. Each item moves through columns: **Signal Received → Discovery → Synthesis → Architecture → Specification → Dispatched → Code → Complete**.

### Setup

The `/setup` wizard creates the board automatically. Or run manually:

```bash
./scripts/setup-project-board.sh "My Project"
```

For the board to auto-update when workflows run, you need a Personal Access Token stored as a repo secret:

1. Go to https://github.com/settings/tokens?type=beta
2. Create a token with **Projects (read/write)** and **Contents (read/write)** permissions
3. Store it: `gh secret set PROJECT_TOKEN`

Without the PAT, the board still works for manual tracking — workflows gracefully skip board updates.

---

## Self-Improving Pipeline (Autoresearch)

Build-Pipe includes an optional nightly self-improvement cycle inspired by [Karpathy's autoresearch](https://github.com/karpathy/autoresearch). It observes pipeline health metrics, picks the single highest-impact improvement target, runs controlled experiments, and opens a PR with the results.

**The loop:**

```
Nightly cron (your machine)
    │
    ▼  scripts/collect-metrics.sh (deterministic — no AI)
pipeline-metrics.jsonl
    │
    ▼  Dispatch agent (Claude Code)
Analyzes trends → picks ONE improvement target → defines eval
    │
    ▼  Research agent (Claude Code)
Autoresearch loop: baseline → hypothesis → change → eval → keep/discard
    │
    ▼  Opens PR with evidence
You review and merge
```

**One metric, one eval, per night.** After a year of nightly cycles (~365 experiments), the pipeline converges toward flawless execution.

### Setup

1. Edit `docs/06-operations/research-strategy.md` — set your metric targets and priorities
2. Add a cron job:
   ```bash
   # Run at 10pm daily
   crontab -e
   0 22 * * * cd /path/to/your-repo && ./scripts/nightly-cycle.sh >> logs/nightly.log 2>&1
   ```
3. Or run manually: `./scripts/nightly-cycle.sh`

### What It Can Improve

The research agent can modify document templates, agent instructions (`CLAUDE.md`, `.agent-rules.md`), validation rules (`validate-docs.sh`), and signal processing. It cannot modify workflow files, pipeline config, or the research system itself. See `docs/06-operations/research-strategy.md` for the full list.

### Commands

```bash
# Full cycle: collect → dispatch → research → PR
./scripts/nightly-cycle.sh

# Collect metrics only
./scripts/nightly-cycle.sh --metrics-only

# Dispatch only (pick target, skip research)
./scripts/nightly-cycle.sh --dry-run

# View research history
cat docs/06-operations/research-log.jsonl | jq '.'

# View latest metrics
tail -1 pipeline-metrics.jsonl | jq '.'
```

---

## CI Validation Rules

`scripts/validate-docs.sh` enforces these rules on every PR:

| Rule | What It Checks | Severity |
|---|---|---|
| Rule 1 | PRD files link to an ADR | Hard fail |
| Rule 2 | ADR files link to a PRB | Hard fail |
| Rule 3 | PRB files link to a raw input | Hard fail |
| Rule 4 | Source files are referenced in a PRD (or contain `# Implements: PRD-{n}`) | Hard fail |
| Rule 5 | No unfilled template placeholders (`[Short Title]`, `[YYYY-MM-DD]`) | Hard fail |
| Rule 6 | PR touches only one pipeline stage | Hard fail |

Additionally:
- Rules 1-3 verify that referenced files actually exist on disk (not just that references appear in text)
- Rule 4 checks both filename and full-path references in PRDs
- Rule 6 counts stages: raw-inputs, discovery, architecture, specification, code

## File Reference

### Configuration

| File | Purpose |
|---|---|
| `pipeline.yaml` | Pipeline mode (`discovery` / `execution` / `steady-state`) and settings |
| `stack.yaml` | Technology constraints — CI enforces these choices |
| `agent-orchestrator.yaml` | Configuration for `ao` (Agent Orchestrator) |
| `.env.example` | Documents required and optional environment variables |

### Agent Instructions

| File | Purpose |
|---|---|
| `CLAUDE.md` | Agent instructions — pipeline stages, cross-linking rules, PR conventions |
| `.agent-rules.md` | Six mandatory rules the agent must follow (CI-enforced) |
| `QUICKSTART.md` | One-page reference card for daily pipeline use |

### Workflows (GitHub Actions)

| File | Purpose |
|---|---|
| `.github/workflows/signal-ingestion.yml` | Auto-captures `signal:*` issues as structured SIG documents |
| `.github/workflows/pipeline-orchestrate.yml` | Routes work to the correct pipeline stage based on mode |
| `.github/workflows/validate-and-test.yml` | CI — document validation, tests, linting |
| `.github/workflows/task-complete.yml` | Marks execution-mode tasks done and auto-dispatches the next task |

### Scripts

| File | Purpose |
|---|---|
| `scripts/ingest-signal.sh` | Transforms a GitHub Issue into a `docs/01-raw-inputs/SIG-{n}.md` document |
| `scripts/validate-docs.sh` | Enforces cross-linking, no orphaned code, single-stage-per-PR |
| `scripts/read-build-plan.sh` | Manages build plan task ordering, dependency resolution, and status |
| `scripts/poll-and-spawn.sh` | Auto-dispatch bridge — watches for `pipeline:agent-task` issues, runs `ao spawn` |
| `scripts/setup-labels.sh` | Creates all pipeline GitHub labels (idempotent) |
| `scripts/setup-project-board.sh` | Creates GitHub Project board with 8 pipeline stages |
| `scripts/update-project-board.sh` | Moves items through project board stages (called by workflows) |
| `scripts/collect-metrics.sh` | Pulls pipeline health metrics from GitHub API into `pipeline-metrics.jsonl` |
| `scripts/nightly-cycle.sh` | Orchestrates the self-improvement cycle (metrics → dispatch → research) |

### Skills (Claude Code)

| File | Purpose |
|---|---|
| `.claude/skills/setup/SKILL.md` | Interactive `/setup` wizard for project onboarding |
| `.claude/skills/dispatch/SKILL.md` | Dispatch agent — analyzes metrics, picks improvement target |
| `.claude/skills/research/SKILL.md` | Research agent — runs autoresearch experiments |

### Project & Docs

| File | Purpose |
|---|---|
| `docs/00-foundation/PROJECT.md` | Project vision, target users, success metrics |
| `docs/00-foundation/BRAND.md` | Voice, design principles, visual identity |
| `docs/00-foundation/PERSONAS.md` | Target user definitions for discovery docs |
| `docs/00-foundation/CONSTRAINTS.md` | Business rules, compliance, performance, security |
| `docs/06-operations/research-strategy.md` | Human-editable priorities for self-improvement |
| `docs/06-operations/research-log.jsonl` | Append-only log of all research experiments |
| `pipeline-metrics.jsonl` | Append-only pipeline health metrics |
| `.github/project-number` | GitHub Project board number (created by setup-project-board.sh) |
| `.templates/*.md` | Document templates for each pipeline stage |

### Repo Hygiene

| File | Purpose |
|---|---|
| `.gitignore` | Ignores `node_modules/`, `.env`, IDE files, `.pipeline-status.json.lock` |
| `.gitattributes` | Forces LF line endings on `.sh`, `.yml`, `.json`, `.md`, `Makefile` |
| `.editorconfig` | Editor formatting — UTF-8, LF, 2-space indent (4 for Python) |
| `.github/CODEOWNERS` | Auto-assigns you as reviewer for proposal and code PRs |
| `.claude/settings.json` | Claude Code tool permissions (pre-configured for pipeline scripts) |

## Configuration Reference

All settings live in `pipeline.yaml`. Here's every tunable and whether you should touch it:

| Setting | Section | Default | What It Does | Notes |
|---|---|---|---|---|
| `mode` | top-level | `steady-state` | Pipeline operating mode | `discovery` / `execution` / `steady-state` — change as your product matures |
| `synthesis_threshold` | `discovery:` | `5` | Signals to collect before synthesizing into architecture | Only active in discovery mode |
| `build_plan_dir` | `execution:` | `./build-plan` | Path to your build plan directory | Only active in execution mode |
| `workstream_dir` | `execution:` | `./build-plan/workstreams` | Path to workstream task subdirectories | Only active in execution mode |
| `max_parallel_tasks` | `execution:` | `7` | Max concurrent agent sessions dispatched per merge wave | ao has no built-in limit — scale freely based on your dependency graph shape and API rate limits |
| `tracker` | shared | `github` | Where issues/tasks are tracked | **Do not change** — only GitHub is supported |
| `agent` | shared | `claude-code` | Which AI agent to use | **Do not change** unless you've adapted all workflows for another agent |
| `agent_rules_file` | shared | `.agent-rules.md` | Path to agent behavioral rules | **Do not change** — CI and workflows reference this path |

`steady_state` has no configurable settings — signal ingestion is always automatic (driven by `signal-ingestion.yml`), and proposal approval is enforced by GitHub branch protection rules (configure those in repo Settings > Branches, not here).

---

## Troubleshooting

**Pipeline doesn't trigger after merge:**
Check that the merged files match the path filters in `pipeline-orchestrate.yml` (lines 7-10). Only changes in `docs/01-raw-inputs/**` through `docs/04-specs/**` trigger the orchestrator.

**Agent tasks created but not picked up:**
Make sure `poll-and-spawn.sh` is running (`ps aux | grep poll-and-spawn`). If not, start it: `./scripts/poll-and-spawn.sh my-project &`. You can also manually spawn agents: `ao spawn my-project <issue-number>`.

**Execution mode says ALL_BLOCKED:**
All remaining tasks have unmet dependencies. Check `.pipeline-status.json` to see which tasks are marked done. Verify that task files contain the correct dependency IDs in `WS0-BB1-T1` format.

**CI fails with "no test configuration":**
When source code changes are detected but `stack.yaml` testing fields are empty, CI fails. Fill in at least `testing.backend` or `testing.frontend` in `stack.yaml`.

**ao spawn fails:**
Run `ao doctor` to check your installation. Verify `agent-orchestrator.yaml` has the correct repo path and project name. Ensure `gh auth status` shows you're authenticated.
