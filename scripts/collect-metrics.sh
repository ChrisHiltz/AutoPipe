#!/usr/bin/env bash
# collect-metrics.sh — Pull pipeline health metrics from GitHub API via gh CLI.
# Deterministic — no AI. Appends one JSON object per run to pipeline-metrics.jsonl.
#
# Usage: ./scripts/collect-metrics.sh [period-days]
# Default period: 7 days

set -euo pipefail

PERIOD_DAYS="${1:-7}"
METRICS_FILE="pipeline-metrics.jsonl"
TIMESTAMP=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
SINCE_DATE=$(date -u -d "${PERIOD_DAYS} days ago" '+%Y-%m-%dT00:00:00Z' 2>/dev/null \
  || date -u -v-${PERIOD_DAYS}d '+%Y-%m-%dT00:00:00Z' 2>/dev/null \
  || python3 -c "from datetime import datetime, timedelta; print((datetime.utcnow() - timedelta(days=${PERIOD_DAYS})).strftime('%Y-%m-%dT00:00:00Z'))" 2>/dev/null \
  || echo "")

# ─── Helpers ────────────────────────────────────────────
safe_gh() {
  # Run gh command, return empty JSON array on failure
  "$@" 2>/dev/null || echo "[]"
}

count_json() {
  echo "$1" | jq 'length' 2>/dev/null || echo "0"
}

echo "Collecting pipeline metrics (last ${PERIOD_DAYS} days)..."

# ─── PR Metrics ─────────────────────────────────────────

# Proposal PRs (pipeline:proposal label)
PROPOSALS_ALL=$(safe_gh gh pr list --label "pipeline:proposal" --state all --limit 200 \
  --json number,state,createdAt,mergedAt,closedAt)
PROPOSALS_MERGED=$(echo "$PROPOSALS_ALL" | jq '[.[] | select(.state == "MERGED")]' 2>/dev/null || echo "[]")
PROPOSALS_CLOSED=$(echo "$PROPOSALS_ALL" | jq '[.[] | select(.state == "CLOSED" and .mergedAt == null)]' 2>/dev/null || echo "[]")

PROPOSALS_TOTAL=$(count_json "$PROPOSALS_ALL")
PROPOSALS_MERGED_COUNT=$(count_json "$PROPOSALS_MERGED")
PROPOSALS_REJECTED_COUNT=$(count_json "$PROPOSALS_CLOSED")

# Average time-to-merge for proposals (in hours)
PROPOSALS_AVG_HOURS=$(echo "$PROPOSALS_MERGED" | jq '
  [.[] | select(.mergedAt != null and .createdAt != null) |
    ((.mergedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 3600] |
  if length > 0 then (add / length * 10 | round / 10) else 0 end
' 2>/dev/null || echo "0")

# Task PRs (pipeline:task label)
TASKS_ALL=$(safe_gh gh pr list --label "pipeline:task" --state all --limit 200 \
  --json number,state,createdAt,mergedAt)
TASKS_MERGED=$(echo "$TASKS_ALL" | jq '[.[] | select(.state == "MERGED")]' 2>/dev/null || echo "[]")

TASKS_TOTAL=$(count_json "$TASKS_ALL")
TASKS_MERGED_COUNT=$(count_json "$TASKS_MERGED")

TASKS_AVG_HOURS=$(echo "$TASKS_MERGED" | jq '
  [.[] | select(.mergedAt != null and .createdAt != null) |
    ((.mergedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 3600] |
  if length > 0 then (add / length * 10 | round / 10) else 0 end
' 2>/dev/null || echo "0")

# Signal PRs (pipeline:signal label)
SIGNALS_ALL=$(safe_gh gh pr list --label "pipeline:signal" --state all --limit 200 \
  --json number,state,createdAt,mergedAt)
SIGNALS_MERGED=$(echo "$SIGNALS_ALL" | jq '[.[] | select(.state == "MERGED")]' 2>/dev/null || echo "[]")

SIGNALS_TOTAL=$(count_json "$SIGNALS_ALL")
SIGNALS_MERGED_COUNT=$(count_json "$SIGNALS_MERGED")

SIGNALS_AVG_HOURS=$(echo "$SIGNALS_MERGED" | jq '
  [.[] | select(.mergedAt != null and .createdAt != null) |
    ((.mergedAt | fromdateiso8601) - (.createdAt | fromdateiso8601)) / 3600] |
  if length > 0 then (add / length * 10 | round / 10) else 0 end
' 2>/dev/null || echo "0")

# ─── CI Metrics ─────────────────────────────────────────

CI_RUNS=$(safe_gh gh run list --workflow validate-and-test.yml --limit 100 \
  --json conclusion,createdAt)
CI_TOTAL=$(count_json "$CI_RUNS")
CI_PASSED=$(echo "$CI_RUNS" | jq '[.[] | select(.conclusion == "success")] | length' 2>/dev/null || echo "0")
CI_FAILED=$(echo "$CI_RUNS" | jq '[.[] | select(.conclusion == "failure")] | length' 2>/dev/null || echo "0")

if [ "$CI_TOTAL" -gt 0 ]; then
  CI_PASS_RATE=$(awk "BEGIN {printf \"%.3f\", $CI_PASSED / $CI_TOTAL}" 2>/dev/null || echo "0")
else
  CI_PASS_RATE="0"
fi

# ─── Issue Metrics ──────────────────────────────────────

# Signal issues (all signal:* labels)
SIGNAL_ISSUES_TOTAL=0
for LABEL in "signal:bug" "signal:feature" "signal:feedback" "signal:analytics"; do
  COUNT=$(safe_gh gh issue list --label "$LABEL" --state all --limit 500 --json number | jq 'length' 2>/dev/null || echo "0")
  SIGNAL_ISSUES_TOTAL=$((SIGNAL_ISSUES_TOTAL + COUNT))
done

# Agent tasks
AGENT_TASKS_ALL=$(safe_gh gh issue list --label "pipeline:agent-task" --state all --limit 200 \
  --json number,state,createdAt,closedAt)
AGENT_TASKS_TOTAL=$(count_json "$AGENT_TASKS_ALL")
AGENT_TASKS_CLOSED=$(echo "$AGENT_TASKS_ALL" | jq '[.[] | select(.state == "CLOSED")] | length' 2>/dev/null || echo "0")
AGENT_TASKS_OPEN=$(echo "$AGENT_TASKS_ALL" | jq '[.[] | select(.state == "OPEN")] | length' 2>/dev/null || echo "0")

# Pipeline failures
FAILURES=$(safe_gh gh issue list --label "pipeline:failure" --state all --limit 50 --json number,createdAt)
FAILURE_COUNT=$(count_json "$FAILURES")

# Reviews (changes requested vs approved)
REVIEWS_DATA=$(safe_gh gh pr list --state all --limit 50 \
  --json number,reviews)
REVIEWS_APPROVED=$(echo "$REVIEWS_DATA" | jq '
  [.[].reviews[]? | select(.state == "APPROVED")] | length
' 2>/dev/null || echo "0")
REVIEWS_CHANGES_REQUESTED=$(echo "$REVIEWS_DATA" | jq '
  [.[].reviews[]? | select(.state == "CHANGES_REQUESTED")] | length
' 2>/dev/null || echo "0")

# ─── Assemble JSON ──────────────────────────────────────

METRICS=$(jq -n \
  --arg timestamp "$TIMESTAMP" \
  --argjson period "$PERIOD_DAYS" \
  --argjson proposals_total "$PROPOSALS_TOTAL" \
  --argjson proposals_merged "$PROPOSALS_MERGED_COUNT" \
  --argjson proposals_rejected "$PROPOSALS_REJECTED_COUNT" \
  --argjson proposals_avg_hours "$PROPOSALS_AVG_HOURS" \
  --argjson ci_total "$CI_TOTAL" \
  --argjson ci_passed "$CI_PASSED" \
  --argjson ci_failed "$CI_FAILED" \
  --argjson ci_pass_rate "$CI_PASS_RATE" \
  --argjson signals_created "$SIGNAL_ISSUES_TOTAL" \
  --argjson signals_ingested "$SIGNALS_TOTAL" \
  --argjson signals_merged "$SIGNALS_MERGED_COUNT" \
  --argjson tasks_dispatched "$AGENT_TASKS_TOTAL" \
  --argjson tasks_completed "$AGENT_TASKS_CLOSED" \
  --argjson tasks_open "$AGENT_TASKS_OPEN" \
  --argjson tasks_merged "$TASKS_MERGED_COUNT" \
  --argjson tasks_avg_hours "$TASKS_AVG_HOURS" \
  --argjson failures "$FAILURE_COUNT" \
  --argjson proposals_hours "$PROPOSALS_AVG_HOURS" \
  --argjson signals_hours "$SIGNALS_AVG_HOURS" \
  --argjson reviews_approved "$REVIEWS_APPROVED" \
  --argjson reviews_changes "$REVIEWS_CHANGES_REQUESTED" \
  '{
    timestamp: $timestamp,
    period_days: $period,
    proposals: {
      total: $proposals_total,
      merged: $proposals_merged,
      rejected: $proposals_rejected,
      avg_hours_to_merge: $proposals_avg_hours
    },
    ci: {
      runs: $ci_total,
      passed: $ci_passed,
      failed: $ci_failed,
      pass_rate: $ci_pass_rate
    },
    signals: {
      created: $signals_created,
      ingested: $signals_ingested,
      completed_pipeline: $signals_merged
    },
    tasks: {
      dispatched: $tasks_dispatched,
      completed: $tasks_completed,
      open: $tasks_open,
      merged_prs: $tasks_merged,
      avg_hours_to_merge: $tasks_avg_hours
    },
    failures: $failures,
    time_to_merge: {
      proposals_hours: $proposals_hours,
      tasks_hours: $tasks_avg_hours,
      signals_hours: $signals_hours
    },
    reviews: {
      approvals: $reviews_approved,
      changes_requested: $reviews_changes
    }
  }')

# Append to metrics file
echo "$METRICS" >> "$METRICS_FILE"
echo "Metrics collected and appended to ${METRICS_FILE}"
echo "$METRICS" | jq '.'
