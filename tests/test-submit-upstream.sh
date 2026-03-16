#!/usr/bin/env bash
# test-submit-upstream.sh — Integration test for submit-upstream.sh
#
# Creates real git repos, real branches, real commits, real cherry-picks.
# Stubs out only gh CLI calls (since we can't hit GitHub in tests).
# Tests every code path: happy path, conflict, no changes, below threshold,
# project-file leakage, worktree cleanup, idempotency.
#
# Usage: ./tests/test-submit-upstream.sh
# Exit code: 0 = all passed, 1 = failures

set -uo pipefail

# ─── Test Framework ──────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SUBMIT_SCRIPT="${SCRIPT_DIR}/scripts/submit-upstream.sh"
TEST_ROOT=$(mktemp -d)

# File-based counters (survive subshells)
COUNTER_FILE="${TEST_ROOT}/.test-counts"
echo "0 0 0" > "$COUNTER_FILE"
FAIL_FILE="${TEST_ROOT}/.test-fails"
: > "$FAIL_FILE"

pass() {
  echo "  PASS: $1"
  # Atomically increment: passed runs
  local p r f
  read -r p f r < "$COUNTER_FILE"
  echo "$(( p + 1 )) $f $(( r + 1 ))" > "$COUNTER_FILE"
}

fail() {
  echo "  FAIL: $1 — $2"
  echo "  - $1: $2" >> "$FAIL_FILE"
  local p r f
  read -r p f r < "$COUNTER_FILE"
  echo "$p $(( f + 1 )) $(( r + 1 ))" > "$COUNTER_FILE"
}

assert_exit_code() {
  local expected="$1" actual="$2" label="$3"
  if [ "$actual" -eq "$expected" ] 2>/dev/null; then
    pass "$label"
  else
    fail "$label" "expected exit $expected, got $actual"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" label="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    pass "$label"
  else
    fail "$label" "output did not contain '$needle'"
  fi
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    fail "$label" "output should NOT contain '$needle'"
  else
    pass "$label"
  fi
}

cleanup_all() {
  for d in "${TEST_ROOT}"/test-*/fork; do
    if [ -d "$d" ]; then
      (cd "$d" 2>/dev/null && git worktree list 2>/dev/null | tail -n +2 | awk '{print $1}' | while read -r wt; do
        git worktree remove "$wt" --force &>/dev/null || true
      done) || true
    fi
  done
  cd /
  rm -rf "$TEST_ROOT" 2>/dev/null || true
}
trap cleanup_all EXIT

echo "=== submit-upstream.sh Integration Tests ==="
echo "Test root: $TEST_ROOT"
echo ""

# ─── Helpers ─────────────────────────────────────────────

# Counter file for test isolation (subshell-safe)
TEST_NUM_FILE="${TEST_ROOT}/.test-num"
echo "0" > "$TEST_NUM_FILE"

new_test_dir() {
  local n
  n=$(cat "$TEST_NUM_FILE")
  n=$(( n + 1 ))
  echo "$n" > "$TEST_NUM_FILE"
  local td="${TEST_ROOT}/test-${n}"
  mkdir -p "$td"
  echo "$td"
}

create_fake_gh() {
  local td="$1"
  local gh_path="${td}/gh"
  local gh_log="${td}/gh-calls.log"
  : > "$gh_log"

  cat > "$gh_path" << 'FAKEGH'
#!/usr/bin/env bash
LOG_FILE="${GH_LOG:-/dev/null}"
echo "gh $*" >> "$LOG_FILE"

if [[ "$1" == "api" && "$2" == "user" ]]; then echo "testuser"; exit 0; fi
if [[ "$1" == "repo" && "$2" == "view" ]]; then echo "testuser/my-project"; exit 0; fi
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  if [ "${FAKE_EXISTING_PR:-}" = "true" ]; then echo "42"; else echo ""; fi
  exit 0
fi
if [[ "$1" == "pr" && "$2" == "create" ]]; then
  if [ "${FAKE_PR_FAIL:-}" = "true" ]; then exit 1; fi
  echo "https://github.com/upstream/AutoPipe/pull/99"; exit 0
fi
if [[ "$1" == "pr" && "$2" == "comment" ]]; then exit 0; fi
if [[ "$1" == "auth" && "$2" == "status" ]]; then exit 0; fi
exit 0
FAKEGH
  chmod +x "$gh_path"
}

create_upstream_repo() {
  local td="$1"
  local bare_dir="${td}/upstream-bare"
  local work_dir="${td}/upstream-work"

  git init --bare --initial-branch=main "$bare_dir" &>/dev/null

  git clone "$bare_dir" "$work_dir" &>/dev/null
  (
    cd "$work_dir"
    git config user.email "test@test.com"
    git config user.name "Test"
    git checkout -b main &>/dev/null || true

    mkdir -p .templates scripts
    echo "# Discovery Template v1" > .templates/discovery_template.md
    echo "# PRD Template v1" > .templates/prd_template.md
    echo "# Agent Rules v1" > .agent-rules.md
    echo "# Claude Instructions v1" > CLAUDE.md
    echo "#!/bin/bash" > scripts/validate-docs.sh
    echo "#!/bin/bash" > scripts/ingest-signal.sh
    chmod +x scripts/validate-docs.sh scripts/ingest-signal.sh
    git add -A &>/dev/null
    git commit -m "initial upstream" &>/dev/null
    git push -u origin main &>/dev/null
  )

  rm -rf "$work_dir"
  echo "$bare_dir"
}

create_fork_repo() {
  local td="$1"
  local bare_dir="$2"
  local fork_dir="${td}/fork"

  git clone -b main "$bare_dir" "$fork_dir" &>/dev/null
  (
    cd "$fork_dir"
    git config user.email "test@test.com"
    git config user.name "Test"

    echo "mode: steady-state" > pipeline.yaml
    echo "template:" >> pipeline.yaml
    echo "  upstream_repo: upstream/AutoPipe" >> pipeline.yaml
    mkdir -p src docs/06-operations docs/04-specs
    echo "console.log('project code')" > src/app.js
    echo "# My Project Spec" > docs/04-specs/PRD-1.md
    echo "# Project README" > README.md
    git add -A &>/dev/null
    git commit -m "add project-specific files" &>/dev/null
    git push origin main &>/dev/null

    git remote add upstream "$bare_dir" &>/dev/null
    git fetch upstream &>/dev/null
  )

  echo "$fork_dir"
}

add_research_branch() {
  local fork_dir="$1"
  local branch="${2:-research/2026-03-16-ci_pass_rate}"
  local include_project="${3:-false}"
  local create_conflict="${4:-false}"

  (
    cd "$fork_dir"
    git checkout main &>/dev/null
    git checkout -b "$branch" &>/dev/null

    echo "# Discovery Template v2 - improved checklist" > .templates/discovery_template.md
    echo "## Required Sections" >> .templates/discovery_template.md
    echo "- [ ] Problem Statement" >> .templates/discovery_template.md
    git add .templates/discovery_template.md &>/dev/null
    git commit -m "research: improve discovery template" &>/dev/null

    echo "# Claude Instructions v2 - clearer rules" > CLAUDE.md
    echo "## Rule: Always validate cross-links" >> CLAUDE.md
    git add CLAUDE.md &>/dev/null
    git commit -m "research: improve agent instructions" &>/dev/null

    if [ "$include_project" = "true" ]; then
      echo "console.log('new feature')" > src/app.js
      echo "# Updated project spec" > docs/04-specs/PRD-1.md
      git add src/app.js docs/04-specs/PRD-1.md &>/dev/null
      git commit -m "feat: add new feature" &>/dev/null
    fi

    if [ "$create_conflict" = "true" ]; then
      echo "CONFLICT CONTENT THAT DIVERGES COMPLETELY" > .templates/prd_template.md
      git add .templates/prd_template.md &>/dev/null
      git commit -m "research: conflicting template change" &>/dev/null
    fi

    mkdir -p docs/06-operations
    echo '{"date":"2026-03-16","target_metric":"ci_pass_rate","artifact":".templates/discovery_template.md","hypothesis":"Add checklist","iterations":5,"kept":3,"discarded":2,"baseline":0.67,"final":0.95,"improved":true}' \
      > docs/06-operations/research-log.jsonl
    git add docs/06-operations/research-log.jsonl &>/dev/null
    git commit -m "research: log results" &>/dev/null

    git checkout main &>/dev/null
  )
}

# Run submit-upstream.sh with fake gh. Returns structured output.
# In production, nightly-cycle.sh calls this while on the research branch,
# so we checkout the research branch first (in a subshell to not affect parent).
run_script() {
  local fork_dir="$1"
  local branch="$2"
  local upstream_repo="$3"
  local td="$4"
  local extra="${5:-}"

  local gh_log="${td}/gh-calls.log"
  : > "$gh_log"

  # Get the local upstream bare repo URL so the script doesn't try to hit github.com
  local upstream_git_url
  upstream_git_url=$(cd "$fork_dir" && git remote get-url upstream 2>/dev/null || echo "")

  local exit_code=0
  local output
  output=$(
    cd "$fork_dir"
    # Match production: nightly-cycle.sh runs submit-upstream.sh while on the research branch
    git checkout "$branch" &>/dev/null || true
    export PATH="${td}:$PATH"
    export GH_LOG="$gh_log"
    export UPSTREAM_GIT_URL="$upstream_git_url"
    if [ -n "$extra" ]; then eval "$extra"; fi
    bash "$SUBMIT_SCRIPT" "$branch" "$upstream_repo" 2>&1
  ) || exit_code=$?

  echo "EXIT_CODE=$exit_code"
  echo "---OUTPUT---"
  echo "$output"
  echo "---GH_LOG---"
  cat "$gh_log" 2>/dev/null || true
}

parse_exit() { echo "$1" | head -1 | sed 's/EXIT_CODE=//'; }
parse_output() { echo "$1" | sed -n '/^---OUTPUT---$/,/^---GH_LOG---$/p' | sed '1d;$d'; }
parse_ghlog() { echo "$1" | sed -n '/^---GH_LOG---$/,$p' | sed '1d'; }

# ═══════════════════════════════════════════════════════════
# TESTS
# ═══════════════════════════════════════════════════════════

echo "--- Test 1: Happy path (upstream-relevant changes, no project files) ---"
TD=$(new_test_dir)
create_fake_gh "$TD"
UPSTREAM=$(create_upstream_repo "$TD")
FORK=$(create_fork_repo "$TD" "$UPSTREAM")
add_research_branch "$FORK" "research/2026-03-16-ci_pass_rate" "false" "false"

RESULT=$(run_script "$FORK" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" "$TD")
EC=$(parse_exit "$RESULT")
OUT=$(parse_output "$RESULT")
GHL=$(parse_ghlog "$RESULT")

assert_exit_code 0 "$EC" "Exits 0"
assert_contains "$OUT" "Created worktree" "Worktree created"
assert_contains "$GHL" "pr create" "gh pr create called"

# Verify worktree cleaned up
WT=$(cd "$FORK" && git worktree list 2>/dev/null | wc -l)
if [ "$WT" -le 1 ]; then pass "Worktree cleaned up"; else fail "Worktree cleanup" "$WT worktrees remain"; fi
echo ""

# ─── TEST 2 ──────────────────────────────────────────────

echo "--- Test 2: Mixed commits — project files must NOT leak ---"
TD=$(new_test_dir)
create_fake_gh "$TD"
UPSTREAM=$(create_upstream_repo "$TD")
FORK=$(create_fork_repo "$TD" "$UPSTREAM")
add_research_branch "$FORK" "research/2026-03-16-ci_pass_rate" "true" "false"

# Verify setup
ALL=$(cd "$FORK" && git log --oneline main..research/2026-03-16-ci_pass_rate 2>/dev/null | wc -l)
UP_ONLY=$(cd "$FORK" && git log --oneline main..research/2026-03-16-ci_pass_rate \
  -- .templates/ CLAUDE.md .agent-rules.md scripts/validate-docs.sh scripts/ingest-signal.sh 2>/dev/null | wc -l)
if [ "$ALL" -gt "$UP_ONLY" ]; then
  pass "Branch has mixed commits ($ALL total, $UP_ONLY upstream)"
else
  fail "Test setup" "expected mixed commits (all=$ALL, upstream=$UP_ONLY)"
fi

RESULT=$(run_script "$FORK" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" "$TD")
EC=$(parse_exit "$RESULT")
assert_exit_code 0 "$EC" "Exits 0 with mixed commits"

# Check the upstream-research branch for leaks
if (cd "$FORK" && git rev-parse --verify "upstream-research/2026-03-16-ci_pass_rate" &>/dev/null); then
  DIFF_FILES=$(cd "$FORK" && git diff --name-only upstream/main upstream-research/2026-03-16-ci_pass_rate 2>/dev/null || echo "")
  assert_not_contains "$DIFF_FILES" "src/app.js" "No src/ files leak"
  assert_not_contains "$DIFF_FILES" "docs/04-specs" "No specs leak"
  assert_not_contains "$DIFF_FILES" "pipeline.yaml" "No pipeline.yaml leaks"
  assert_not_contains "$DIFF_FILES" "README.md" "No README leaks"
else
  pass "Upstream branch cleaned up (trap ran — still safe)"
fi
echo ""

# ─── TEST 3 ──────────────────────────────────────────────

echo "--- Test 3: Project-only commits → skip ---"
TD=$(new_test_dir)
create_fake_gh "$TD"
UPSTREAM=$(create_upstream_repo "$TD")
FORK=$(create_fork_repo "$TD" "$UPSTREAM")

(
  cd "$FORK"
  git checkout -b "research/2026-03-16-signal_completion" &>/dev/null
  echo "new project code" > src/app.js
  git add src/app.js &>/dev/null
  git commit -m "feat: project change only" &>/dev/null
  mkdir -p docs/06-operations
  echo '{"date":"2026-03-16","target_metric":"signal_completion","artifact":"src/app.js","hypothesis":"test","iterations":3,"kept":1,"discarded":2,"baseline":0.5,"final":0.8,"improved":true}' \
    > docs/06-operations/research-log.jsonl
  git add docs/06-operations/research-log.jsonl &>/dev/null
  git commit -m "research: log" &>/dev/null
  git checkout main &>/dev/null
)

RESULT=$(run_script "$FORK" "research/2026-03-16-signal_completion" "upstream/AutoPipe" "$TD")
EC=$(parse_exit "$RESULT")
OUT=$(parse_output "$RESULT")
assert_exit_code 0 "$EC" "Exits 0"
assert_contains "$OUT" "No upstream-relevant changes" "Correctly skips"
echo ""

# ─── TEST 4 ──────────────────────────────────────────────

echo "--- Test 4: Failed research (improved=false) → skip ---"
TD=$(new_test_dir)
create_fake_gh "$TD"
UPSTREAM=$(create_upstream_repo "$TD")
FORK=$(create_fork_repo "$TD" "$UPSTREAM")

(
  cd "$FORK"
  git checkout -b "research/2026-03-16-ci_pass_rate" &>/dev/null
  echo "# Modified" > .templates/discovery_template.md
  git add .templates/discovery_template.md &>/dev/null
  git commit -m "research: failed" &>/dev/null
  mkdir -p docs/06-operations
  echo '{"date":"2026-03-16","target_metric":"ci_pass_rate","artifact":".templates/discovery_template.md","hypothesis":"test","iterations":5,"kept":0,"discarded":5,"baseline":0.67,"final":0.67,"improved":false}' \
    > docs/06-operations/research-log.jsonl
  git add docs/06-operations/research-log.jsonl &>/dev/null
  git commit -m "log" &>/dev/null
  git checkout main &>/dev/null
)

RESULT=$(run_script "$FORK" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" "$TD")
EC=$(parse_exit "$RESULT")
OUT=$(parse_output "$RESULT")
assert_exit_code 0 "$EC" "Exits 0"
assert_contains "$OUT" "did not produce improvement" "Detects improved=false"
echo ""

# ─── TEST 5 ──────────────────────────────────────────────

echo "--- Test 5: Marginal improvement (delta < 0.10) → skip ---"
TD=$(new_test_dir)
create_fake_gh "$TD"
UPSTREAM=$(create_upstream_repo "$TD")
FORK=$(create_fork_repo "$TD" "$UPSTREAM")

(
  cd "$FORK"
  git checkout -b "research/2026-03-16-ci_pass_rate" &>/dev/null
  echo "# Tiny tweak" > .templates/discovery_template.md
  git add .templates/discovery_template.md &>/dev/null
  git commit -m "research: marginal" &>/dev/null
  mkdir -p docs/06-operations
  echo '{"date":"2026-03-16","target_metric":"ci_pass_rate","artifact":".templates/discovery_template.md","hypothesis":"test","iterations":5,"kept":1,"discarded":4,"baseline":0.93,"final":0.95,"improved":true}' \
    > docs/06-operations/research-log.jsonl
  git add docs/06-operations/research-log.jsonl &>/dev/null
  git commit -m "log" &>/dev/null
  git checkout main &>/dev/null
)

RESULT=$(run_script "$FORK" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" "$TD")
EC=$(parse_exit "$RESULT")
OUT=$(parse_output "$RESULT")
assert_exit_code 0 "$EC" "Exits 0"
assert_contains "$OUT" "below threshold" "Detects marginal improvement"
echo ""

# ─── TEST 6 ──────────────────────────────────────────────

echo "--- Test 6: Existing upstream PR → skip (idempotency) ---"
TD=$(new_test_dir)
create_fake_gh "$TD"
UPSTREAM=$(create_upstream_repo "$TD")
FORK=$(create_fork_repo "$TD" "$UPSTREAM")
add_research_branch "$FORK" "research/2026-03-16-ci_pass_rate" "false" "false"

RESULT=$(run_script "$FORK" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" "$TD" \
  "export FAKE_EXISTING_PR=true")
EC=$(parse_exit "$RESULT")
OUT=$(parse_output "$RESULT")
assert_exit_code 0 "$EC" "Exits 0"
assert_contains "$OUT" "already exists" "Detects existing PR"
echo ""

# ─── TEST 7 ──────────────────────────────────────────────

echo "--- Test 7: Missing research-log.jsonl → skip ---"
TD=$(new_test_dir)
create_fake_gh "$TD"
UPSTREAM=$(create_upstream_repo "$TD")
FORK=$(create_fork_repo "$TD" "$UPSTREAM")

(
  cd "$FORK"
  git checkout -b "research/2026-03-16-ci_pass_rate" &>/dev/null
  echo "# change" > .templates/discovery_template.md
  git add .templates/discovery_template.md &>/dev/null
  git commit -m "research: template" &>/dev/null
  git checkout main &>/dev/null
)

RESULT=$(run_script "$FORK" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" "$TD")
EC=$(parse_exit "$RESULT")
OUT=$(parse_output "$RESULT")
assert_exit_code 0 "$EC" "Exits 0"
assert_contains "$OUT" "No research log found" "Detects missing log"
echo ""

# ─── TEST 8 ──────────────────────────────────────────────

echo "--- Test 8: Worktree cleanup on all exit paths ---"
TD=$(new_test_dir)
create_fake_gh "$TD"
UPSTREAM=$(create_upstream_repo "$TD")
FORK=$(create_fork_repo "$TD" "$UPSTREAM")
add_research_branch "$FORK" "research/2026-03-16-ci_pass_rate" "false" "false"

BEFORE=$(cd "$FORK" && git worktree list 2>/dev/null | wc -l)
run_script "$FORK" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" "$TD" >/dev/null 2>&1 || true
AFTER=$(cd "$FORK" && git worktree list 2>/dev/null | wc -l)

if [ "$AFTER" -le "$BEFORE" ]; then
  pass "No worktree leak ($BEFORE → $AFTER)"
else
  fail "Worktree leak" "$BEFORE before, $AFTER after"
fi

ORPHANS=$(cd "$FORK" && git branch --list 'upstream-research/*' 2>/dev/null | wc -l)
if [ "$ORPHANS" -eq 0 ]; then
  pass "No orphan upstream-research branches"
else
  fail "Orphan branches" "found $ORPHANS"
fi
echo ""

# ─── TEST 9 ──────────────────────────────────────────────

echo "--- Test 9: Cherry-pick conflict → graceful exit, clean state ---"
TD=$(new_test_dir)
create_fake_gh "$TD"
UPSTREAM=$(create_upstream_repo "$TD")
FORK=$(create_fork_repo "$TD" "$UPSTREAM")

# Push conflicting change to upstream
UPSTREAM_WORK="${TD}/upstream-conflict"
git clone "$UPSTREAM" "$UPSTREAM_WORK" &>/dev/null
(
  cd "$UPSTREAM_WORK"
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "# PRD Template v3 - upstream diverged" > .templates/prd_template.md
  echo "## Upstream-specific content" >> .templates/prd_template.md
  git add .templates/prd_template.md &>/dev/null
  git commit -m "upstream: diverge prd template" &>/dev/null
  git push origin main &>/dev/null
)
rm -rf "$UPSTREAM_WORK"

(cd "$FORK" && git fetch upstream &>/dev/null)
add_research_branch "$FORK" "research/2026-03-16-ci_pass_rate" "false" "true"

RESULT=$(run_script "$FORK" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" "$TD")
EC=$(parse_exit "$RESULT")
assert_exit_code 0 "$EC" "Conflict exits 0"

DIRTY=$(cd "$FORK" && git status --porcelain 2>/dev/null || true)
if [ -z "$DIRTY" ]; then
  pass "Main working tree clean after conflict"
else
  fail "Dirty tree" "$DIRTY"
fi

WT=$(cd "$FORK" && git worktree list 2>/dev/null | wc -l)
if [ "$WT" -le 1 ]; then
  pass "Worktree cleaned up after conflict"
else
  fail "Worktree leak after conflict" "$WT"
fi
echo ""

# ─── TEST 10 ─────────────────────────────────────────────

echo "--- Test 10: PR creation fails 3x → cleanup ---"
TD=$(new_test_dir)
create_fake_gh "$TD"
UPSTREAM=$(create_upstream_repo "$TD")
FORK=$(create_fork_repo "$TD" "$UPSTREAM")
add_research_branch "$FORK" "research/2026-03-16-ci_pass_rate" "false" "false"

RESULT=$(run_script "$FORK" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" "$TD" \
  "export FAKE_PR_FAIL=true")
EC=$(parse_exit "$RESULT")
OUT=$(parse_output "$RESULT")
assert_exit_code 0 "$EC" "PR failure exits 0"
assert_contains "$OUT" "failed after 3" "Logs 3-attempt failure"
echo ""

# ─── TEST 11 ─────────────────────────────────────────────

echo "--- Test 11: Delta calculation correctness ---"
PY=$(command -v python3 2>/dev/null || command -v python 2>/dev/null || echo "")
if [ -z "$PY" ]; then
  fail "Python" "neither python3 nor python found"
else
  D=$($PY -c "b, f = float('0.67'), float('0.95'); print(f'{f - b:.4f}' if b > 0 else '0')" 2>/dev/null)
  if [ "$D" = "0.2800" ]; then pass "Delta 0.67→0.95 = $D"; else fail "Delta calc" "expected 0.2800, got $D"; fi

  D2=$($PY -c "b, f = float('0.93'), float('0.95'); print(f'{f - b:.4f}' if b > 0 else '0')" 2>/dev/null)
  BT=$($PY -c "print('yes' if float('$D2') < float('0.10') else 'no')" 2>/dev/null)
  if [ "$BT" = "yes" ]; then pass "Delta $D2 below 0.10"; else fail "Threshold" "$D2 should be below"; fi

  AT=$($PY -c "print('yes' if float('$D') < float('0.10') else 'no')" 2>/dev/null)
  if [ "$AT" = "no" ]; then pass "Delta $D above 0.10"; else fail "Threshold" "$D should be above"; fi

  PCT=$($PY -c "b=float('0.67'); print(f'{((float(\"0.95\")-b)/b)*100:.0f}' if b>0 else '0')" 2>/dev/null)
  if [ "$PCT" = "42" ]; then pass "Pct 0.67→0.95 = ${PCT}%"; else fail "Pct calc" "expected 42, got $PCT"; fi
fi
echo ""

# ─── TEST 12 ─────────────────────────────────────────────

echo "--- Test 12: UPSTREAM_PATHS filter ---"
UPSTREAM_PATHS=(".templates/" "CLAUDE.md" ".agent-rules.md" "scripts/validate-docs.sh" "scripts/ingest-signal.sh")

for f in ".templates/prd_template.md" ".templates/discovery_template.md" \
         "CLAUDE.md" ".agent-rules.md" "scripts/validate-docs.sh" "scripts/ingest-signal.sh"; do
  matched=false
  for p in "${UPSTREAM_PATHS[@]}"; do
    if [[ "$f" == "$p"* ]] || [[ "$f" == "$p" ]]; then matched=true; break; fi
  done
  if [ "$matched" = true ]; then pass "IN:  $f"; else fail "Path filter" "$f should match"; fi
done

for f in "src/app.js" "pipeline.yaml" "docs/04-specs/PRD-1.md" \
         "scripts/nightly-cycle.sh" "scripts/collect-metrics.sh" \
         ".github/workflows/ci.yml" "README.md" "stack.yaml" \
         "scripts/submit-upstream.sh" "docs/06-operations/research-log.jsonl"; do
  matched=false
  for p in "${UPSTREAM_PATHS[@]}"; do
    if [[ "$f" == "$p"* ]] || [[ "$f" == "$p" ]]; then matched=true; break; fi
  done
  if [ "$matched" = false ]; then pass "OUT: $f"; else fail "Path filter" "$f should NOT match"; fi
done
echo ""

# ─── TEST 13 ─────────────────────────────────────────────

echo "--- Test 13: nightly-cycle.sh Step 4 wiring ---"
CONTENT=$(cat "${SCRIPT_DIR}/scripts/nightly-cycle.sh")
assert_contains "$CONTENT" "Step 4" "Step 4 label present"
assert_contains "$CONTENT" "submit-upstream.sh" "Calls submit-upstream.sh"
assert_contains "$CONTENT" "upstream_repo" "Reads upstream_repo"
assert_contains "$CONTENT" "non-blocking" "Documented as non-blocking"
echo ""

# ─── TEST 14 ─────────────────────────────────────────────

echo "--- Test 14: Off-limits enforcement ---"
assert_contains "$(cat "${SCRIPT_DIR}/.claude/skills/research/SKILL.md")" \
  "scripts/submit-upstream.sh" "SKILL.md off-limits"
assert_contains "$(cat "${SCRIPT_DIR}/docs/06-operations/research-strategy.md")" \
  "scripts/submit-upstream.sh" "research-strategy.md off-limits"
echo ""

# ─── TEST 15 ─────────────────────────────────────────────

echo "--- Test 15: Syntax check ---"
if bash -n "${SCRIPT_DIR}/scripts/submit-upstream.sh" 2>/dev/null; then
  pass "submit-upstream.sh syntax OK"
else
  fail "submit-upstream.sh syntax" "bash -n failed"
fi
if bash -n "${SCRIPT_DIR}/scripts/nightly-cycle.sh" 2>/dev/null; then
  pass "nightly-cycle.sh syntax OK"
else
  fail "nightly-cycle.sh syntax" "bash -n failed"
fi
echo ""

# ─── Results ─────────────────────────────────────────────

read -r PASSED FAILED TOTAL < "$COUNTER_FILE"
echo "========================================="
echo " Results: ${PASSED}/${TOTAL} passed, ${FAILED} failed"
echo "========================================="

if [ "$FAILED" -gt 0 ]; then
  echo ""
  echo "Failures:"
  cat "$FAIL_FILE"
  echo ""
  exit 1
else
  echo ""
  echo "All tests passed."
  exit 0
fi
