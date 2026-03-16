#!/usr/bin/env bash
# update-project-board.sh — Add or move an item on the GitHub Project board.
#
# Called by GitHub Actions workflows to automatically track pipeline progress.
# Gracefully exits 0 if the project board isn't configured — never breaks the pipeline.
#
# Usage:
#   ./scripts/update-project-board.sh <issue-or-pr-url> <stage-name>
#
# Examples:
#   ./scripts/update-project-board.sh "https://github.com/org/repo/issues/42" "Discovery"
#   ./scripts/update-project-board.sh "https://github.com/org/repo/pull/15" "Complete"
#
# Stage names must match the Pipeline Stage field options:
#   Signal Received | Discovery | Architecture | Specification | Code | Complete

set -euo pipefail

ITEM_URL="${1:-}"
STAGE="${2:-}"

if [ -z "$ITEM_URL" ] || [ -z "$STAGE" ]; then
  echo "Usage: update-project-board.sh <issue-or-pr-url> <stage-name>"
  exit 1
fi

# ─── Read project configuration ───────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROJECT_FILE="${REPO_ROOT}/.github/project-number"

if [ ! -f "$PROJECT_FILE" ]; then
  echo "No project board configured (.github/project-number not found). Skipping."
  exit 0
fi

PROJECT_NUMBER=$(cat "$PROJECT_FILE")
if [ -z "$PROJECT_NUMBER" ]; then
  echo "Project number is empty. Skipping."
  exit 0
fi

# ─── Determine project owner ─────────────────────────────
# In GitHub Actions, use the repo owner. Locally, use @me.
if [ -n "${GITHUB_REPOSITORY_OWNER:-}" ]; then
  OWNER="$GITHUB_REPOSITORY_OWNER"
else
  OWNER="@me"
fi

# ─── Add item to project (idempotent) ────────────────────
ITEM_RESPONSE=$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" \
  --url "$ITEM_URL" --format json 2>/dev/null) || {
  echo "Could not add item to project board. Skipping."
  exit 0
}

ITEM_ID=$(echo "$ITEM_RESPONSE" | jq -r '.id' 2>/dev/null)
if [ -z "$ITEM_ID" ] || [ "$ITEM_ID" = "null" ]; then
  echo "Could not extract item ID. Skipping."
  exit 0
fi

# ─── Get project node ID ─────────────────────────────────
PROJECT_ID=$(gh project view "$PROJECT_NUMBER" --owner "$OWNER" \
  --format json 2>/dev/null | jq -r '.id' 2>/dev/null) || {
  echo "Could not get project ID. Skipping."
  exit 0
}

# ─── Get field and option IDs ─────────────────────────────
FIELDS=$(gh project field-list "$PROJECT_NUMBER" --owner "$OWNER" \
  --format json 2>/dev/null) || {
  echo "Could not list project fields. Skipping."
  exit 0
}

FIELD_ID=$(echo "$FIELDS" | jq -r '.fields[] | select(.name == "Pipeline Stage") | .id' 2>/dev/null)
if [ -z "$FIELD_ID" ] || [ "$FIELD_ID" = "null" ]; then
  echo "Pipeline Stage field not found on project board. Skipping."
  exit 0
fi

OPTION_ID=$(echo "$FIELDS" | jq -r ".fields[] | select(.name == \"Pipeline Stage\") | .options[] | select(.name == \"${STAGE}\") | .id" 2>/dev/null)
if [ -z "$OPTION_ID" ] || [ "$OPTION_ID" = "null" ]; then
  echo "Stage option '${STAGE}' not found. Valid: Signal Received, Discovery, Synthesis, Architecture, Specification, Dispatched, Code, Complete"
  exit 0
fi

# ─── Update the item's stage ─────────────────────────────
gh project item-edit --id "$ITEM_ID" --project-id "$PROJECT_ID" \
  --field-id "$FIELD_ID" --single-select-option-id "$OPTION_ID" 2>/dev/null || {
  echo "Could not update project board item. Skipping."
  exit 0
}

echo "Project board updated: ${STAGE} — ${ITEM_URL}"
