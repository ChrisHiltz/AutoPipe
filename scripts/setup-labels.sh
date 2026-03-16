#!/usr/bin/env bash
# setup-labels.sh — Create all Build-Pipe GitHub labels.
# Idempotent: skips labels that already exist.
#
# Usage: ./scripts/setup-labels.sh

set -euo pipefail

# Verify gh CLI is available and authenticated
if ! command -v gh &>/dev/null; then
  echo "ERROR: gh CLI not found. Install from https://cli.github.com/"
  exit 1
fi

if ! gh auth status --hostname github.com &>/dev/null; then
  echo "ERROR: gh CLI not authenticated. Run: gh auth login"
  exit 1
fi

# All Build-Pipe labels: "name|color|description"
LABELS=(
  "signal:bug|d73a4a|Bug report signals"
  "signal:feature|0075ca|Feature request signals"
  "signal:feedback|e4e669|User feedback signals"
  "signal:analytics|bfdadc|Analytics-driven signals"
  "pipeline:signal|c5def5|Signal ingestion PRs"
  "pipeline:proposal|0e8a16|Document PRs needing approval"
  "pipeline:agent-task|5319e7|Work orders for the agent"
  "pipeline:task|5319e7|Execution-mode task PRs"
  "pipeline:claimed|c2e0c6|Applied by poll-and-spawn to prevent double-dispatch"
  "pipeline:human-gate|fbca04|Tasks requiring human review"
  "pipeline:failure|b60205|Pipeline failure notifications"
  "improvement|1d76db|Template improvement submitted from a fork"
  "improvement:critical|d73a4a|Critical — pipeline is broken"
  "improvement:high|e99695|High — key feature fails"
  "improvement:medium|fbca04|Medium — friction or missing automation"
  "improvement:low|c5def5|Low — minor inconvenience"
  "pipeline:errata|d93f0b|ADR inaccuracies flagged by code agents"
)

echo "Creating Build-Pipe labels..."
echo ""

CREATED=0
SKIPPED=0
FAILED=0

for ENTRY in "${LABELS[@]}"; do
  IFS='|' read -r NAME COLOR DESC <<< "$ENTRY"

  if gh label create "$NAME" --color "$COLOR" --description "$DESC" 2>/dev/null; then
    echo "  + $NAME (created)"
    CREATED=$((CREATED + 1))
  else
    # Label likely already exists — verify
    if gh label list --json name -q '.[].name' 2>/dev/null | grep -qx "$NAME"; then
      echo "  - $NAME (already exists, skipped)"
      SKIPPED=$((SKIPPED + 1))
    else
      echo "  ! $NAME (failed to create)"
      FAILED=$((FAILED + 1))
    fi
  fi
done

echo ""
echo "Done: ${CREATED} created, ${SKIPPED} skipped, ${FAILED} failed."

if [ "$FAILED" -gt 0 ]; then
  echo "WARNING: Some labels failed. Check your repo permissions."
  exit 1
fi
