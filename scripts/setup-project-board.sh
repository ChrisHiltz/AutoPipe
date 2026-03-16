#!/usr/bin/env bash
# setup-project-board.sh — Create a GitHub Project board for pipeline tracking.
#
# Creates a project with a "Pipeline Stage" field that workflows update automatically
# as signals flow through discovery → architecture → specification → code → complete.
#
# Usage:
#   ./scripts/setup-project-board.sh "My Project"   # named board
#   ./scripts/setup-project-board.sh                 # defaults to "Build-Pipe"
#
# Idempotent: skips creation if a project with the same name already exists.
# Requires: gh CLI authenticated (gh auth login)

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1"; }

PROJECT_NAME="${1:-Build-Pipe}"

# ─── Preflight ────────────────────────────────────────────
if ! command -v gh &>/dev/null; then
  log "${RED}ERROR:${NC} gh CLI not found. Install: https://cli.github.com"
  exit 1
fi

if ! gh auth status --hostname github.com &>/dev/null 2>&1; then
  log "${RED}ERROR:${NC} gh not authenticated. Run: gh auth login"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  log "${RED}ERROR:${NC} jq not found."
  log "  Install jq for your platform:"
  log "    macOS:   brew install jq"
  log "    Ubuntu:  sudo apt-get install -y jq"
  log "    Fedora:  sudo dnf install -y jq"
  log "    Windows: winget install jqlang.jq  (restart your terminal after install)"
  log "  Or download from: https://jqlang.github.io/jq/download/"
  exit 1
fi

# ─── Check for existing project ──────────────────────────
log "Checking for existing project board..."

EXISTING=$(gh project list --owner @me --format json 2>/dev/null \
  | jq -r ".projects[] | select(.title == \"${PROJECT_NAME}\") | .number" 2>/dev/null || echo "")

if [ -n "$EXISTING" ]; then
  log "${YELLOW}Project board already exists:${NC} #${EXISTING} (${PROJECT_NAME})"
  PROJECT_NUMBER="$EXISTING"
else
  # ─── Create project ──────────────────────────────────────
  log "Creating project board: ${PROJECT_NAME}..."
  PROJECT_NUMBER=$(gh project create --owner @me --title "$PROJECT_NAME" --format json \
    | jq -r '.number')
  log "${GREEN}Created project board:${NC} #${PROJECT_NUMBER}"
fi

# ─── Add "Pipeline Stage" field ───────────────────────────
log "Configuring Pipeline Stage field..."

# Check if field already exists
FIELDS=$(gh project field-list "$PROJECT_NUMBER" --owner @me --format json 2>/dev/null || echo '{"fields":[]}')
STAGE_FIELD=$(echo "$FIELDS" | jq -r '.fields[] | select(.name == "Pipeline Stage") | .id' 2>/dev/null || echo "")

if [ -n "$STAGE_FIELD" ]; then
  log "${YELLOW}Pipeline Stage field already exists.${NC} Skipping."
else
  gh project field-create "$PROJECT_NUMBER" --owner @me \
    --name "Pipeline Stage" \
    --data-type "SINGLE_SELECT" \
    --single-select-options "Signal Received,Discovery,Synthesis,Architecture,Specification,Dispatched,Code,Complete" \
    2>/dev/null || log "${YELLOW}Note:${NC} Could not create Pipeline Stage field. You may need to add it manually in the project settings."
  log "${GREEN}Added Pipeline Stage field${NC} with 8 stages."
fi

# ─── Save project number for workflows ────────────────────
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_FILE="${REPO_ROOT}/.github/project-number"

echo "$PROJECT_NUMBER" > "$PROJECT_FILE"
log "${GREEN}Saved project number${NC} to .github/project-number"

# ─── Get project URL ──────────────────────────────────────
OWNER=$(gh api user -q '.login' 2>/dev/null || echo "unknown")
log ""
log "${GREEN}Project board ready!${NC}"
log "  View at: https://github.com/users/${OWNER}/projects/${PROJECT_NUMBER}"
log ""
log "For workflow automation, you'll need a Personal Access Token:"
log "  1. Go to https://github.com/settings/tokens?type=beta"
log "  2. Create a token with 'Projects (read/write)' and 'Repository (read/write)' permissions"
log "  3. Store it: gh secret set PROJECT_TOKEN"
log "  (Workflows will gracefully skip board updates if this isn't configured)"
