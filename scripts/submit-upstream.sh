#!/usr/bin/env bash
# submit-upstream.sh — Submit research improvements to the upstream template repo.
# Best-effort: failures are logged but never break the local workflow.
# Called by nightly-cycle.sh after the research agent finishes.
#
# Uses git worktree isolation so the main working tree is NEVER touched.
#
# Usage: ./scripts/submit-upstream.sh <research-branch> <upstream-repo>
# Example: ./scripts/submit-upstream.sh research/2026-03-15-ci_pass_rate org/AutoPipe

set -euo pipefail

RESEARCH_BRANCH="${1:?Usage: submit-upstream.sh <research-branch> <upstream-repo>}"
UPSTREAM_REPO="${2:?Usage: submit-upstream.sh <research-branch> <upstream-repo>}"

# Files that are relevant to the upstream template (everything else is project-specific)
UPSTREAM_PATHS=(".templates/" "CLAUDE.md" ".agent-rules.md" "scripts/validate-docs.sh" "scripts/ingest-signal.sh")

WORKTREE_DIR=""

# ─── Helpers ────────────────────────────────────────────
log() { echo "[submit-upstream] $1"; }

cleanup() {
  if [ -n "$WORKTREE_DIR" ] && [ -d "$WORKTREE_DIR" ]; then
    git worktree remove "$WORKTREE_DIR" --force 2>/dev/null || true
    rm -rf "$WORKTREE_DIR" 2>/dev/null || true
  fi
  # Clean up the local upstream branch if it exists
  local branch_name
  branch_name="upstream-research/${DATE_METRIC:-cleanup}"
  git branch -D "$branch_name" 2>/dev/null || true
}
trap cleanup EXIT

# ─── Preflight ──────────────────────────────────────────

# Derive fork owner from gh auth
FORK_OWNER=$(gh api user --jq .login 2>/dev/null || echo "")
if [ -z "$FORK_OWNER" ]; then
  log "Cannot determine fork owner from gh auth. Skipping."
  exit 0
fi

FORK_REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")

# Extract date-metric suffix for branch naming
DATE_METRIC=$(echo "$RESEARCH_BRANCH" | sed 's|^research/||')
UPSTREAM_BRANCH="upstream-research/${DATE_METRIC}"

# Check for existing upstream PR (idempotency)
EXISTING_PR=$(gh pr list --repo "$UPSTREAM_REPO" \
  --head "${FORK_OWNER}:${UPSTREAM_BRANCH}" \
  --json number --jq '.[0].number' 2>/dev/null || echo "")
if [ -n "$EXISTING_PR" ]; then
  log "Upstream PR #${EXISTING_PR} already exists. Skipping."
  exit 0
fi

# Get research commits that touch upstream-relevant files only
RESEARCH_COMMITS=$(git log --format='%H' "main..${RESEARCH_BRANCH}" --reverse \
  -- "${UPSTREAM_PATHS[@]}" 2>/dev/null || echo "")
if [ -z "$RESEARCH_COMMITS" ]; then
  log "No upstream-relevant changes in research branch. Skipping."
  exit 0
fi

# Read the last research log entry for metadata
LOG_FILE="docs/06-operations/research-log.jsonl"
if [ -f "$LOG_FILE" ]; then
  LAST_LOG=$(tail -1 "$LOG_FILE" 2>/dev/null || echo "{}")
  TARGET_METRIC=$(echo "$LAST_LOG" | jq -r '.target_metric // "unknown"' 2>/dev/null || echo "unknown")
  ARTIFACT=$(echo "$LAST_LOG" | jq -r '.artifact // "unknown"' 2>/dev/null || echo "unknown")
  BASELINE=$(echo "$LAST_LOG" | jq -r '.baseline // 0' 2>/dev/null || echo "0")
  FINAL=$(echo "$LAST_LOG" | jq -r '.final // 0' 2>/dev/null || echo "0")
  ITERATIONS=$(echo "$LAST_LOG" | jq -r '.iterations // 0' 2>/dev/null || echo "0")
  KEPT=$(echo "$LAST_LOG" | jq -r '.kept // 0' 2>/dev/null || echo "0")
  DISCARDED=$(echo "$LAST_LOG" | jq -r '.discarded // 0' 2>/dev/null || echo "0")
  IMPROVED=$(echo "$LAST_LOG" | jq -r '.improved // false' 2>/dev/null || echo "false")
else
  log "No research log found. Skipping."
  exit 0
fi

# Only submit if the research actually improved something
if [ "$IMPROVED" != "true" ]; then
  log "Research did not produce improvement. Skipping upstream submission."
  exit 0
fi

# Minimum delta threshold (skip marginal improvements)
DELTA=$(python3 -c "
b, f = float('$BASELINE'), float('$FINAL')
print(f'{f - b:.4f}' if b > 0 else '0')
" 2>/dev/null || echo "0")

MIN_DELTA="0.10"
BELOW_THRESHOLD=$(python3 -c "print('yes' if float('$DELTA') < float('$MIN_DELTA') else 'no')" 2>/dev/null || echo "no")
if [ "$BELOW_THRESHOLD" = "yes" ]; then
  log "Improvement delta ($DELTA) below threshold ($MIN_DELTA). Skipping."
  exit 0
fi

# ─── Ensure upstream remote ─────────────────────────────

UPSTREAM_URL="https://github.com/${UPSTREAM_REPO}.git"
EXISTING_URL=$(git remote get-url upstream 2>/dev/null || echo "")
if [ -z "$EXISTING_URL" ]; then
  git remote add upstream "$UPSTREAM_URL"
elif [ "$EXISTING_URL" != "$UPSTREAM_URL" ]; then
  git remote set-url upstream "$UPSTREAM_URL"
fi

if ! git fetch upstream main 2>/dev/null; then
  log "Cannot fetch upstream main. Skipping."
  exit 0
fi

# ─── Create isolated worktree ───────────────────────────

WORKTREE_DIR=$(mktemp -d)
if ! git worktree add "$WORKTREE_DIR" -b "$UPSTREAM_BRANCH" upstream/main 2>/dev/null; then
  log "Cannot create worktree. Skipping."
  exit 0
fi

log "Created worktree at $WORKTREE_DIR"

# ─── Cherry-pick in worktree ────────────────────────────

CHERRY_PICK_FAILED=false
pushd "$WORKTREE_DIR" > /dev/null

for commit in $RESEARCH_COMMITS; do
  if ! git cherry-pick "$commit" --no-commit 2>/dev/null; then
    log "Cherry-pick conflict on $(git log --oneline -1 "$commit" 2>/dev/null || echo "$commit"). Skipping upstream submission."
    git cherry-pick --abort 2>/dev/null || true
    git checkout -- . 2>/dev/null || true
    CHERRY_PICK_FAILED=true
    break
  fi
done

if [ "$CHERRY_PICK_FAILED" = true ]; then
  popd > /dev/null
  exit 0
fi

# Stage only upstream-relevant files, discard anything else
git reset HEAD 2>/dev/null || true
for path in "${UPSTREAM_PATHS[@]}"; do
  git add "$path" 2>/dev/null || true
done

if ! git diff --cached --quiet 2>/dev/null; then
  git commit -m "research: improve ${TARGET_METRIC} via ${ARTIFACT} (from fork ${FORK_OWNER})" 2>/dev/null
else
  log "Nothing to commit after filtering. Skipping."
  popd > /dev/null
  exit 0
fi

popd > /dev/null

# ─── Compute content hash for dedup ─────────────────────

pushd "$WORKTREE_DIR" > /dev/null
DIFF_HASH=$(git diff upstream/main --cached 2>/dev/null | sha256sum 2>/dev/null | cut -c1-12 || echo "")
if [ -z "$DIFF_HASH" ]; then
  # Fallback: hash the diff of HEAD vs upstream/main
  DIFF_HASH=$(git diff upstream/main HEAD -- "${UPSTREAM_PATHS[@]}" 2>/dev/null | sha256sum 2>/dev/null | cut -c1-12 || echo "nohash")
fi
popd > /dev/null

# Check for existing upstream PRs with the same diff hash
ARTIFACT_BASENAME=$(basename "$ARTIFACT")
DEDUP_PR=$(gh pr list --repo "$UPSTREAM_REPO" \
  --state open \
  --label "improvement" \
  --search "diff-hash:${DIFF_HASH}" \
  --json number --jq '.[0].number' 2>/dev/null || echo "")

if [ -n "$DEDUP_PR" ]; then
  log "Found existing upstream PR #${DEDUP_PR} with same content hash. Adding corroborating comment."
  gh pr comment "$DEDUP_PR" \
    --repo "$UPSTREAM_REPO" \
    --body "Corroborating data from another fork: **${TARGET_METRIC}** improved ${BASELINE} → ${FINAL} (delta: ${DELTA}). Fork: ${FORK_REPO:-unknown}" \
    2>/dev/null || log "Could not add comment to PR #${DEDUP_PR}"
  exit 0
fi

# ─── Push and create PR ─────────────────────────────────

if ! git push -u origin "$UPSTREAM_BRANCH" 2>/dev/null; then
  log "Push failed. Skipping upstream submission."
  exit 0
fi

log "Branch pushed. Creating cross-fork PR..."

DELTA_PCT=$(python3 -c "
b = float('$BASELINE')
print(f'{((float(\"$FINAL\") - b) / b) * 100:.0f}' if b > 0 else '0')
" 2>/dev/null || echo "?")

PR_CREATED=false
for attempt in 1 2 3; do
  if gh pr create \
    --repo "$UPSTREAM_REPO" \
    --head "${FORK_OWNER}:${UPSTREAM_BRANCH}" \
    --base main \
    --title "research: improve ${TARGET_METRIC} via ${ARTIFACT_BASENAME}" \
    --body "$(cat <<EOF
## Template Improvement: ${ARTIFACT}

A fork's nightly self-improvement cycle found a change that improved
**${TARGET_METRIC}** by ${DELTA_PCT}% (${BASELINE} → ${FINAL}) across
${ITERATIONS} iterations (${KEPT} kept, ${DISCARDED} discarded).

### What Changed
See the diff for details. This change was validated with a synthetic eval
that produced measurable improvement in the target metric.

### Evidence
- **Metric:** ${TARGET_METRIC}
- **Baseline:** ${BASELINE}
- **Final:** ${FINAL}
- **Delta:** +${DELTA} (+${DELTA_PCT}%)

<!-- improvement-metadata
metric: ${TARGET_METRIC}
artifact: ${ARTIFACT}
baseline: ${BASELINE}
final: ${FINAL}
delta: ${DELTA}
diff-hash: ${DIFF_HASH}
fork: ${FORK_REPO:-unknown}
-->

---
*Submitted automatically by a Build-Pipe fork's nightly self-improvement cycle.*
*Source fork: ${FORK_REPO:-unknown}*
EOF
)" \
    --label "improvement" 2>/dev/null; then
    PR_CREATED=true
    log "Upstream PR created successfully."
    break
  fi

  log "PR creation attempt ${attempt}/3 failed. Retrying in 5s..."
  sleep 5
done

if [ "$PR_CREATED" = false ]; then
  log "PR creation failed after 3 attempts. Cleaning up orphan branch."
  git push origin --delete "$UPSTREAM_BRANCH" 2>/dev/null || true
  exit 0
fi
