#!/usr/bin/env bash
# ingest-signal.sh — Transforms a GitHub Issue into a structured raw input document.
#
# Expected env vars (set by signal-ingestion.yml):
#   ISSUE_NUMBER, ISSUE_TITLE, ISSUE_BODY, ISSUE_AUTHOR,
#   ISSUE_DATE, SIGNAL_TYPE, REPO_NAME

set -euo pipefail

# Cross-platform sed -i (macOS requires '' argument, GNU does not)
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

OUTPUT_DIR="docs/01-raw-inputs"
OUTPUT_FILE="${OUTPUT_DIR}/SIG-${ISSUE_NUMBER}.md"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Format the date (extract YYYY-MM-DD from ISO timestamp)
FORMATTED_DATE=$(echo "$ISSUE_DATE" | cut -d'T' -f1 2>/dev/null || echo "$ISSUE_DATE")

# Map signal type to human-readable label
case "$SIGNAL_TYPE" in
  bug)       TYPE_LABEL="Bug Report" ;;
  feature)   TYPE_LABEL="Feature Request" ;;
  feedback)  TYPE_LABEL="User Feedback" ;;
  analytics) TYPE_LABEL="Analytics Insight" ;;
  *)         TYPE_LABEL="Unclassified Signal" ;;
esac

# Sanitize inputs to prevent heredoc injection and shell escapes
# Replace any line that is exactly the heredoc delimiter
SAFE_TITLE=$(printf '%s' "$ISSUE_TITLE" | tr -d '\r')
SAFE_BODY=$(printf '%s' "$ISSUE_BODY" | sed 's/^ENDSIGNAL$/ENDSIGNAL_ESCAPED/g' | tr -d '\r')

# Write the structured document using a quoted heredoc (no variable expansion)
# then substitute values with sed for safety
cat > "$OUTPUT_FILE" << 'ENDSIGNAL'
# Signal: __SIGNAL_TITLE__
**ID:** SIG-__SIGNAL_NUM__
**Type:** __SIGNAL_TYPE__
**Source:** [GitHub Issue #__SIGNAL_NUM__](__SIGNAL_URL__)
**Date:** __SIGNAL_DATE__
**Reporter:** @__SIGNAL_AUTHOR__

## Raw Content

__SIGNAL_BODY__

## Classification

- **Priority:** _To be determined during discovery_
- **Affected Area:** _To be determined during discovery_
- **Pipeline Status:** Ingested — awaiting discovery phase
ENDSIGNAL

# Substitute placeholders safely (using | as delimiter to avoid path conflicts)
sedi "s|__SIGNAL_TITLE__|${SAFE_TITLE}|g" "$OUTPUT_FILE"
sedi "s|__SIGNAL_NUM__|${ISSUE_NUMBER}|g" "$OUTPUT_FILE"
sedi "s|__SIGNAL_TYPE__|${TYPE_LABEL}|g" "$OUTPUT_FILE"
sedi "s|__SIGNAL_URL__|https://github.com/${REPO_NAME}/issues/${ISSUE_NUMBER}|g" "$OUTPUT_FILE"
sedi "s|__SIGNAL_DATE__|${FORMATTED_DATE}|g" "$OUTPUT_FILE"
sedi "s|__SIGNAL_AUTHOR__|${ISSUE_AUTHOR}|g" "$OUTPUT_FILE"

# Body replacement needs special handling (multiline)
# Write body to temp file, then use sed to replace placeholder
BODY_TEMP=$(mktemp)
trap 'rm -f "$BODY_TEMP"' EXIT
printf '%s' "$SAFE_BODY" > "$BODY_TEMP"
sedi "/__SIGNAL_BODY__/{
  r $BODY_TEMP
  d
}" "$OUTPUT_FILE"

echo "Created ${OUTPUT_FILE}"
