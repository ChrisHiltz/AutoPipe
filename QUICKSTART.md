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

- [ ] Install ao: `git clone https://github.com/ComposioHQ/agent-orchestrator.git && cd agent-orchestrator && bash scripts/setup.sh`
- [ ] Edit `agent-orchestrator.yaml` — set your project name, repo, and local path
- [ ] Start ao: `ao start`
- [ ] Start auto-dispatch: `./scripts/poll-and-spawn.sh my-project &`

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
```

- [ ] All nine scripts are executable

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

## Optional: GitHub Project Board

A visual Kanban board that auto-updates as signals flow through the pipeline.

### 11. Set Up Project Board (Optional)

- [ ] Run: `./scripts/setup-project-board.sh "My Project"`
- [ ] Create a PAT at https://github.com/settings/tokens?type=beta with Projects (read/write) + Contents (read/write)
- [ ] Store it: `gh secret set PROJECT_TOKEN` (paste token when prompted)

Without the PAT, the board works for manual tracking — workflows skip board updates gracefully.

---

## Optional: Nightly Self-Improvement

Build-Pipe includes an autoresearch loop that improves pipeline artifacts (templates, validation, instructions) through nightly experiments.

### 12. Set Up Nightly Cycle (Optional)

- [ ] Edit `docs/06-operations/research-strategy.md` — set your metric targets and priorities
- [ ] Add cron job: `0 22 * * * cd /path/to/repo && ./scripts/nightly-cycle.sh >> logs/nightly.log 2>&1`
- [ ] Or run manually anytime: `./scripts/nightly-cycle.sh`

The cycle collects metrics, picks one improvement target, runs experiments, and opens a PR if it finds an improvement. You review and merge — same 2-decision-point pattern.
