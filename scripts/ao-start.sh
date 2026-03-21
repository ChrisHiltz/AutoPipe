#!/usr/bin/env bash
# ao-start.sh — Start Agent Orchestrator and auto-dispatch.
#
# Launches ao + poll-and-spawn.sh together. Works from Git Bash (auto-relays
# to WSL) or directly from WSL.
#
# Usage:
#   ./scripts/ao-start.sh                     # Start ao + auto-dispatch
#   ./scripts/ao-start.sh --ao-only           # Start ao without auto-dispatch
#
# To stop:
#   pkill -f 'ao start' && pkill -f poll-and-spawn

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:-full}"

# Detect ao project name from agent-orchestrator.yaml
AO_PROJECT=$(grep -A1 '^projects:' "$REPO_ROOT/agent-orchestrator.yaml" 2>/dev/null | tail -1 | sed 's/:.*//' | tr -d ' ' || echo "")
if [ -z "$AO_PROJECT" ]; then
  echo "ERROR: Could not detect project name from agent-orchestrator.yaml"
  exit 1
fi

# ─── Git Bash → WSL relay ────────────────────────────
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    REPO_WSL=$(echo "$REPO_ROOT" | sed 's|^/\([a-zA-Z]\)/|/mnt/\L\1/|')
    echo "Detected Git Bash. Launching in WSL..."
    exec wsl bash -c "cd \"$REPO_WSL\" && bash scripts/ao-start.sh $MODE"
    ;;
esac

# ─── Pre-flight ──────────────────────────────────────
"$REPO_ROOT/scripts/verify-ao.sh" || {
  echo "Pre-flight failed. Run ./scripts/setup-ao.sh to fix."
  exit 1
}

cd "$REPO_ROOT"

# ─── Start ao ────────────────────────────────────────
echo ""
echo "Starting ao..."
ao start &
AO_PID=$!
echo "ao running (PID ${AO_PID})"

if [ "$MODE" = "--ao-only" ]; then
  echo "ao-only mode. Auto-dispatch not started."
  echo "To stop: kill ${AO_PID}"
  wait "$AO_PID"
  exit 0
fi

# ─── Start poll-and-spawn ────────────────────────────
echo "Starting auto-dispatch (poll-and-spawn)..."
"$REPO_ROOT/scripts/poll-and-spawn.sh" "$AO_PROJECT" &
POLL_PID=$!
echo "poll-and-spawn running (PID ${POLL_PID})"

echo ""
echo "ao + auto-dispatch running."
echo "  ao PID:            ${AO_PID}"
echo "  poll-and-spawn PID: ${POLL_PID}"
echo ""
echo "To stop: pkill -f 'ao start' && pkill -f poll-and-spawn"
echo ""

# Wait for either process to exit
wait -n "$AO_PID" "$POLL_PID" 2>/dev/null || true
echo "A process exited. Cleaning up..."
kill "$AO_PID" "$POLL_PID" 2>/dev/null || true
