# Task Template

Reference document for Step 6 of the build-plan-generator process.

Every task file MUST use this exact template. No fields may be omitted (use `TBD` if unknown). No fields may be added without updating this template.

## YAML Frontmatter

```yaml
---
# === IDENTITY ===
id: WS{n}-BB{m}-T{k}                    # Required. Unique. Follows naming convention.
title: ""                                 # Required. Human-readable. <80 chars.
workstream: ""                            # Required. Kebab-case workstream name.
build_block: ""                           # Required. Kebab-case block name.

# === SCHEDULING ===
status: ready                             # Required. Enum: ready | blocked | in_progress | done | failed
lane: backend                            # Required. Enum: backend | frontend | integrations
depends_on: []                            # Required (may be empty). List of task IDs.
dependency_reasons: {}                    # Required if depends_on not empty. Map: task_id -> reason.
                                          # Reason categories: shared_file, shared_data_model,
                                          # shared_api, shared_function, pattern_reference
                                          # MUST include the specific file/table/endpoint/function name.
blocks: []                                # Required (may be empty). List of task IDs this blocks.
parallel_safe: true                       # Required. Can run alongside other ready tasks in different lanes.
branch: ""                                # Required. Git branch name. Format: feature/{id}-{short-name}
estimated_hours: 4                        # Required. Integer 2-8.

# === REVIEW ===
human_gate: false                         # Required. Boolean.
gate_reason: ""                           # Required if human_gate is true.
review_tier: auto_merge                   # Required. Enum: must_review | review_by_summary | auto_merge

# === TRACEABILITY ===
blueprint_refs: []                        # Required. List of "Section N: quote or summary" strings.
                                          # At least one required. If none, source must be "inferred".
source: blueprint                         # Required. Enum: blueprint | inferred
requires_human_confirmation: false        # Required. True if source is "inferred".
pattern_refs: []                          # Optional. References to pattern files to follow.
assumptions: []                           # Optional. Assumptions made where blueprint is ambiguous.
blueprint_ambiguity: false                # Required. True if blueprint was ambiguous for this task.

# === CONTRACTS ===
contracts_consumed: []                    # List of contract files/functions this task depends on.
contracts_produced: []                    # List of contract files/functions this task creates.
files_touched: []                         # Required. Directory-level paths from DIRECTORY-CONTRACT.md.
                                          # Max 2 directories.

# === ACCEPTANCE ===
acceptance_criteria: []                   # Required. 3-7 testable criteria. Natural language only.
product_intent_tests: []                  # Optional. High-level product intent validations.
---
```

## Markdown Body

The body after the frontmatter MUST include these sections in this order:

```markdown
## Product Context

[3-5 line compact summary of core product identity, anti-goals, and key constraints]
Full product truths: see PRODUCT-TRUTHS.md
[Any product truths specifically relevant to THIS task — e.g., "Core is unified — do NOT split"
for a Core task, or "Approval-first for all external actions" for a send task]

## Description

[2-4 paragraphs explaining what this task implements and why it matters to the product]

## Blueprint Context

[Exact quotes from the blueprint sections referenced in blueprint_refs]

## Scope Boundary

**In scope:**
- [explicit list]

**Out of scope:**
- [explicit list]

## Interface Contracts

[Function signatures, API endpoint shapes, or type definitions that this task must implement
or consume. These are CONTRACTS, not implementations. No function bodies. No SQL beyond
table/column names.]

## Coordination Notes

[Non-dependency notes about related tasks. Informational only, not blocking.]
```

## Field Validation Rules

1. `id` must follow pattern `WS{n}-BB{m}-T{k}` where n, m, k are integers
2. `title` must be under 80 characters
3. `workstream` and `build_block` must be kebab-case
4. `estimated_hours` must be an integer between 2 and 8 inclusive
5. `depends_on` entries must reference valid task IDs that exist in the plan
6. `dependency_reasons` must have an entry for every ID in `depends_on`
7. `files_touched` must reference paths from DIRECTORY-CONTRACT.md, max 2 entries
8. `acceptance_criteria` must have 3-7 items, written in natural language (no code)
9. `blueprint_refs` must have at least one entry unless `source` is `inferred`
10. If `source` is `inferred`, `requires_human_confirmation` must be `true`
11. If `blueprint_ambiguity` is `true`, `assumptions` must not be empty
12. `branch` must follow format `feature/{id}-{short-name}`
