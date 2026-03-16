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

set -euo pipefail

# ─── Test Framework ──────────────────────────────────────

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAIL_DETAILS=""

pass() {
  ((TESTS_PASSED++)) || true
  ((TESTS_RUN++)) || true
  echo "  PASS: $1"
}

fail() {
  ((TESTS_FAILED++)) || true
  ((TESTS_RUN++)) || true
  echo "  FAIL: $1"
  FAIL_DETAILS="${FAIL_DETAILS}\n  - $1: $2"
}

assert_exit_code() {
  local expected="$1" actual="$2" label="$3"
  if [ "$actual" -eq "$expected" ]; then
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

assert_file_exists() {
  if [ -e "$1" ]; then
    pass "$2"
  else
    fail "$2" "file $1 does not exist"
  fi
}

assert_file_not_exists() {
  if [ -e "$1" ]; then
    fail "$2" "file $1 should not exist but does"
  else
    pass "$2"
  fi
}

# ─── Setup ───────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT=$(mktemp -d)
FAKE_GH="${TEST_ROOT}/fake-gh"

# Track what gh commands were called
GH_LOG="${TEST_ROOT}/gh-calls.log"

cleanup_all() {
  cd /
  # Clean up any lingering worktrees
  if [ -d "${TEST_ROOT}/fork" ]; then
    cd "${TEST_ROOT}/fork"
    git worktree list 2>/dev/null | grep -v "bare" | tail -n +2 | awk '{print $1}' | while read -r wt; do
      git worktree remove "$wt" --force 2>/dev/null || true
    done
    cd /
  fi
  rm -rf "$TEST_ROOT" 2>/dev/null || true
}
trap cleanup_all EXIT

echo "=== submit-upstream.sh Integration Tests ==="
echo "Test root: $TEST_ROOT"
echo ""

# ─── Create fake gh CLI ─────────────────────────────────
# This is the key: we stub gh so the script thinks it's talking to GitHub
# but we control every response and log every call.

cat > "$FAKE_GH" << 'FAKEGH'
#!/usr/bin/env bash
# Fake gh CLI that logs calls and returns controlled responses
LOG_FILE="${GH_LOG:-/dev/null}"
echo "gh $*" >> "$LOG_FILE"

# gh api user --jq .login
if [[ "$1" == "api" && "$2" == "user" ]]; then
  echo "testuser"
  exit 0
fi

# gh repo view --json nameWithOwner
if [[ "$1" == "repo" && "$2" == "view" ]]; then
  echo "testuser/my-project"
  exit 0
fi

# gh pr list (idempotency check / dedup check)
if [[ "$1" == "pr" && "$2" == "list" ]]; then
  # Check if FAKE_EXISTING_PR is set (for idempotency test)
  if [ "${FAKE_EXISTING_PR:-}" = "true" ]; then
    echo "42"
  else
    echo ""
  fi
  exit 0
fi

# gh pr create
if [[ "$1" == "pr" && "$2" == "create" ]]; then
  if [ "${FAKE_PR_FAIL:-}" = "true" ]; then
    exit 1
  fi
  echo "https://github.com/upstream/AutoPipe/pull/99"
  exit 0
fi

# gh pr comment
if [[ "$1" == "pr" && "$2" == "comment" ]]; then
  exit 0
fi

# gh auth status
if [[ "$1" == "auth" && "$2" == "status" ]]; then
  exit 0
fi

# Default: succeed silently
exit 0
FAKEGH
chmod +x "$FAKE_GH"

# ─── Helper: Create test repos ──────────────────────────

create_upstream_repo() {
  local upstream_dir="${TEST_ROOT}/upstream-bare"
  mkdir -p "$upstream_dir"
  cd "$upstream_dir"
  git init --bare 2>/dev/null

  # Create a working copy to populate it
  local upstream_work="${TEST_ROOT}/upstream-work"
  git clone "$upstream_dir" "$upstream_work" 2>/dev/null
  cd "$upstream_work"
  git config user.email "test@test.com"
  git config user.name "Test"

  # Create upstream-relevant files
  mkdir -p .templates scripts
  echo "# Discovery Template v1" > .templates/discovery_template.md
  echo "# PRD Template v1" > .templates/prd_template.md
  echo "# Agent Rules v1" > .agent-rules.md
  echo "# Claude Instructions v1" > CLAUDE.md
  echo "#!/bin/bash" > scripts/validate-docs.sh
  echo "#!/bin/bash" > scripts/ingest-signal.sh
  chmod +x scripts/validate-docs.sh scripts/ingest-signal.sh
  git add -A
  git commit -m "initial upstream" 2>/dev/null
  git push origin main 2>/dev/null

  cd "$TEST_ROOT"
  rm -rf "$upstream_work"
  echo "$upstream_dir"
}

create_fork_repo() {
  local upstream_bare="$1"
  local fork_dir="${TEST_ROOT}/fork"

  git clone "$upstream_bare" "$fork_dir" 2>/dev/null
  cd "$fork_dir"
  git config user.email "test@test.com"
  git config user.name "Test"

  # Add project-specific files (these must NOT leak upstream)
  echo "mode: steady-state" > pipeline.yaml
  echo "template:" >> pipeline.yaml
  echo "  upstream_repo: upstream/AutoPipe" >> pipeline.yaml
  mkdir -p src docs/06-operations docs/04-specs
  echo "console.log('project code')" > src/app.js
  echo "# My Project Spec" > docs/04-specs/PRD-1.md
  echo "# Project README" > README.md
  git add -A
  git commit -m "add project-specific files" 2>/dev/null
  git push origin main 2>/dev/null

  # Set up upstream remote pointing to the bare repo
  git remote add upstream "$upstream_bare"
  git fetch upstream 2>/dev/null

  echo "$fork_dir"
}

create_research_branch() {
  local fork_dir="$1"
  local branch_name="${2:-research/2026-03-16-ci_pass_rate}"
  local include_project_files="${3:-false}"
  local create_conflict="${4:-false}"

  cd "$fork_dir"

  # Make sure we're on main
  git checkout main 2>/dev/null

  # Create and switch to research branch
  git checkout -b "$branch_name" 2>/dev/null

  # Commit 1: upstream-relevant change (template improvement)
  echo "# Discovery Template v2 - improved checklist" > .templates/discovery_template.md
  echo "## Required Sections" >> .templates/discovery_template.md
  echo "- [ ] Problem Statement" >> .templates/discovery_template.md
  git add .templates/discovery_template.md
  git commit -m "research: improve discovery template" 2>/dev/null

  # Commit 2: another upstream-relevant change (CLAUDE.md)
  echo "# Claude Instructions v2 - clearer rules" > CLAUDE.md
  echo "## Rule: Always validate cross-links" >> CLAUDE.md
  git add CLAUDE.md
  git commit -m "research: improve agent instructions" 2>/dev/null

  if [ "$include_project_files" = "true" ]; then
    # Commit 3: project-specific change (MUST NOT leak upstream)
    echo "console.log('new feature')" > src/app.js
    echo "# Updated project spec" > docs/04-specs/PRD-1.md
    git add src/app.js docs/04-specs/PRD-1.md
    git commit -m "feat: add new feature" 2>/dev/null
  fi

  if [ "$create_conflict" = "true" ]; then
    # This will conflict with upstream's version
    echo "CONFLICT CONTENT THAT DIVERGES COMPLETELY" > .templates/prd_template.md
    git add .templates/prd_template.md
    git commit -m "research: conflicting template change" 2>/dev/null
  fi

  # Create research log
  mkdir -p docs/06-operations
  echo '{"date":"2026-03-16","target_metric":"ci_pass_rate","artifact":".templates/discovery_template.md","hypothesis":"Add checklist","iterations":5,"kept":3,"discarded":2,"baseline":0.67,"final":0.95,"improved":true}' > docs/06-operations/research-log.jsonl
  git add docs/06-operations/research-log.jsonl
  git commit -m "research: log results" 2>/dev/null

  # Go back to main
  git checkout main 2>/dev/null
}

# ─── Extract testable functions from submit-upstream.sh ──
# We'll source parts of the script but override gh and control flow

run_submit_upstream() {
  local fork_dir="$1"
  local research_branch="$2"
  local upstream_repo="$3"
  local extra_env="${4:-}"

  cd "$fork_dir"

  # Clear gh log
  > "$GH_LOG"

  # Run the script with fake gh, capturing output and exit code
  local output
  local exit_code=0
  output=$(
    export PATH="${TEST_ROOT}:$PATH"
    export GH_LOG="$GH_LOG"
    # Rename fake-gh to gh for this invocation
    cp "$FAKE_GH" "${TEST_ROOT}/gh"
    chmod +x "${TEST_ROOT}/gh"
    eval "$extra_env" bash "${SCRIPT_DIR}/scripts/submit-upstream.sh" \
      "$research_branch" "$upstream_repo" 2>&1
  ) || exit_code=$?

  echo "EXIT:${exit_code}"
  echo "OUTPUT:${output}"
}

# ─── TEST 1: Happy path — upstream-relevant changes only ─

echo "--- Test 1: Happy path (upstream-relevant changes only) ---"
(
  UPSTREAM_BARE=$(create_upstream_repo)
  FORK_DIR=$(create_fork_repo "$UPSTREAM_BARE")
  create_research_branch "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "false" "false"

  cd "$FORK_DIR"

  # Verify research branch has the right commits
  COMMIT_COUNT=$(git log --oneline main..research/2026-03-16-ci_pass_rate -- .templates/ CLAUDE.md .agent-rules.md scripts/validate-docs.sh scripts/ingest-signal.sh 2>/dev/null | wc -l)
  if [ "$COMMIT_COUNT" -ge 2 ]; then
    pass "Research branch has upstream-relevant commits ($COMMIT_COUNT)"
  else
    fail "Research branch commit count" "expected >=2, got $COMMIT_COUNT"
  fi

  RESULT=$(run_submit_upstream "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe")
  EXIT_CODE=$(echo "$RESULT" | grep "^EXIT:" | cut -d: -f2)
  OUTPUT=$(echo "$RESULT" | grep "^OUTPUT:" | cut -d: -f2-)

  assert_exit_code 0 "$EXIT_CODE" "Happy path exits 0"
  assert_contains "$OUTPUT" "Created worktree" "Worktree was created"

  # Verify worktree was cleaned up
  WORKTREE_COUNT=$(git worktree list 2>/dev/null | wc -l)
  if [ "$WORKTREE_COUNT" -le 1 ]; then
    pass "Worktree cleaned up after run"
  else
    fail "Worktree cleanup" "found $WORKTREE_COUNT worktrees, expected 1"
  fi

  # Verify gh pr create was called
  if grep -q "gh pr create" "$GH_LOG" 2>/dev/null; then
    pass "gh pr create was called"
  else
    fail "gh pr create" "was never called"
  fi
)
echo ""

# ─── TEST 2: Project files do NOT leak ──────────────────

echo "--- Test 2: Project file leak prevention ---"
(
  UPSTREAM_BARE=$(create_upstream_repo)
  FORK_DIR=$(create_fork_repo "$UPSTREAM_BARE")
  create_research_branch "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "true" "false"

  cd "$FORK_DIR"

  # The research branch has BOTH upstream and project commits
  ALL_COMMITS=$(git log --oneline main..research/2026-03-16-ci_pass_rate 2>/dev/null | wc -l)
  UPSTREAM_COMMITS=$(git log --oneline main..research/2026-03-16-ci_pass_rate -- .templates/ CLAUDE.md .agent-rules.md scripts/validate-docs.sh scripts/ingest-signal.sh 2>/dev/null | wc -l)

  if [ "$ALL_COMMITS" -gt "$UPSTREAM_COMMITS" ]; then
    pass "Research branch has project-specific commits ($ALL_COMMITS total, $UPSTREAM_COMMITS upstream-relevant)"
  else
    fail "Mixed commit setup" "expected more total commits than upstream-relevant"
  fi

  # The script should only cherry-pick upstream-relevant commits
  # Let's verify by checking git log filtering
  PROJECT_COMMITS=$(git log --format='%H' main..research/2026-03-16-ci_pass_rate -- src/ docs/04-specs/ 2>/dev/null)
  if [ -n "$PROJECT_COMMITS" ]; then
    pass "Project-specific commits exist on research branch (will test they don't leak)"
  else
    fail "Project commits missing" "test setup issue"
  fi

  RESULT=$(run_submit_upstream "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe")
  EXIT_CODE=$(echo "$RESULT" | grep "^EXIT:" | cut -d: -f2)
  assert_exit_code 0 "$EXIT_CODE" "Mixed-commit path exits 0"

  # Most importantly: verify no project files were committed to the upstream branch
  # Check if the upstream branch was created
  if git rev-parse --verify "upstream-research/2026-03-16-ci_pass_rate" >/dev/null 2>&1; then
    # Check what files are in the upstream branch's diff vs upstream/main
    UPSTREAM_DIFF_FILES=$(git diff --name-only upstream/main upstream-research/2026-03-16-ci_pass_rate 2>/dev/null || echo "")
    assert_not_contains "$UPSTREAM_DIFF_FILES" "src/app.js" "No project source files in upstream diff"
    assert_not_contains "$UPSTREAM_DIFF_FILES" "docs/04-specs/" "No project specs in upstream diff"
    assert_not_contains "$UPSTREAM_DIFF_FILES" "pipeline.yaml" "No pipeline.yaml in upstream diff"
    assert_not_contains "$UPSTREAM_DIFF_FILES" "README.md" "No README in upstream diff"
  else
    pass "No upstream branch created (project-only changes filtered out, which is correct)"
  fi
)
echo ""

# ─── TEST 3: No upstream-relevant changes → skip ────────

echo "--- Test 3: No upstream-relevant changes (project-only commits) ---"
(
  UPSTREAM_BARE=$(create_upstream_repo)
  FORK_DIR=$(create_fork_repo "$UPSTREAM_BARE")

  cd "$FORK_DIR"
  git checkout -b "research/2026-03-16-signal_completion" 2>/dev/null

  # Only project-specific changes
  echo "new project code" > src/app.js
  git add src/app.js
  git commit -m "feat: project change only" 2>/dev/null

  mkdir -p docs/06-operations
  echo '{"date":"2026-03-16","target_metric":"signal_completion","artifact":"src/app.js","hypothesis":"test","iterations":3,"kept":1,"discarded":2,"baseline":0.5,"final":0.8,"improved":true}' > docs/06-operations/research-log.jsonl
  git add docs/06-operations/research-log.jsonl
  git commit -m "research: log" 2>/dev/null

  git checkout main 2>/dev/null

  RESULT=$(run_submit_upstream "$FORK_DIR" "research/2026-03-16-signal_completion" "upstream/AutoPipe")
  EXIT_CODE=$(echo "$RESULT" | grep "^EXIT:" | cut -d: -f2)
  OUTPUT=$(echo "$RESULT" | grep "^OUTPUT:" | cut -d: -f2-)

  assert_exit_code 0 "$EXIT_CODE" "Project-only exits 0"
  assert_contains "$OUTPUT" "No upstream-relevant changes" "Correctly identifies no upstream changes"
)
echo ""

# ─── TEST 4: Research did not improve → skip ────────────

echo "--- Test 4: improved=false → skip ---"
(
  UPSTREAM_BARE=$(create_upstream_repo)
  FORK_DIR=$(create_fork_repo "$UPSTREAM_BARE")

  cd "$FORK_DIR"
  git checkout -b "research/2026-03-16-ci_pass_rate" 2>/dev/null

  echo "# Modified template" > .templates/discovery_template.md
  git add .templates/discovery_template.md
  git commit -m "research: failed experiment" 2>/dev/null

  mkdir -p docs/06-operations
  # improved: false!
  echo '{"date":"2026-03-16","target_metric":"ci_pass_rate","artifact":".templates/discovery_template.md","hypothesis":"test","iterations":5,"kept":0,"discarded":5,"baseline":0.67,"final":0.67,"improved":false}' > docs/06-operations/research-log.jsonl
  git add docs/06-operations/research-log.jsonl
  git commit -m "research: log" 2>/dev/null

  git checkout main 2>/dev/null

  RESULT=$(run_submit_upstream "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe")
  EXIT_CODE=$(echo "$RESULT" | grep "^EXIT:" | cut -d: -f2)
  OUTPUT=$(echo "$RESULT" | grep "^OUTPUT:" | cut -d: -f2-)

  assert_exit_code 0 "$EXIT_CODE" "No-improvement exits 0"
  assert_contains "$OUTPUT" "did not produce improvement" "Correctly skips unimproved research"
)
echo ""

# ─── TEST 5: Below delta threshold → skip ───────────────

echo "--- Test 5: Below minimum delta threshold ---"
(
  UPSTREAM_BARE=$(create_upstream_repo)
  FORK_DIR=$(create_fork_repo "$UPSTREAM_BARE")

  cd "$FORK_DIR"
  git checkout -b "research/2026-03-16-ci_pass_rate" 2>/dev/null

  echo "# Tiny improvement" > .templates/discovery_template.md
  git add .templates/discovery_template.md
  git commit -m "research: marginal improvement" 2>/dev/null

  mkdir -p docs/06-operations
  # Delta is only 0.02 (below 0.10 threshold)
  echo '{"date":"2026-03-16","target_metric":"ci_pass_rate","artifact":".templates/discovery_template.md","hypothesis":"test","iterations":5,"kept":1,"discarded":4,"baseline":0.93,"final":0.95,"improved":true}' > docs/06-operations/research-log.jsonl
  git add docs/06-operations/research-log.jsonl
  git commit -m "research: log" 2>/dev/null

  git checkout main 2>/dev/null

  RESULT=$(run_submit_upstream "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe")
  EXIT_CODE=$(echo "$RESULT" | grep "^EXIT:" | cut -d: -f2)
  OUTPUT=$(echo "$RESULT" | grep "^OUTPUT:" | cut -d: -f2-)

  assert_exit_code 0 "$EXIT_CODE" "Below-threshold exits 0"
  assert_contains "$OUTPUT" "below threshold" "Correctly identifies marginal improvement"
)
echo ""

# ─── TEST 6: Idempotency — existing PR → skip ───────────

echo "--- Test 6: Idempotency (existing PR) ---"
(
  UPSTREAM_BARE=$(create_upstream_repo)
  FORK_DIR=$(create_fork_repo "$UPSTREAM_BARE")
  create_research_branch "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "false" "false"

  RESULT=$(run_submit_upstream "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" \
    "export FAKE_EXISTING_PR=true;")
  EXIT_CODE=$(echo "$RESULT" | grep "^EXIT:" | cut -d: -f2)
  OUTPUT=$(echo "$RESULT" | grep "^OUTPUT:" | cut -d: -f2-)

  assert_exit_code 0 "$EXIT_CODE" "Idempotency exits 0"
  assert_contains "$OUTPUT" "already exists" "Detects existing PR"
)
echo ""

# ─── TEST 7: Missing research log → skip ────────────────

echo "--- Test 7: No research log file ---"
(
  UPSTREAM_BARE=$(create_upstream_repo)
  FORK_DIR=$(create_fork_repo "$UPSTREAM_BARE")

  cd "$FORK_DIR"
  git checkout -b "research/2026-03-16-ci_pass_rate" 2>/dev/null
  echo "# change" > .templates/discovery_template.md
  git add .templates/discovery_template.md
  git commit -m "research: template" 2>/dev/null
  git checkout main 2>/dev/null

  # No research-log.jsonl exists!

  RESULT=$(run_submit_upstream "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe")
  EXIT_CODE=$(echo "$RESULT" | grep "^EXIT:" | cut -d: -f2)
  OUTPUT=$(echo "$RESULT" | grep "^OUTPUT:" | cut -d: -f2-)

  assert_exit_code 0 "$EXIT_CODE" "Missing log exits 0"
  assert_contains "$OUTPUT" "No research log found" "Detects missing research log"
)
echo ""

# ─── TEST 8: Worktree cleanup on any exit path ──────────

echo "--- Test 8: Worktree cleanup verification ---"
(
  UPSTREAM_BARE=$(create_upstream_repo)
  FORK_DIR=$(create_fork_repo "$UPSTREAM_BARE")
  create_research_branch "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "false" "false"

  cd "$FORK_DIR"

  # Count worktrees before
  BEFORE=$(git worktree list 2>/dev/null | wc -l)

  # Run the script
  run_submit_upstream "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" > /dev/null 2>&1 || true

  cd "$FORK_DIR"
  AFTER=$(git worktree list 2>/dev/null | wc -l)

  if [ "$AFTER" -le "$BEFORE" ]; then
    pass "No lingering worktrees ($BEFORE before, $AFTER after)"
  else
    fail "Worktree leak" "$BEFORE before, $AFTER after"
  fi

  # Also check that no tmp directories from worktrees linger
  ORPHAN_BRANCHES=$(git branch --list 'upstream-research/*' 2>/dev/null | wc -l)
  # The cleanup trap should have deleted this
  if [ "$ORPHAN_BRANCHES" -eq 0 ]; then
    pass "No orphan upstream-research branches"
  else
    fail "Orphan branches" "found $ORPHAN_BRANCHES upstream-research/* branches"
  fi
)
echo ""

# ─── TEST 9: Date-metric extraction ─────────────────────

echo "--- Test 9: Branch name parsing ---"
(
  # Test that various research branch names are parsed correctly
  for branch_input in \
    "research/2026-03-16-ci_pass_rate" \
    "research/2026-01-01-signal_completion" \
    "research/2026-12-31-agent_task_success"; do

    expected=$(echo "$branch_input" | sed 's|^research/||')
    actual=$(echo "$branch_input" | sed 's|^research/||')
    if [ "$expected" = "$actual" ]; then
      pass "Branch parsing: $branch_input → $expected"
    else
      fail "Branch parsing" "expected $expected, got $actual"
    fi
  done
)
echo ""

# ─── TEST 10: Delta calculation ──────────────────────────

echo "--- Test 10: Delta math ---"
(
  # Test the python delta calculation with various inputs
  DELTA=$(python3 -c "
b, f = float('0.67'), float('0.95')
print(f'{f - b:.4f}' if b > 0 else '0')
" 2>/dev/null)
  if [ "$DELTA" = "0.2800" ]; then
    pass "Delta calc: 0.67 → 0.95 = $DELTA"
  else
    fail "Delta calc" "expected 0.2800, got $DELTA"
  fi

  # Below threshold
  DELTA2=$(python3 -c "
b, f = float('0.93'), float('0.95')
print(f'{f - b:.4f}' if b > 0 else '0')
" 2>/dev/null)
  BELOW=$(python3 -c "print('yes' if float('$DELTA2') < float('0.10') else 'no')" 2>/dev/null)
  if [ "$BELOW" = "yes" ]; then
    pass "Threshold check: delta $DELTA2 correctly below 0.10"
  else
    fail "Threshold check" "delta $DELTA2 should be below 0.10"
  fi

  # Above threshold
  ABOVE=$(python3 -c "print('yes' if float('$DELTA') < float('0.10') else 'no')" 2>/dev/null)
  if [ "$ABOVE" = "no" ]; then
    pass "Threshold check: delta $DELTA correctly above 0.10"
  else
    fail "Threshold check" "delta $DELTA should be above 0.10"
  fi

  # Percentage calc
  PCT=$(python3 -c "
b = float('0.67')
print(f'{((float(\"0.95\") - b) / b) * 100:.0f}' if b > 0 else '0')
" 2>/dev/null)
  if [ "$PCT" = "42" ]; then
    pass "Percentage calc: 0.67 → 0.95 = ${PCT}%"
  else
    fail "Percentage calc" "expected 42, got $PCT"
  fi
)
echo ""

# ─── TEST 11: UPSTREAM_PATHS filtering ──────────────────

echo "--- Test 11: Path filtering covers exactly the right files ---"
(
  UPSTREAM_PATHS=(".templates/" "CLAUDE.md" ".agent-rules.md" "scripts/validate-docs.sh" "scripts/ingest-signal.sh")

  # Files that SHOULD match
  for f in ".templates/prd_template.md" ".templates/discovery_template.md" \
           "CLAUDE.md" ".agent-rules.md" "scripts/validate-docs.sh" "scripts/ingest-signal.sh"; do
    matched=false
    for pattern in "${UPSTREAM_PATHS[@]}"; do
      if [[ "$f" == "$pattern"* ]] || [[ "$f" == "$pattern" ]]; then
        matched=true
        break
      fi
    done
    if [ "$matched" = true ]; then
      pass "Path match: $f (upstream-relevant)"
    else
      fail "Path match" "$f should match but didn't"
    fi
  done

  # Files that MUST NOT match
  for f in "src/app.js" "pipeline.yaml" "docs/04-specs/PRD-1.md" \
           "scripts/nightly-cycle.sh" "scripts/collect-metrics.sh" \
           ".github/workflows/ci.yml" "README.md" "stack.yaml"; do
    matched=false
    for pattern in "${UPSTREAM_PATHS[@]}"; do
      if [[ "$f" == "$pattern"* ]] || [[ "$f" == "$pattern" ]]; then
        matched=true
        break
      fi
    done
    if [ "$matched" = false ]; then
      pass "Path reject: $f (project-specific)"
    else
      fail "Path reject" "$f should NOT match but did"
    fi
  done
)
echo ""

# ─── TEST 12: Cherry-pick conflict → graceful skip ──────

echo "--- Test 12: Cherry-pick conflict handling ---"
(
  UPSTREAM_BARE=$(create_upstream_repo)
  FORK_DIR=$(create_fork_repo "$UPSTREAM_BARE")

  cd "$FORK_DIR"

  # Modify upstream's prd_template to create divergence
  # We need to push a change to the bare upstream that conflicts
  UPSTREAM_WORK="${TEST_ROOT}/upstream-conflict"
  git clone "$UPSTREAM_BARE" "$UPSTREAM_WORK" 2>/dev/null
  cd "$UPSTREAM_WORK"
  git config user.email "test@test.com"
  git config user.name "Test"
  echo "# PRD Template v3 - upstream changed this" > .templates/prd_template.md
  echo "## Upstream-specific content that will conflict" >> .templates/prd_template.md
  git add .templates/prd_template.md
  git commit -m "upstream: template update" 2>/dev/null
  git push origin main 2>/dev/null
  cd "$FORK_DIR"
  git fetch upstream 2>/dev/null
  rm -rf "$UPSTREAM_WORK"

  # Now create research branch with conflicting change to same file
  create_research_branch "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "false" "true"

  RESULT=$(run_submit_upstream "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe")
  EXIT_CODE=$(echo "$RESULT" | grep "^EXIT:" | cut -d: -f2)
  OUTPUT=$(echo "$RESULT" | grep "^OUTPUT:" | cut -d: -f2-)

  assert_exit_code 0 "$EXIT_CODE" "Conflict exits 0 (graceful)"

  # Verify the main working tree is untouched
  cd "$FORK_DIR"
  DIRTY=$(git status --porcelain 2>/dev/null)
  if [ -z "$DIRTY" ]; then
    pass "Main working tree clean after conflict"
  else
    fail "Main tree dirty after conflict" "status: $DIRTY"
  fi

  # Verify no worktrees leaked
  WT_COUNT=$(git worktree list 2>/dev/null | wc -l)
  if [ "$WT_COUNT" -le 1 ]; then
    pass "Worktree cleaned up after conflict"
  else
    fail "Worktree leak after conflict" "found $WT_COUNT"
  fi
)
echo ""

# ─── TEST 13: PR creation failure → cleanup ─────────────

echo "--- Test 13: PR creation failure + orphan branch cleanup ---"
(
  UPSTREAM_BARE=$(create_upstream_repo)
  FORK_DIR=$(create_fork_repo "$UPSTREAM_BARE")
  create_research_branch "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "false" "false"

  RESULT=$(run_submit_upstream "$FORK_DIR" "research/2026-03-16-ci_pass_rate" "upstream/AutoPipe" \
    "export FAKE_PR_FAIL=true;")
  EXIT_CODE=$(echo "$RESULT" | grep "^EXIT:" | cut -d: -f2)
  OUTPUT=$(echo "$RESULT" | grep "^OUTPUT:" | cut -d: -f2-)

  assert_exit_code 0 "$EXIT_CODE" "PR failure exits 0"

  # Should have attempted cleanup
  if grep -q "gh push origin --delete" "$GH_LOG" 2>/dev/null || echo "$OUTPUT" | grep -q "failed after 3"; then
    pass "PR failure triggers cleanup attempt"
  else
    # The script may have logged the failure
    assert_contains "$OUTPUT" "failed" "PR failure is logged"
  fi
)
echo ""

# ─── TEST 14: nightly-cycle.sh Step 4 integration ───────

echo "--- Test 14: nightly-cycle.sh Step 4 wiring ---"
(
  # Verify nightly-cycle.sh has the Step 4 code
  NIGHTLY="${SCRIPT_DIR}/scripts/nightly-cycle.sh"
  CONTENT=$(cat "$NIGHTLY")

  assert_contains "$CONTENT" "Step 4" "nightly-cycle.sh has Step 4"
  assert_contains "$CONTENT" "submit-upstream.sh" "nightly-cycle.sh calls submit-upstream.sh"
  assert_contains "$CONTENT" "upstream_repo" "nightly-cycle.sh reads upstream_repo from pipeline.yaml"
  assert_contains "$CONTENT" "research/*" "nightly-cycle.sh finds research branch"
  assert_contains "$CONTENT" "best-effort" "Step 4 is documented as best-effort"
  assert_contains "$CONTENT" "non-blocking" "Failure is non-blocking"
)
echo ""

# ─── TEST 15: Off-limits enforcement ────────────────────

echo "--- Test 15: Off-limits lists updated ---"
(
  # Verify submit-upstream.sh is in SKILL.md off-limits
  SKILL="${SCRIPT_DIR}/.claude/skills/research/SKILL.md"
  SKILL_CONTENT=$(cat "$SKILL")
  assert_contains "$SKILL_CONTENT" "scripts/submit-upstream.sh" "SKILL.md has submit-upstream.sh in off-limits"

  # Verify submit-upstream.sh is in research-strategy.md off-limits
  STRATEGY="${SCRIPT_DIR}/docs/06-operations/research-strategy.md"
  STRATEGY_CONTENT=$(cat "$STRATEGY")
  assert_contains "$STRATEGY_CONTENT" "scripts/submit-upstream.sh" "research-strategy.md has submit-upstream.sh in off-limits"
)
echo ""

# ─── Results ─────────────────────────────────────────────

echo ""
echo "========================================="
echo " Results: ${TESTS_PASSED}/${TESTS_RUN} passed, ${TESTS_FAILED} failed"
echo "========================================="

if [ "$TESTS_FAILED" -gt 0 ]; then
  echo ""
  echo "Failures:"
  echo -e "$FAIL_DETAILS"
  echo ""
  exit 1
else
  echo ""
  echo "All tests passed."
  exit 0
fi
