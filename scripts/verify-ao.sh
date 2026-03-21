#!/usr/bin/env bash
# verify-ao.sh — Health check for Agent Orchestrator readiness.
#
# Run before starting ao to verify all prerequisites are met.
# Exit 0 if everything looks good, exit 1 if something is broken.
#
# Usage:
#   ./scripts/verify-ao.sh
#
# Designed for: manual checks, pre-flight before ao start, monitoring scripts.

set -euo pipefail

if [ -t 1 ]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; NC=''
fi

pass() { echo -e "  ${GREEN}PASS${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC}  $1"; WARNINGS=$((WARNINGS + 1)); }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; FAILURES=$((FAILURES + 1)); }

FAILURES=0
WARNINGS=0

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "ao health check"
echo "───────────────"

# 1. WSL check
if grep -qi microsoft /proc/version 2>/dev/null; then
  pass "Running inside WSL"
elif [ "$(uname -s)" = "Linux" ] || [ "$(uname -s)" = "Darwin" ]; then
  pass "Running on $(uname -s)"
else
  warn "Not running in WSL — tmux runtime requires Linux/WSL"
fi

# 2. ao CLI
if command -v ao &>/dev/null; then
  AO_VER=$(ao --version 2>/dev/null || echo "unknown")
  pass "ao ${AO_VER}"
else
  fail "ao not found — run ./scripts/setup-ao.sh"
fi

# 3. tmux
if command -v tmux &>/dev/null; then
  pass "tmux $(tmux -V 2>/dev/null | awk '{print $2}' || echo '')"
else
  fail "tmux not found — required for ao runtime"
fi

# 4. agent-orchestrator.yaml + path
CONFIG_FILE="$REPO_ROOT/agent-orchestrator.yaml"
if [ -f "$CONFIG_FILE" ]; then
  pass "agent-orchestrator.yaml exists"

  CONFIG_PATH=$(grep 'path:' "$CONFIG_FILE" | head -1 | sed 's/.*path: *//; s/^"//; s/"$//')
  if [ -d "$CONFIG_PATH" ]; then
    pass "Config path exists: ${CONFIG_PATH}"
  else
    fail "Config path does not exist: ${CONFIG_PATH}"
  fi
else
  fail "agent-orchestrator.yaml not found"
fi

# 5. Config repo matches git remote
if [ -f "$CONFIG_FILE" ]; then
  CONFIG_REPO=$(grep 'repo:' "$CONFIG_FILE" | head -1 | awk '{print $2}')
  ACTUAL_REMOTE=$(cd "$REPO_ROOT" && git remote get-url origin 2>/dev/null | sed 's|.*github.com[:/]||; s|\.git$||' || echo "")
  if [ -n "$ACTUAL_REMOTE" ] && [ "$CONFIG_REPO" = "$ACTUAL_REMOTE" ]; then
    pass "Repo matches remote: ${CONFIG_REPO}"
  elif [ -n "$ACTUAL_REMOTE" ]; then
    warn "Config repo '${CONFIG_REPO}' differs from remote '${ACTUAL_REMOTE}'"
  else
    warn "Could not detect git remote to compare"
  fi
fi

# 6. gh auth
if command -v gh &>/dev/null; then
  if gh auth status --hostname github.com &>/dev/null 2>&1; then
    pass "gh authenticated"
  else
    fail "gh not authenticated — run: gh auth login"
  fi
else
  fail "gh CLI not found"
fi

# 7. Claude Code CLI
if command -v claude &>/dev/null; then
  pass "Claude Code CLI found"
else
  fail "Claude Code CLI not found — run: npm install -g @anthropic-ai/claude-code"
fi

# Summary
echo ""
echo "───────────────"
if [ "$FAILURES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
  echo -e "${GREEN}All checks passed.${NC} ao is ready to start."
elif [ "$FAILURES" -eq 0 ]; then
  echo -e "${YELLOW}${WARNINGS} warning(s), 0 failures.${NC} ao should work but check warnings."
else
  echo -e "${RED}${FAILURES} failure(s), ${WARNINGS} warning(s).${NC} Fix FAIL items before starting ao."
fi

exit "$FAILURES"
