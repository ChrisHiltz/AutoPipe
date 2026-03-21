# Build-Pipe Quick Start Checklist

Get from zero to a running pipeline in 15 minutes. Check each box as you go.

> **Fastest path:** After copying the template and installing prerequisites, run `claude` in your repo root and type `/setup`. The setup wizard will walk you through everything below interactively.

---

## Prerequisites

- [ ] GitHub repository created (public or private)
- [ ] [Agent Orchestrator](https://github.com/ComposioHQ/agent-orchestrator) installed (recommended)
- [ ] [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed (`npm install -g @anthropic-ai/claude-code`)
- [ ] `jq` installed (`brew install jq` / `apt install jq` / `choco install jq`)
- [ ] [GitHub CLI](https://cli.github.com/) installed (`gh auth login` completed)

## Accounts & API Keys

| What | Where to Get It | Where It Goes |
|---|---|---|
| Anthropic API Key | [console.anthropic.com](https://console.anthropic.com/) | Local env: `export ANTHROPIC_API_KEY=sk-ant-...` |
| GitHub Token | Auto-available in Actions as `GITHUB_TOKEN` | Already configured in workflows |

## Setup Steps

### 1. Copy Template into Your Repo

```bash
cp -r project-template/* /path/to/your-repo/
cp -r project-template/.* /path/to/your-repo/  # hidden files (.claude, .github, .templates, .agent-rules.md)
```

- [ ] All files copied (verify with `ls -la` — you should see `.github/`, `.claude/`, `.templates/`, `.agent-rules.md`)

### 2. Configure Your Stack

- [ ] Edit `stack.yaml` — set your project name, frameworks, database, testing tools, and hosting

### 2a. Configure Local Development

- [ ] Edit `stack.yaml` section `local_dev`:
  - `strategy` — how devs run locally (e.g., `docker-compose`, `native`, `devcontainer`)
  - `bootstrap_command` — single command from clone to running (e.g., `make dev`)
  - `prerequisites` — system deps (e.g., `Docker 24+`, `Node 20+`)
  - `seed_data` — how test data loads (e.g., `make seed`, or `none`)
  - `env_setup` — how env vars get configured (e.g., `cp .env.example .env`)
- [ ] Customize `.env.example` with application-specific environment variables

### 2b. Fill In Project Foundation (Recommended)

- [ ] Edit `docs/00-foundation/PROJECT.md` — vision, target users, success metrics, non-goals
- [ ] Edit `docs/00-foundation/BRAND.md` — voice, design principles, visual identity (optional)
- [ ] Edit `docs/00-foundation/PERSONAS.md` — user persona definitions (optional)
- [ ] Edit `docs/00-foundation/CONSTRAINTS.md` — business rules, compliance, performance (optional)

These give agents context about your project. At minimum, fill in PROJECT.md — the rest can wait.

### 3. Set Pipeline Mode

- [ ] Edit `pipeline.yaml` line 1 — choose one:
  - `mode: steady-state` — Live product, processing incoming signals
  - `mode: execution` — Locked build plan with task dependencies
  - `mode: discovery` — Fresh product, collecting research

### 4. Create GitHub Labels

- [ ] Go to repo Settings > Labels and create:

| Label | Color |
|---|---|
| `signal:bug` | `#d73a4a` |
| `signal:feature` | `#0075ca` |
| `signal:feedback` | `#e4e669` |
| `signal:analytics` | `#bfdadc` |
| `pipeline:signal` | `#c5def5` |
| `pipeline:proposal` | `#0e8a16` |
| `pipeline:agent-task` | `#5319e7` |
| `pipeline:task` | `#5319e7` |
| `pipeline:claimed` | `#c2e0c6` |
| `pipeline:human-gate` | `#fbca04` |
| `pipeline:failure` | `#b60205` |

### 5. Set Up Agent Orchestrator

- [ ] Install and configure ao: `./scripts/setup-ao.sh` (detects platform, installs all dependencies)
- [ ] Edit `agent-orchestrator.yaml` — verify your project name, repo, and local path
- [ ] Start ao + auto-dispatch: `./scripts/ao-start.sh`

> **Windows users:** ao requires tmux, which runs inside WSL. The `setup-ao.sh` script automatically detects Git Bash and relays setup into WSL. After setup, `ao-start.sh` does the same for launching. All ao operations run transparently inside WSL while your code stays on the Windows filesystem.

### 6. Set Up CODEOWNERS

- [ ] Edit `.github/CODEOWNERS` — replace `@your-github-username` with your actual GitHub username

### 7. Enable Branch Protection

- [ ] Go to repo Settings > Branches > Add rule for `main`:
  - [x] Require pull request reviews (1 approval)
  - [x] Require status checks: `Validate Document Pipeline`, `Run Test Suite`
  - [x] Require review from Code Owners
  - [x] Do not allow bypassing the above settings

### 8. Configure Claude Code

- [ ] Set your API key: `export ANTHROPIC_API_KEY=sk-ant-...`
- [ ] Verify Claude Code reads `CLAUDE.md`: run `claude` in your repo root

### 9. Make Scripts Executable

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
chmod +x scripts/setup-ao.sh
chmod +x scripts/verify-ao.sh
chmod +x scripts/ao-start.sh
```

- [ ] All twelve scripts are executable

### 10. Push and Verify

```bash
git add -A
git commit -m "feat: initialize Build-Pipe pipeline"
git push origin main
```

- [ ] Workflows visible in GitHub Actions tab

---

## Verify It Works

Create a test signal:

1. Open a GitHub Issue with label `signal:feature` and title "Test signal"
2. Watch the Actions tab — `signal-ingestion.yml` should fire
3. A PR should appear on branch `signal/{issue_number}` with `docs/01-raw-inputs/SIG-{n}.md`

If the PR appears, your pipeline is live.

---

## Your Two Decision Points

Once running, you only make two kinds of decisions:

1. **Approve proposals** — Review and approve discovery/architecture/spec PRs on GitHub
2. **Approve code** — Review and merge implementation PRs on GitHub

Everything else is autonomous.

---

## REQUIRED: GitHub Project Board & Views

The project board is your team's **operational command center**. Without it, you have no visibility into what agents are doing, what needs your approval, or what's stuck in rework. Every signal, proposal, and code PR flows through this board.

### 11. Set Up Project Board

- [ ] Run: `./scripts/setup-project-board.sh "My Project"` (creates board with Pipeline Stage field)
- [ ] Add custom fields (run each command):

```bash
# These fields are REQUIRED for the approval queue to work
gh project field-create PROJECT_NUM --owner YOUR_ORG --name "Review Status" --data-type "SINGLE_SELECT" --single-select-options "Queued,Needs Review,Approved,Changes Requested"
gh project field-create PROJECT_NUM --owner YOUR_ORG --name "Priority" --data-type "SINGLE_SELECT" --single-select-options "P0 Critical,P1 High,P2 Medium,P3 Low"
gh project field-create PROJECT_NUM --owner YOUR_ORG --name "Signal Type" --data-type "SINGLE_SELECT" --single-select-options "Bug,Feature,Feedback,Analytics"
```

Replace `PROJECT_NUM` with your project number (stored in `.github/project-number`) and `YOUR_ORG` with your GitHub org or username.

- [ ] Create `.github/project-owner` containing your org name (e.g., `echo "my-org" > .github/project-owner`)

### 11a. Set Up Project Board Views (MANDATORY)

Open your project board URL and create these 3 views. **Do not skip this** — without the Approval Queue, your team cannot efficiently process pipeline work.

#### View 1: Approval Queue (your team's daily driver)

This is where your team spends 90% of their time. It shows exactly what needs a human decision RIGHT NOW.

1. Click **"+ New view"** at the top of the project board
2. Select **"Table"** layout
3. Name it **"Approval Queue"**
4. Click the **filter icon** (funnel) in the toolbar
5. Add filter: **Review Status** → **is** → **Needs Review**
6. Click **"Group by"** → select **Pipeline Stage** (groups items by Discovery, Architecture, Specification, Code)
7. Click **"Sort"** → select **Priority** → **Ascending** (P0 Critical appears first)
8. Add visible columns by clicking **"+"** on the header row:
   - Title
   - Pipeline Stage
   - Priority
   - Assignees
   - Linked pull requests (click the PR link to go directly to the review)
9. Remove any columns you don't need (right-click column header → Hide)

**How to use it:** Open this view daily. Each row is a PR waiting for your review. Click the linked PR, review it, approve or request changes. The board updates automatically.

#### View 2: Pipeline Overview (at-a-glance health check)

Shows everything in flight across all stages. Use this to spot bottlenecks.

1. Click **"+ New view"**
2. Select **"Board"** layout
3. Name it **"Pipeline Overview"**
4. Set **"Column field"** to **Pipeline Stage**
5. No filter — shows all items
6. Cards should show: Title, Priority, Review Status

**How to use it:** Glance at this weekly or when something feels stuck. If one column has too many items, that's your bottleneck.

#### View 3: Rework Needed (items agents need to fix)

Shows items where you requested changes. Agents pick these up automatically via `ao`, but this view lets you track rework progress.

1. Click **"+ New view"**
2. Select **"Table"** layout
3. Name it **"Rework"**
4. Click the **filter icon**
5. Add filter: **Review Status** → **is** → **Changes Requested**
6. Click **"Sort"** → select **Priority** → **Ascending**
7. Add visible columns: Title, Pipeline Stage, Priority, Assignees, Linked pull requests

**How to use it:** Check this when you want to see if agents have addressed your feedback. Once an agent re-submits, the item moves back to the Approval Queue automatically.

### 11b. Set Up Board Automation Token

For the board to auto-update as agents work, you need a Personal Access Token stored as a repo secret.

- [ ] Go to https://github.com/settings/tokens?type=beta
- [ ] Click **"Generate new token"**
- [ ] Name it **"Build-Pipe Project Board"**
- [ ] Under **"Repository access"**, select your repo
- [ ] Under **"Permissions"**, enable: **Projects (read/write)** and **Contents (read/write)**
- [ ] Generate and copy the token
- [ ] Store it: `gh secret set PROJECT_TOKEN` (paste when prompted)

Without the PAT, workflows skip board updates gracefully — the pipeline still works, but the board won't reflect real-time status.

### Board Field Reference

| Field | Values | Updated By |
|-------|--------|-----------|
| **Pipeline Stage** | Signal Received, Discovery, Synthesis, Architecture, Specification, Dispatched, Code, Complete | `pipeline-orchestrate.yml`, `signal-ingestion.yml`, `task-complete.yml` |
| **Review Status** | Queued (agent working), Needs Review (PR open for human), Approved, Changes Requested | `pipeline-orchestrate.yml`, `pr-review-tracking.yml` |
| **Priority** | P0 Critical, P1 High, P2 Medium, P3 Low | Set manually or by signal classification |
| **Signal Type** | Bug, Feature, Feedback, Analytics | `signal-ingestion.yml` (from issue label) |

### Review Status Lifecycle

```
Agent dispatched → Queued
Agent opens PR   → Needs Review  ← YOU SEE THIS IN THE APPROVAL QUEUE
You approve      → Approved      → auto-merges or you merge → next stage triggered
You deny         → Changes Requested → agent reworks → Needs Review (back in queue)
```

---

## Optional: Nightly Self-Improvement

Build-Pipe includes an autoresearch loop that improves pipeline artifacts (templates, validation, instructions) through nightly experiments.

### 12. Set Up Nightly Cycle (Optional)

- [ ] Edit `docs/06-operations/research-strategy.md` — set your metric targets and priorities
- [ ] Add cron job: `0 22 * * * cd /path/to/repo && ./scripts/nightly-cycle.sh >> logs/nightly.log 2>&1`
- [ ] Or run manually anytime: `./scripts/nightly-cycle.sh`

The cycle collects metrics, picks one improvement target, runs experiments, and opens a PR if it finds an improvement. You review and merge — same 2-decision-point pattern.
