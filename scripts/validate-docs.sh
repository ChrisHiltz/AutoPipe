#!/usr/bin/env bash
# validate-docs.sh — Enforces the cross-linking rules, document traceability,
# and single-stage-per-PR discipline.
# Runs in CI to catch violations before PRs can merge.
# Exit codes: 0 = all valid, 1 = violations found

set -euo pipefail

DOCS_DIR="${1:-docs}"
SRC_DIR="${2:-src}"
ERRORS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_error() { echo -e "${RED}FAIL${NC} $1"; ((ERRORS++)); }
log_ok()    { echo -e "${GREEN}OK${NC}   $1"; }
log_warn()  { echo -e "${YELLOW}WARN${NC} $1"; }
log_info()  { echo "     $1"; }

echo "============================================"
echo "  Document Pipeline Validator"
echo "============================================"
echo ""

# ──────────────────────────────────────────────
# Helper: Extract referenced file from cross-link patterns
# Returns the referenced filename if found (e.g., ADR-42, PRB-42, SIG-42)
# ──────────────────────────────────────────────
check_reference_exists() {
  local doc="$1"
  local pattern="$2"      # regex to extract IDs (e.g., ADR-[0-9]+)
  local target_dir="$3"   # directory where referenced files should exist

  local refs
  refs=$(grep -oiE "$pattern" "$doc" 2>/dev/null | sort -u || true)

  if [ -z "$refs" ]; then
    return 1  # no references found
  fi

  local all_exist=true
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    # Check if a file matching this reference exists in target dir
    if ! compgen -G "${target_dir}/${ref}*" > /dev/null 2>&1; then
      log_error "$doc → references ${ref} but no matching file exists in ${target_dir}/"
      all_exist=false
    fi
  done <<< "$refs"

  if [ "$all_exist" = true ]; then
    return 0
  fi
  return 0  # errors already logged via log_error
}

# ──────────────────────────────────────────────
# Rule 1: PRDs must link to an ADR (with existence check)
# ──────────────────────────────────────────────
echo "--- Rule 1: PRD → ADR cross-links ---"
prd_count=0
if compgen -G "${DOCS_DIR}/04-specs/"*.md > /dev/null 2>&1; then
  for prd in "${DOCS_DIR}/04-specs/"*.md; do
    prd_count=$((prd_count + 1))
    if grep -qiE '(ADR-[0-9]+|docs/03-architecture/|Implements Architecture:)' "$prd"; then
      log_ok "$prd → links to ADR"
      # Verify referenced ADR actually exists
      check_reference_exists "$prd" 'ADR-[0-9]+' "${DOCS_DIR}/03-architecture"
    else
      log_error "$prd → NO link to an Architecture Decision Record"
      log_info "  Add 'Implements Architecture: [Link to ADR-xxx.md]' to this file"
    fi
  done
fi
if [ "$prd_count" -eq 0 ]; then
  log_warn "No PRD files found in ${DOCS_DIR}/04-specs/ (this is fine if no specs exist yet)"
fi
echo ""

# ──────────────────────────────────────────────
# Rule 2: ADRs must link to a PRB (with existence check)
# ──────────────────────────────────────────────
echo "--- Rule 2: ADR → PRB cross-links ---"
adr_count=0
if compgen -G "${DOCS_DIR}/03-architecture/"*.md > /dev/null 2>&1; then
  for adr in "${DOCS_DIR}/03-architecture/"*.md; do
    adr_count=$((adr_count + 1))
    if grep -qiE '(PRB-[0-9]+|docs/02-discovery/|Solves Problem:)' "$adr"; then
      log_ok "$adr → links to PRB"
      check_reference_exists "$adr" 'PRB-[0-9]+' "${DOCS_DIR}/02-discovery"
    else
      log_error "$adr → NO link to a Discovery/Problem document"
      log_info "  Add 'Solves Problem: [Link to PRB-xxx.md]' to this file"
    fi
  done
fi
if [ "$adr_count" -eq 0 ]; then
  log_warn "No ADR files found in ${DOCS_DIR}/03-architecture/ (this is fine if no architecture docs exist yet)"
fi
echo ""

# ──────────────────────────────────────────────
# Rule 3: PRBs must link to a raw input (with existence check)
# ──────────────────────────────────────────────
echo "--- Rule 3: PRB → Raw Input cross-links ---"
prb_count=0
if compgen -G "${DOCS_DIR}/02-discovery/"*.md > /dev/null 2>&1; then
  for prb in "${DOCS_DIR}/02-discovery/"*.md; do
    prb_count=$((prb_count + 1))
    if grep -qiE '(SIG-[0-9]+|docs/01-raw-inputs/|Raw Input Source:|#[0-9]+)' "$prb"; then
      log_ok "$prb → links to raw input"
      check_reference_exists "$prb" 'SIG-[0-9]+' "${DOCS_DIR}/01-raw-inputs"
    else
      log_error "$prb → NO link to a raw input/signal source"
      log_info "  Add 'Raw Input Source: [Link to signal or issue]' to this file"
    fi
  done
fi
if [ "$prb_count" -eq 0 ]; then
  log_warn "No PRB files found in ${DOCS_DIR}/02-discovery/ (this is fine if no discovery docs exist yet)"
fi
echo ""

# ──────────────────────────────────────────────
# Rule 4: No orphaned code — file-specific PRD mapping
# Source files changed in PR must be listed in a PRD's "Files to Create/Modify" section
# ──────────────────────────────────────────────
echo "--- Rule 4: No orphaned code ---"

# Detect changed source files
if [ -n "${GITHUB_BASE_REF:-}" ]; then
  changed_src_files=$(git diff --name-only "origin/${GITHUB_BASE_REF}...HEAD" -- "${SRC_DIR}/" 2>/dev/null | grep -E '\.(js|ts|jsx|tsx|py|go|rs|java|rb|ex|cs|kt|swift|dart|cpp|c|h|hpp)$' || true)
else
  changed_src_files=$(find "${SRC_DIR}/" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.rb" -o -name "*.ex" -o -name "*.cs" -o -name "*.kt" -o -name "*.swift" -o -name "*.dart" -o -name "*.cpp" -o -name "*.c" -o -name "*.h" \) 2>/dev/null || true)
fi

if [ -n "$changed_src_files" ]; then
  if [ "$prd_count" -eq 0 ]; then
    src_file_count=$(echo "$changed_src_files" | wc -l | tr -d ' ')
    log_error "Found $src_file_count source files but NO PRD in ${DOCS_DIR}/04-specs/"
    log_info "  Every code change must trace to a specification document"
    log_info "  Create a PRD using .templates/prd_template.md before writing code"
  else
    # File-specific check: each changed source file should appear in at least one PRD
    orphan_count=0
    while IFS= read -r src_file; do
      [ -z "$src_file" ] && continue
      # Check if this file path appears in any PRD (in the "Files to Create/Modify" section or anywhere)
      src_basename=$(basename "$src_file")
      if grep -rlq "$src_basename" "${DOCS_DIR}/04-specs/" 2>/dev/null; then
        : # file is referenced in a PRD
      elif grep -rlq "$src_file" "${DOCS_DIR}/04-specs/" 2>/dev/null; then
        : # full path is referenced in a PRD
      else
        # Also check for Implements: PRD-{n} comment in the source file itself
        if [ -f "$src_file" ] && grep -qE '# Implements: PRD-[0-9]+|// Implements: PRD-[0-9]+|-- Implements: PRD-[0-9]+' "$src_file" 2>/dev/null; then
          : # source file self-declares its PRD
        else
          log_error "$src_file → not referenced in any PRD (add to 'Files to Create/Modify' section or add '# Implements: PRD-{n}' comment)"
          orphan_count=$((orphan_count + 1))
        fi
      fi
    done <<< "$changed_src_files"

    if [ "$orphan_count" -eq 0 ]; then
      log_ok "All source files are traceable to specifications"
    else
      log_error "$orphan_count source file(s) not explicitly mapped to a PRD"
      log_info "  Add file paths to the 'Files to Create/Modify' section of the relevant PRD"
      log_info "  Or add '# Implements: PRD-{n}' comments to the source files"
    fi
  fi
else
  log_ok "No source code changes to validate"
fi
echo ""

# ──────────────────────────────────────────────
# Rule 5: Template completeness check (only check changed files in CI)
# ──────────────────────────────────────────────
echo "--- Rule 5: No placeholder text in documents ---"
placeholder_count=0

# In CI, only check files changed in this PR for efficiency
if [ -n "${GITHUB_BASE_REF:-}" ]; then
  docs_to_check=$(git diff --name-only "origin/${GITHUB_BASE_REF}...HEAD" -- "${DOCS_DIR}/" 2>/dev/null | grep '\.md$' || true)
else
  docs_to_check=$(find "${DOCS_DIR}/" -name "*.md" -type f 2>/dev/null || true)
fi

if [ -n "$docs_to_check" ]; then
  while IFS= read -r doc; do
    [ -z "$doc" ] && continue
    [ ! -f "$doc" ] && continue
    # Skip foundation docs (00-foundation/) — these are reference templates filled during /setup
    if echo "$doc" | grep -q "00-foundation/"; then
      continue
    fi
    if grep -qE '\[Short Title\]|\[Issue-Number\]|\[YYYY-MM-DD\]|\[Link to|\[path\]|\[existing-path\]' "$doc"; then
      log_error "$doc → contains unfilled template placeholders"
      placeholder_count=$((placeholder_count + 1))
    fi
  done <<< "$docs_to_check"
  if [ "$placeholder_count" -eq 0 ]; then
    log_ok "No unfilled template placeholders found"
  fi
else
  log_warn "No documents found to check"
fi
echo ""

# ──────────────────────────────────────────────
# Rule 6: Single-stage-per-PR discipline
# A PR should only contain artifacts from one pipeline stage
# ──────────────────────────────────────────────
echo "--- Rule 6: Single stage per PR ---"

if [ -n "${GITHUB_BASE_REF:-}" ]; then
  changed_files=$(git diff --name-only "origin/${GITHUB_BASE_REF}...HEAD" 2>/dev/null || echo "")

  stages_touched=0
  stage_names=""

  if echo "$changed_files" | grep -q "docs/01-raw-inputs/"; then
    stages_touched=$((stages_touched + 1))
    stage_names="${stage_names} raw-inputs"
  fi
  if echo "$changed_files" | grep -q "docs/02-discovery/"; then
    stages_touched=$((stages_touched + 1))
    stage_names="${stage_names} discovery"
  fi
  if echo "$changed_files" | grep -q "docs/03-architecture/"; then
    stages_touched=$((stages_touched + 1))
    stage_names="${stage_names} architecture"
  fi
  if echo "$changed_files" | grep -q "docs/04-specs/"; then
    stages_touched=$((stages_touched + 1))
    stage_names="${stage_names} specification"
  fi
  if echo "$changed_files" | grep -qE "^${SRC_DIR}/"; then
    stages_touched=$((stages_touched + 1))
    stage_names="${stage_names} code"
  fi

  if [ "$stages_touched" -gt 2 ]; then
    log_error "PR touches $stages_touched pipeline stages:${stage_names}"
    log_info "  Each PR should contain artifacts from ONE stage only"
    log_info "  Split this into separate PRs per stage"
  elif [ "$stages_touched" -eq 2 ]; then
    # Allow code + specs together (code phase may update the PRD checklist)
    if echo "$stage_names" | grep -q "code" && echo "$stage_names" | grep -q "specification"; then
      log_ok "PR contains code + spec updates (allowed: code phase may update PRD checklist)"
    else
      log_error "PR touches 2 pipeline stages:${stage_names}"
      log_info "  Each PR should contain artifacts from ONE stage only"
      log_info "  Only code + specification changes are allowed together"
    fi
  elif [ "$stages_touched" -eq 1 ]; then
    log_ok "PR is scoped to a single pipeline stage:${stage_names}"
  else
    log_ok "PR does not touch pipeline stage directories (config/script changes)"
  fi
else
  log_warn "Not running in CI — skipping single-stage check"
fi
echo ""

# ──────────────────────────────────────────────
# Rule 7: Codebase awareness checks
# ADRs must explore the codebase when source files exist
# ──────────────────────────────────────────────
echo "--- Rule 7: Codebase awareness ---"

# Check if src/ has real source files (not just .gitkeep)
has_source_files=false
if find "${SRC_DIR}/" -type f \( -name "*.py" -o -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \) 2>/dev/null | head -1 | grep -q .; then
  has_source_files=true
fi

codebase_checks=0
if [ "$adr_count" -gt 0 ] && compgen -G "${DOCS_DIR}/03-architecture/"*.md > /dev/null 2>&1; then
  for adr in "${DOCS_DIR}/03-architecture/"*.md; do
    # Check 1: Greenfield escape hatch — warn if src/ has files but ADR says Greenfield
    if [ "$has_source_files" = true ]; then
      if grep -q "Greenfield" "$adr" 2>/dev/null; then
        log_warn "$adr says 'Greenfield' but src/ contains source files — verify codebase was explored"
      fi
    fi

    # Check 2: Verify paths listed in "Modules examined" actually exist
    if grep -q "Modules examined" "$adr" 2>/dev/null; then
      modules_section=$(sed -n '/Modules examined/,/^\*\*\|^##/p' "$adr" 2>/dev/null | grep '^\- `' | sed 's/^- `//;s/`.*//' || true)
      if [ -n "$modules_section" ]; then
        while IFS= read -r module_path; do
          [ -z "$module_path" ] && continue
          if [ ! -e "$module_path" ]; then
            log_error "$adr → references module '$module_path' but it does not exist (hallucinated path)"
            codebase_checks=$((codebase_checks + 1))
          fi
        done <<< "$modules_section"
      fi
    fi
  done
fi

# Check 3: PRD MODIFY targets must exist
if [ "$prd_count" -gt 0 ] && compgen -G "${DOCS_DIR}/04-specs/"*.md > /dev/null 2>&1; then
  for prd in "${DOCS_DIR}/04-specs/"*.md; do
    # Extract files listed under "Modify:" section
    modify_section=$(sed -n '/^\*\*Modify:\*\*/,/^\*\*\|^##/p' "$prd" 2>/dev/null | grep '^\- `' | sed 's/^- `//;s/`.*//' || true)
    if [ -n "$modify_section" ]; then
      while IFS= read -r file_path; do
        [ -z "$file_path" ] && continue
        if [ ! -f "$file_path" ]; then
          log_warn "$prd → lists '$file_path' under Modify but file does not exist"
        fi
      done <<< "$modify_section"
    fi
  done
fi

if [ "$codebase_checks" -eq 0 ]; then
  log_ok "Codebase awareness checks passed"
fi
echo ""

# ──────────────────────────────────────────────
# Rule 8: Local dev sections in pipeline documents
# ADRs must have "Local Development Impact" section
# PRDs must have "Local Development Requirements" section
# ──────────────────────────────────────────────
echo "--- Rule 8: Local development completeness ---"
localdev_checks=0

# Check ADRs for Local Development Impact section
if [ "$adr_count" -gt 0 ] && compgen -G "${DOCS_DIR}/03-architecture/"*.md > /dev/null 2>&1; then
  for adr in "${DOCS_DIR}/03-architecture/"*.md; do
    if ! grep -q "Local Development Impact" "$adr" 2>/dev/null; then
      log_error "$adr → missing 'Local Development Impact' section (ADR Section 5)"
      log_info "  Every ADR must address how the architecture decision affects local development"
      localdev_checks=$((localdev_checks + 1))
    fi
  done
fi

# Check PRDs for Local Development Requirements section
if [ "$prd_count" -gt 0 ] && compgen -G "${DOCS_DIR}/04-specs/"*.md > /dev/null 2>&1; then
  for prd in "${DOCS_DIR}/04-specs/"*.md; do
    if ! grep -q "Local Development Requirements" "$prd" 2>/dev/null; then
      log_error "$prd → missing 'Local Development Requirements' section (PRD Section 4)"
      log_info "  Every PRD must include local development acceptance criteria"
      localdev_checks=$((localdev_checks + 1))
    fi
  done
fi

# Check that .env.example exists if any code changes are present
if [ -n "$changed_src_files" ]; then
  if [ ! -f ".env.example" ]; then
    log_warn "Source code changes present but no .env.example file found"
  fi
fi

if [ "$localdev_checks" -eq 0 ]; then
  log_ok "Local development sections present in all pipeline documents"
fi
echo ""

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
echo "============================================"
if [ "$ERRORS" -gt 0 ]; then
  echo -e "  ${RED}VALIDATION FAILED${NC}: $ERRORS error(s) found"
  echo "============================================"
  exit 1
else
  echo -e "  ${GREEN}VALIDATION PASSED${NC}: All checks clear"
  echo "============================================"
  exit 0
fi
