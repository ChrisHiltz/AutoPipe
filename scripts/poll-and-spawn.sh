#!/usr/bin/env bash
# poll-and-spawn.sh — Auto-dispatch bridge between Build-Pipe and Agent Orchestrator.
#
# Watches for new pipeline:agent-task issues on GitHub and spawns ao sessions
# for each one. Run this alongside ao on your local machine.
#
# Usage:
#   ./scripts/poll-and-spawn.sh <ao-project-name> [poll-interval-seconds]
#
# Examples:
#   ./scripts/poll-and-spawn.sh my-project          # Poll every 5 min
#   ./scripts/poll-and-spawn.sh my-project 60       # Poll every 1 min
#   ./scripts/poll-and-spawn.sh my-project &         # Run in background
#
# Requirements:
#   - gh CLI authenticated (gh auth login)
#   - ao installed and configured (agent-orchestrator.yaml)
#
# To stop: Ctrl+C, or: pkill -f poll-and-spawn

set -euo pipefail

PROJECT="${1:-}"
POLL_INTERVAL="${2:-300}"

if [ -z "$PROJECT" ]; then
  echo "Usage: $0 <ao-project-name> [poll-interval-seconds]"
  echo ""
  echo "The project name must match a project in your agent-orchestrator.yaml."
  echo "Example: $0 my-project 300"
  exit 1
fi

# Verify dependencies
command -v gh &>/dev/null || { echo "ERROR: gh CLI not found. Install from https://cli.github.com/"; exit 1; }
command -v ao &>/dev/null || { echo "ERROR: ao not found. Install from https://github.com/ComposioHQ/agent-orchestrator"; exit 1; }

echo "Build-Pipe auto-dispatch starting..."
echo "  Project: ${PROJECT}"
echo "  Poll interval: ${POLL_INTERVAL}s"
echo "  Watching for: pipeline:agent-task issues (excluding pipeline:claimed)"
echo ""
echo "Press Ctrl+C to stop."
echo ""

while true; do
  # Find open agent-task issues that haven't been claimed yet
  ISSUES=$(gh issue list \
    --label "pipeline:agent-task" \
    --state open \
    --json number,labels,title \
    -q '[.[] | select(.labels | map(.name) | index("pipeline:claimed") | not)] | .[].number' \
    2>/dev/null || echo "")

  if [ -n "$ISSUES" ]; then
    for ISSUE_NUM in $ISSUES; do
      TITLE=$(gh issue view "$ISSUE_NUM" --json title -q '.title' 2>/dev/null || echo "unknown")
      echo "[$(date '+%H:%M:%S')] Found unclaimed task: #${ISSUE_NUM} — ${TITLE}"

      # Mark as claimed immediately to prevent double-spawning
      if ! gh issue edit "$ISSUE_NUM" --add-label "pipeline:claimed" 2>/dev/null; then
        echo "[$(date '+%H:%M:%S')] WARNING: Could not claim #${ISSUE_NUM}. Skipping to prevent conflicts."
        continue
      fi
      echo "[$(date '+%H:%M:%S')] Labeled #${ISSUE_NUM} as claimed"

      # Spawn ao session
      echo "[$(date '+%H:%M:%S')] Spawning: ao spawn ${PROJECT} ${ISSUE_NUM}"
      ao spawn "$PROJECT" "$ISSUE_NUM" || {
        echo "[$(date '+%H:%M:%S')] WARNING: ao spawn failed for #${ISSUE_NUM}. Removing claimed label."
        gh issue edit "$ISSUE_NUM" --remove-label "pipeline:claimed" 2>/dev/null || true
      }

      echo ""
    done
  fi

  sleep "$POLL_INTERVAL"
done
