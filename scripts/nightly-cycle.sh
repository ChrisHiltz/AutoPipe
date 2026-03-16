#!/usr/bin/env bash
# nightly-cycle.sh — Run the self-improvement cycle.
#
# Orchestrates: metrics collection → dispatch (pick target) → research (autoresearch loop)
# Everything runs locally via Claude Code. Results flow through PRs for human review.
#
# Usage:
#   ./scripts/nightly-cycle.sh                    # full cycle
#   ./scripts/nightly-cycle.sh --dry-run           # collect + dispatch only, skip research
#   ./scripts/nightly-cycle.sh --metrics-only      # collect metrics only
#
# Cron setup (run at 10pm daily):
#   0 22 * * * cd /path/to/repo && ./scripts/nightly-cycle.sh >> logs/nightly.log 2>&1

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

MODE="${1:-full}"
TASK_FILE="docs/06-operations/current-research-task.json"
LOG_FILE="docs/06-operations/research-log.jsonl"
STRATEGY_FILE="docs/06-operations/research-strategy.md"

if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; NC=''
fi

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

# ─── Preflight checks ──────────────────────────────────
if ! command -v gh &>/dev/null; then
  log "${RED}ERROR:${NC} gh CLI not found."
  exit 1
fi

if ! command -v claude &>/dev/null; then
  log "${RED}ERROR:${NC} Claude Code not found. Install: npm install -g @anthropic-ai/claude-code"
  exit 1
fi

if ! gh auth status --hostname github.com &>/dev/null 2>&1; then
  log "${RED}ERROR:${NC} gh not authenticated. Run: gh auth login"
  exit 1
fi

if [ ! -f "$STRATEGY_FILE" ]; then
  log "${RED}ERROR:${NC} Research strategy file not found at ${STRATEGY_FILE}"
  log "       Create it before running the nightly cycle."
  exit 1
fi

# Create logs directory if needed
mkdir -p logs

# ─── Step 1: Collect metrics ───────────────────────────
log "${GREEN}Step 1:${NC} Collecting pipeline metrics..."
chmod +x scripts/collect-metrics.sh
./scripts/collect-metrics.sh

if [ "$MODE" = "--metrics-only" ]; then
  log "Metrics collection complete. Exiting (--metrics-only mode)."
  exit 0
fi

# ─── Step 2: Dispatch ─────────────────────────────────
log "${GREEN}Step 2:${NC} Analyzing metrics and selecting research target..."

# Clean up previous task file
rm -f "$TASK_FILE"

timeout 1800 claude -p "$(cat <<'DISPATCH_PROMPT'
You are the Build-Pipe dispatch agent running a nightly self-improvement cycle.

## Your Job
Analyze pipeline health metrics, pick the SINGLE highest-impact improvement target,
and write a research task for the research agent.

## Steps
1. Read `docs/06-operations/research-strategy.md` — your constraints and focus areas
2. Read `pipeline-metrics.jsonl` — recent metrics (last entry is most current)
3. Read `docs/06-operations/research-log.jsonl` — what was already tried (avoid repeats)
4. Identify the metric with the worst trend or biggest gap from target
5. Map it to a modifiable artifact (template, CLAUDE.md, validation script, etc.)
6. Define a concrete synthetic eval that can be run locally
7. Write the research task to `docs/06-operations/current-research-task.json`

## Research Task Format
Write a JSON file with these fields:
{
  "date": "YYYY-MM-DD",
  "target_metric": "metric_name",
  "current_baseline": 0.0,
  "target": 0.0,
  "artifact_to_modify": "path/to/file",
  "hypothesis": "What you think will improve the metric and why",
  "eval": {
    "type": "synthetic",
    "description": "How to measure improvement",
    "success_criterion": "Specific measurable outcome"
  },
  "max_iterations": 5,
  "time_budget_minutes": 30
}

## Rules
- Pick ONE target only
- Never pick the same target two nights in a row
- If metrics are insufficient (< 3 data points), write {"status": "INSUFFICIENT_DATA"} and stop
- Only target artifacts listed as modifiable in research-strategy.md
- The eval must be runnable locally without deploying anything
DISPATCH_PROMPT
)"

# Verify dispatch produced a task
if [ ! -f "$TASK_FILE" ]; then
  log "${RED}ERROR:${NC} Dispatch did not produce a research task. Aborting."
  exit 1
fi

# Check for insufficient data
if jq -e '.status == "INSUFFICIENT_DATA"' "$TASK_FILE" &>/dev/null; then
  log "${YELLOW}SKIP:${NC} Insufficient metrics data. Need more pipeline activity before research can begin."
  exit 0
fi

log "Research target selected:"
jq '.' "$TASK_FILE"

if [ "$MODE" = "--dry-run" ]; then
  log "${YELLOW}DRY RUN:${NC} Skipping research phase. Task file saved at ${TASK_FILE}"
  exit 0
fi

# ─── Step 3: Research ──────────────────────────────────
log "${GREEN}Step 3:${NC} Running autoresearch cycle..."

# Load the full research skill instructions (single source of truth)
SKILL_FILE=".claude/skills/research/SKILL.md"
if [ ! -f "$SKILL_FILE" ]; then
  log "${RED}ERROR:${NC} Research skill file not found at ${SKILL_FILE}"
  exit 1
fi
SKILL_CONTENT=$(cat "$SKILL_FILE")

timeout 1800 claude -p "$(cat <<RESEARCH_PROMPT
You are the Build-Pipe research agent running in automated nightly mode.

## Full Research Protocol

Follow these instructions exactly:

${SKILL_CONTENT}

## Nightly Mode Reminders

- Your assignment is in docs/06-operations/current-research-task.json
- You MUST attempt ALL iterations specified in max_iterations — do not stop early
- Log results to docs/06-operations/research-log.jsonl when done
- If improved: open a PR on branch research/{date}-{metric} with label pipeline:proposal
- If not improved: log and exit without opening a PR
- NEVER modify files listed as off-limits in research-strategy.md
- NEVER modify the research system itself (nightly-cycle.sh, collect-metrics.sh, skills)
RESEARCH_PROMPT
)"

# ─── Step 4: Submit to upstream (best-effort) ───────────
UPSTREAM_REPO=$(grep 'upstream_repo:' pipeline.yaml | awk '{print $2}' | tr -d '"' | tr -d "'" 2>/dev/null || echo "")
if [ -n "$UPSTREAM_REPO" ] && [ "$UPSTREAM_REPO" != "" ]; then
  RESEARCH_BRANCH=$(git branch --list 'research/*' --sort=-committerdate 2>/dev/null | head -1 | tr -d ' *')
  if [ -n "$RESEARCH_BRANCH" ]; then
    log "${GREEN}Step 4:${NC} Submitting improvements to upstream (best-effort)..."
    chmod +x scripts/submit-upstream.sh 2>/dev/null || true
    ./scripts/submit-upstream.sh "$RESEARCH_BRANCH" "$UPSTREAM_REPO" || \
      log "${YELLOW}WARN:${NC} Upstream submission failed (non-blocking)"
  fi
else
  log "No upstream repo configured. Skipping upstream submission."
fi

log "${GREEN}Nightly cycle complete.${NC}"
