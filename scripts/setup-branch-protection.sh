#!/usr/bin/env bash
# setup-branch-protection.sh — Configure branch protection rules on main.
# Idempotent: updates existing rules if they already exist.
#
# Requires: gh CLI authenticated with admin access to the repo.
# Note: Branch protection on private repos requires GitHub Pro or higher.
#
# Usage: ./scripts/setup-branch-protection.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "$1"; }

# ─── Preflight ────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  log "${RED}ERROR:${NC} gh CLI not found. Install from https://cli.github.com/"
  exit 1
fi

if ! gh auth status --hostname github.com &>/dev/null 2>&1; then
  log "${RED}ERROR:${NC} gh CLI not authenticated. Run: gh auth login"
  exit 1
fi

REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")
if [ -z "$REPO" ]; then
  log "${RED}ERROR:${NC} Not in a GitHub repository. Run this from your project root."
  exit 1
fi

BRANCH="main"

log "Setting up branch protection for ${REPO} (branch: ${BRANCH})..."
log ""

# ─── Apply branch protection rules ──────────────────────
# Uses the GitHub REST API to set branch protection.
# See: https://docs.github.com/en/rest/branches/branch-protection
RESPONSE=$(gh api \
  --method PUT \
  "repos/${REPO}/branches/${BRANCH}/protection" \
  --input - 2>&1 <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "contexts": ["Validate Document Pipeline", "Run Test Suite"]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "required_approving_review_count": 1,
    "require_code_owner_reviews": true,
    "dismiss_stale_reviews": false
  },
  "restrictions": null
}
EOF
) || {
  EXIT_CODE=$?

  # Check for common failure reasons
  if echo "$RESPONSE" | grep -qi "not found\|Resource not accessible"; then
    log "${YELLOW}WARNING:${NC} Could not set branch protection."
    log ""
    log "  This usually means one of:"
    log "  1. The '${BRANCH}' branch doesn't exist yet (push at least one commit first)"
    log "  2. This is a private repo on GitHub Free (branch protection requires Pro: github.com/settings/billing)"
    log "  3. You don't have admin access to this repo"
    log ""
    log "  You can set branch protection manually: Settings > Branches > Add rule for '${BRANCH}'"
    log "  Required settings:"
    log "    - Require pull request reviews (1 approval)"
    log "    - Require status checks: 'Validate Document Pipeline', 'Run Test Suite'"
    log "    - Require review from Code Owners"
    log ""
    log "  Re-run this script after resolving the issue."
    exit 0  # Don't fail setup — this is non-blocking
  fi

  log "${RED}ERROR:${NC} Unexpected error setting branch protection."
  log "$RESPONSE"
  exit $EXIT_CODE
}

log "${GREEN}Branch protection configured:${NC}"
log "  - Require PR reviews (1 approval)"
log "  - Require status checks: Validate Document Pipeline, Run Test Suite"
log "  - Require Code Owner reviews"
log "  - Enforce for admins"
log ""
log "Verify at: https://github.com/${REPO}/settings/branches"
