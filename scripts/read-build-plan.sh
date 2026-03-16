#!/usr/bin/env bash
# read-build-plan.sh — Reads a structured build plan and manages task execution order.
#
# Usage:
#   ./read-build-plan.sh next                    # Print next available task ID
#   ./read-build-plan.sh next-batch [N]          # Print up to N available task IDs (default: 3)
#   ./read-build-plan.sh find <task-id>          # Print file path for a task
#   ./read-build-plan.sh check-deps <task-id>    # Verify dependencies are satisfied
#   ./read-build-plan.sh list                    # List all tasks with status
#   ./read-build-plan.sh status <task-id> <done> # Mark task as complete
#
# Reads pipeline.yaml for build_plan_dir and workstream_dir paths.

set -euo pipefail

# Cross-platform sed -i (macOS requires '' argument, GNU does not)
sedi() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

COMMAND="${1:-help}"
TASK_ID="${2:-}"
STATUS_VALUE="${3:-}"

# Read config from pipeline.yaml
if [ -f pipeline.yaml ]; then
  BUILD_PLAN_DIR=$(grep -A5 'execution:' pipeline.yaml | grep 'build_plan_dir:' | awk '{print $2}' | tr -d '"' || echo "./build-plan")
  WORKSTREAM_DIR=$(grep -A5 'execution:' pipeline.yaml | grep 'workstream_dir:' | awk '{print $2}' | tr -d '"' || echo "./build-plan/workstreams")
else
  BUILD_PLAN_DIR="./build-plan"
  WORKSTREAM_DIR="./build-plan/workstreams"
fi

# Status tracking file (persists task completion state)
# In CI: look for the committed status file first, fall back to build plan root
if [ -f "${BUILD_PLAN_DIR}/.pipeline-status.json" ]; then
  STATUS_FILE="${BUILD_PLAN_DIR}/.pipeline-status.json"
else
  STATUS_FILE=".pipeline-status.json"
fi

# Initialize status file if it doesn't exist
if [ ! -f "$STATUS_FILE" ]; then
  echo '{}' > "$STATUS_FILE"
fi

# ──────────────────────────────────────────────
# find: Locate a task file by its ID
# ──────────────────────────────────────────────
find_task() {
  local task_id="$1"
  # Search for task file matching the ID pattern
  # Task files follow patterns like: WS0-BB1-T1-*.md, or contain the ID in their content
  local found=""

  # First, try filename match
  found=$(find "$WORKSTREAM_DIR" -name "*${task_id}*" -name "*.md" -type f 2>/dev/null | head -1)

  if [ -z "$found" ]; then
    # Try searching inside task files for the ID
    found=$(grep -rl "^.*${task_id}" "$WORKSTREAM_DIR" --include="*.md" 2>/dev/null | head -1)
  fi

  if [ -n "$found" ]; then
    echo "$found"
  else
    echo ""
    return 1
  fi
}

# ──────────────────────────────────────────────
# get_dependencies: Extract dependency list from a task file
# ──────────────────────────────────────────────
get_dependencies() {
  local task_file="$1"
  # Parse the YAML depends_on: field from the frontmatter.
  # Handles both inline (depends_on: []) and multi-line YAML lists:
  #   depends_on:
  #     - WS0-BB1-T1
  #     - WS1-BB1-T1
  # Only reads from the YAML frontmatter (between --- delimiters) to avoid
  # false matches from prose text that mentions task IDs.
  awk '
    /^---$/ { fm++; next }
    fm == 1 && /^depends_on:/ {
      # Check for inline task IDs on the same line (e.g., depends_on: [WS0-BB1-T1])
      if ($0 ~ /WS[0-9]+-BB[0-9]+-T[0-9]+/) { print; }
      in_deps = 1; next
    }
    fm == 1 && in_deps && /^[[:space:]]+-[[:space:]]/ { print; next }
    fm == 1 && in_deps { in_deps = 0 }
    fm >= 2 { exit }
  ' "$task_file" | grep -oE 'WS[0-9]+-BB[0-9]+-T[0-9]+' 2>/dev/null | sort -u || true
}

# ──────────────────────────────────────────────
# is_complete: Check if a task has been marked done
# ──────────────────────────────────────────────
is_complete() {
  local task_id="$1"
  if command -v jq &>/dev/null; then
    local status
    status=$(jq -r ".\"${task_id}\" // \"pending\"" "$STATUS_FILE")
    [ "$status" = "done" ]
  else
    grep -q "\"${task_id}\": \"done\"" "$STATUS_FILE" 2>/dev/null
  fi
}

# ──────────────────────────────────────────────
# check_deps: Verify all dependencies of a task are complete
# ──────────────────────────────────────────────
check_deps() {
  local task_id="$1"
  local task_file
  task_file=$(find_task "$task_id")

  if [ -z "$task_file" ]; then
    echo "ERROR: Task $task_id not found"
    exit 1
  fi

  local deps
  deps=$(get_dependencies "$task_file")

  # Filter out self-references
  deps=$(echo "$deps" | grep -v "^${task_id}$" || true)

  if [ -z "$deps" ]; then
    echo "OK: $task_id has no dependencies"
    exit 0
  fi

  local blocked=0
  while IFS= read -r dep; do
    [ -z "$dep" ] && continue
    if is_complete "$dep"; then
      echo "  OK: $dep is complete"
    else
      echo "  BLOCKED: $dep is not yet complete"
      blocked=1
    fi
  done <<< "$deps"

  if [ "$blocked" -eq 1 ]; then
    echo "ERROR: $task_id has unmet dependencies"
    exit 1
  else
    echo "OK: All dependencies for $task_id are satisfied"
    exit 0
  fi
}

# ──────────────────────────────────────────────
# find_ready_tasks: Collect all tasks whose deps are satisfied
# Returns one task ID per line. Internal helper used by next and next-batch.
# ──────────────────────────────────────────────
find_ready_tasks() {
  local all_tasks
  all_tasks=$(find "$WORKSTREAM_DIR" -path "*/tasks/*.md" -type f 2>/dev/null | sort)

  [ -z "$all_tasks" ] && return 0

  while IFS= read -r task_file; do
    local basename
    basename=$(basename "$task_file" .md)
    local task_id
    task_id=$(echo "$basename" | grep -oE 'WS[0-9]+-BB[0-9]+-T[0-9]+' || echo "")

    [ -z "$task_id" ] && continue

    # Skip if already done
    if is_complete "$task_id"; then
      continue
    fi

    # Check if all dependencies are met
    local deps
    deps=$(get_dependencies "$task_file")
    deps=$(echo "$deps" | grep -v "^${task_id}$" || true)

    local all_deps_met=true
    while IFS= read -r dep; do
      [ -z "$dep" ] && continue
      if ! is_complete "$dep"; then
        all_deps_met=false
        break
      fi
    done <<< "$deps"

    if [ "$all_deps_met" = true ]; then
      echo "$task_id"
    fi
  done <<< "$all_tasks"
}

# ──────────────────────────────────────────────
# next: Find the next available task to execute
# ──────────────────────────────────────────────
find_next() {
  local ready
  ready=$(find_ready_tasks)

  if [ -n "$ready" ]; then
    echo "$ready" | head -1
    return 0
  fi

  # Check if there are any pending tasks at all
  local pending
  pending=$(find "$WORKSTREAM_DIR" -path "*/tasks/*.md" -type f 2>/dev/null | while IFS= read -r f; do
    local tid
    tid=$(basename "$f" .md | grep -oE 'WS[0-9]+-BB[0-9]+-T[0-9]+' || echo "")
    [ -z "$tid" ] && continue
    is_complete "$tid" || echo "$tid"
  done)

  if [ -z "$pending" ]; then
    echo "NO_TASKS"
  else
    local count
    count=$(echo "$pending" | wc -l | tr -d ' ')
    echo "ALL_BLOCKED" >&2
    echo "WARNING: $count task(s) remain but all are blocked by unmet dependencies." >&2
    echo "This may indicate a circular dependency. Check task files for dependency loops." >&2
    echo "ALL_BLOCKED"
  fi
}

# ──────────────────────────────────────────────
# next-batch: Find up to N available tasks to execute in parallel
# ──────────────────────────────────────────────
find_next_batch() {
  local max="${1:-3}"
  local ready
  ready=$(find_ready_tasks)

  if [ -n "$ready" ]; then
    echo "$ready" | head -"$max"
    return 0
  fi

  # Same fallback logic as find_next
  local pending
  pending=$(find "$WORKSTREAM_DIR" -path "*/tasks/*.md" -type f 2>/dev/null | while IFS= read -r f; do
    local tid
    tid=$(basename "$f" .md | grep -oE 'WS[0-9]+-BB[0-9]+-T[0-9]+' || echo "")
    [ -z "$tid" ] && continue
    is_complete "$tid" || echo "$tid"
  done)

  if [ -z "$pending" ]; then
    echo "NO_TASKS"
  else
    echo "ALL_BLOCKED"
  fi
}

# ──────────────────────────────────────────────
# list: Show all tasks with their status
# ──────────────────────────────────────────────
list_tasks() {
  local all_tasks
  all_tasks=$(find "$WORKSTREAM_DIR" -path "*/tasks/*.md" -type f 2>/dev/null | sort)

  if [ -z "$all_tasks" ]; then
    echo "No task files found in $WORKSTREAM_DIR"
    return 0
  fi

  echo "TASK ID          | STATUS  | HUMAN GATE | FILE"
  echo "─────────────────|─────────|────────────|──────────────────────"

  while IFS= read -r task_file; do
    local basename
    basename=$(basename "$task_file" .md)
    local task_id
    task_id=$(echo "$basename" | grep -oE 'WS[0-9]+-BB[0-9]+-T[0-9]+' || echo "???")

    local status="pending"
    if is_complete "$task_id"; then
      status="done"
    fi

    local gate="no"
    if grep -q "^human_gate: true" "$task_file" 2>/dev/null; then
      gate="YES"
    fi

    printf "%-16s | %-7s | %-10s | %s\n" "$task_id" "$status" "$gate" "$task_file"
  done <<< "$all_tasks"
}

# ──────────────────────────────────────────────
# status: Mark a task as complete
# ──────────────────────────────────────────────
set_status() {
  local task_id="$1"
  local new_status="$2"

  # Use flock if available to prevent concurrent write corruption
  (
    if command -v flock &>/dev/null; then
      flock -w 10 200 || { echo "WARN: Could not acquire lock on status file"; }
    fi

    if command -v jq &>/dev/null; then
      local tmp
      tmp=$(jq ".\"${task_id}\" = \"${new_status}\"" "$STATUS_FILE")
      echo "$tmp" > "$STATUS_FILE"
    else
      if grep -q "\"${task_id}\"" "$STATUS_FILE"; then
        sedi "s/\"${task_id}\": \"[^\"]*\"/\"${task_id}\": \"${new_status}\"/" "$STATUS_FILE"
      else
        sedi "s/}$/,\"${task_id}\": \"${new_status}\"}/" "$STATUS_FILE"
        sedi 's/{,/{/' "$STATUS_FILE"
      fi
    fi
  ) 200>"${STATUS_FILE}.lock"

  echo "Set $task_id → $new_status"

  # Auto-commit the status change so it persists across CI runs
  if [ -n "${GITHUB_ACTIONS:-}" ] || [ "${AUTO_COMMIT_STATUS:-}" = "true" ]; then
    if command -v git &>/dev/null && git rev-parse --git-dir &>/dev/null 2>&1; then
      git config user.name "build-pipe[bot]" 2>/dev/null || true
      git config user.email "build-pipe[bot]@users.noreply.github.com" 2>/dev/null || true
      git add "$STATUS_FILE" 2>/dev/null || true
      git commit -m "pipeline: mark ${task_id} as ${new_status}" 2>/dev/null || true
      git push 2>/dev/null || echo "WARN: Could not push status update (may need manual push)"
    fi
  fi
}

# ──────────────────────────────────────────────
# Main dispatch
# ──────────────────────────────────────────────
case "$COMMAND" in
  find)
    [ -z "$TASK_ID" ] && { echo "Usage: $0 find <task-id>"; exit 1; }
    find_task "$TASK_ID"
    ;;
  check-deps)
    [ -z "$TASK_ID" ] && { echo "Usage: $0 check-deps <task-id>"; exit 1; }
    check_deps "$TASK_ID"
    ;;
  next)
    find_next
    ;;
  next-batch)
    find_next_batch "${TASK_ID:-3}"
    ;;
  list)
    list_tasks
    ;;
  status)
    [ -z "$TASK_ID" ] || [ -z "$STATUS_VALUE" ] && { echo "Usage: $0 status <task-id> <done|pending>"; exit 1; }
    set_status "$TASK_ID" "$STATUS_VALUE"
    ;;
  help|*)
    echo "read-build-plan.sh — Manage build plan task execution"
    echo ""
    echo "Commands:"
    echo "  next                    Print next available task ID"
    echo "  next-batch [N]          Print up to N available task IDs (default: 3)"
    echo "  find <task-id>          Print file path for a task"
    echo "  check-deps <task-id>   Verify dependencies are satisfied"
    echo "  list                    List all tasks with status"
    echo "  status <task-id> <val> Mark task as done or pending"
    ;;
esac
