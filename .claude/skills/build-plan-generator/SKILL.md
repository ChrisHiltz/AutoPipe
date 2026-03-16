---
name: build-plan-generator
description: >
  Use when turning a product blueprint into an orchestrator-ready build plan.
  Triggers on "build plan", "decompose blueprint", "plan implementation",
  "create tasks from blueprint", "break down the blueprint", or any request
  to convert a design document into executable agent tasks. Also use when
  the user has a blueprint and wants to prepare it for multi-agent execution,
  task decomposition, or autonomous coding workflows.
---

# Build Plan Generator

A rigid skill that ingests a product blueprint and produces a structured, dependency-aware, orchestrator-ready build plan. The output is a package of markdown files with YAML frontmatter that any orchestrator (like ComposioHQ's agent-orchestrator) can consume.

**This is a rigid skill. Follow exactly. The rigidity IS the value — it prevents the hallucination and drift that freeform planning produces.**

## What This Skill Is NOT

- NOT a code generator. It produces planning artifacts, never implementation code.
- NOT a project management tool. It produces a one-time build plan, not ongoing tracking.
- NOT a blueprint writer. It consumes an existing blueprint; it does not create one.
- NOT an orchestrator. It produces files the orchestrator consumes; it does not execute tasks.

## Announcement

> "Using build-plan-generator to decompose the blueprint into an orchestrator-ready build plan."

## Required Checklist

Create a TodoWrite checklist with these items:

1. Extract product truths from blueprint
2. Define directory contract
3. Structural extraction (read blueprint in sections, build summary)
4. Define workstreams from structural summary
5. For each workstream: extract build blocks
6. For each build block: generate agent tasks (+ density check)
7. Build dependency graph
8. Identify human gates
9. Identify risks and blueprint gaps
10. Extract contracts (schema/API/type) from all tasks
11. Dispatch build-plan-reviewer and architecture-guard subagents
12. Address review findings
13. Run scripts/validate_plan.py against generated plan
14. Generate final plan summary
15. Present plan to user and hand off to review

---

## Process Flow

Steps cannot be reordered or skipped.

```
Step 1: PRODUCT TRUTHS → PRODUCT-TRUTHS.md
  Read blueprint. Extract identity, anti-goals, locked decisions, named concepts.
  This is the FIRST output.

Step 2: DIRECTORY CONTRACT → DIRECTORY-CONTRACT.md
  Define project folder structure (top 2 levels).
  Tag as requires_human_confirmation.

  *** CHECKPOINT: STOP and ask user to confirm product truths and directory contract. ***
  *** These are the foundation — if wrong, everything downstream is wrong. ***

Step 3: STRUCTURAL EXTRACTION → internal structural-summary
  Read blueprint in ~200-line chunks. For each chunk extract ONLY:
  section headings, data model objects, integrations, dependencies, phases, constraints.
  Write extractions to running structural summary. DO NOT hold full blueprint.

Step 4: WORKSTREAM DEFINITION → WORKSTREAMS.md + workstream dirs
  Using ONLY the structural summary, define 4-8 workstreams.
  Each has: name, scope boundary, blueprint sections, dependencies on other workstreams.

Step 5: BUILD BLOCK DEFINITION → WORKSTREAM.md per workstream
  For each workstream (with fresh context), define 2-5 build blocks.
  Each has: name, scope, relevant blueprint sections, lane assignment.
  Load references/decomposition-rules.md for this step.

Step 6: TASK GENERATION → task files in tasks/
  For each build block (with fresh context):
  - Read ONLY relevant blueprint sections (cited from structural summary)
  - Load references/task-template.md
  - Generate 2-4 tasks per block
  - Each task includes a compact product context (see B4 below)
  - Validate every task against the template
  Load references/decomposition-rules.md for this step.

  *** SELF-CHECK: Count total tasks. If >60, consolidate. ***
  *** If any workstream has <2 build blocks, re-examine. ***
  *** DENSITY CHECK: Compare task counts across workstreams. ***
  *** If any workstream has >2.5x the tasks of another, re-examine. ***
  *** Smaller workstreams may have fewer tasks, but the gap should ***
  *** reflect genuine scope difference, not decomposition fatigue. ***

Step 7: DEPENDENCY GRAPH → DEPENDENCY-GRAPH.md
  Build DAG from all task depends_on fields. Validate:
  - No circular dependencies
  - No dangling references
  - Every task reachable from root
  - Every depends_on has a coded reason

Step 8: HUMAN GATES → HUMAN-GATES.md
  Collect all tasks with human_gate: true.
  Group by gate reason. Verify coverage of security, product design, compliance.
  Load references/autonomy-policy.md for this step.

Step 9: RISKS & GAPS → RISKS.md
  Collect all blueprint gaps, ambiguities, inferred tasks, TBD fields.
  Categorize by severity.
  Load references/failure-recovery.md for this step.

Step 10: CONTRACTS → CONTRACTS.md
  Extract all schema contracts, API contracts, type contracts from across all tasks.
  Verify producers sequenced before consumers.

Step 11: REVIEW SUBAGENTS
  Dispatch build-plan-reviewer (read build-plan-reviewer-prompt.md) and
  architecture-guard (read architecture-guard-prompt.md) as subagents.
  Architecture-guard now has CONTRACTS.md available for constraint #6.
  Address findings. Max 3 review iterations.

  *** Address ALL review findings before generating final summary. ***

Step 12: VALIDATE PLAN
  Run scripts/validate_plan.py against the build-plan/ directory.
  This checks: required fields, schema validity, dangling dependencies,
  circular dependencies, invalid review tiers, task count thresholds,
  sizing violations, code-in-tasks detection, and density variance.
  Fix any failures before proceeding.

Step 13: PLAN SUMMARY → PLAN-SUMMARY.md + REVIEW-CHECKLIST.md
  Generate: workstream count, task count, estimated total hours,
  human gates count, risk count, parallelization analysis.
  Include task density table: tasks per workstream with ratios.

Step 14: PRESENT TO USER + REVIEW HANDOFF
  Show the plan summary stats (workstream count, task count, estimated hours,
  human gates, risks, parallelization analysis, task density table).

  Then present review handoff options:

  "Your build plan is ready. How would you like to proceed?"

  1. "Submit for comprehensive review" (Recommended)
     → Invoke /buildplan-review
     This runs the full review skill against the generated plan,
     checking structural integrity, dependency correctness, product
     alignment, and execution readiness.

  2. "Submit with focus notes"
     → Ask user for specific areas of concern or attention
     → Write their notes to build-plan/REVIEW-FOCUS.md
     → Then invoke /buildplan-review
     The reviewer will prioritize the flagged areas while still
     performing the full review.

  3. "Skip review" (NOT recommended for autonomous execution)
     → Accept the plan as-is without review
     Warn: "Skipping review is not recommended if this plan will
     drive autonomous agent execution. Unreviewed plans have higher
     risk of dependency errors, missing gates, and scope drift."

  DO NOT proceed without the user making an explicit choice.
```

---

## Context Window Management

These rules prevent context overflow and positional decay on large blueprints. They are non-negotiable.

### Rule 1: Never Hold Full Blueprint + Full Output
Maintain at most THREE documents in active context at any time:
1. The structural summary (10-20% of blueprint size)
2. The current working document (one workstream or build block)
3. The product truths (small, constant)

### Rule 2: Section-by-Section Reading
Read the blueprint in chunks of ~200 lines. For each chunk, extract ONLY structural information (headings, data objects, integrations, dependencies, phases, constraints). Write extractions immediately. Do NOT attempt to remember the full chunk.

### Rule 3: Fresh Context Per Workstream
When generating tasks for Workstream N, load only: product truths + structural summary + relevant blueprint sections for Workstream N. Do NOT carry forward task outputs from previous workstreams.

### Rule 4: Reference Documents Loaded On Demand
- Load `references/decomposition-rules.md` during Steps 4-6 only
- Load `references/task-template.md` during Step 6 only
- Load `references/autonomy-policy.md` during Step 8 only
- Load `references/failure-recovery.md` during Step 9 only
- Do NOT load all reference documents at once

### Rule 5: Subagent Dispatch for Review
Step 10 uses subagent dispatch — the reviewer gets a FRESH context containing only the generated plan files, not the blueprint reading history.

---

## Critical Boundaries

These boundaries prevent the specific failure modes that destroy build plans. Each exists because of real failure patterns observed in blueprint decomposition.

### B1: No Invented Requirements
Every task MUST include `blueprint_refs` citing the specific blueprint section(s) it implements. If you cannot cite a reference, tag the task `source: inferred` and `requires_human_confirmation: true`. Do NOT add requirements beyond what the blueprint states. Blueprint gaps go in RISKS.md as "Blueprint Gap" items, not silently filled with solutions.

The temptation to add "obvious" features is strong — error handling patterns, testing frameworks, architectural patterns that seem like best practice. Resist it. If the blueprint doesn't mention it, you don't specify it.

### B2: No Fabricated Dependencies
Dependencies MUST be justified by one of exactly five concrete reasons:
1. **Shared file:** Task B modifies a file Task A creates (cite file path)
2. **Shared data model:** Task B reads from a table Task A creates (cite table)
3. **Shared API contract:** Task B calls an endpoint Task A implements (cite endpoint)
4. **Shared function/type:** Task B imports something Task A defines (cite name)
5. **Pattern reference:** Task B follows a pattern Task A establishes (cite pattern)

"Conceptual" dependencies ("these features are related") are NOT valid. Note them as `coordination_notes`, not `depends_on`. Every `depends_on` entry MUST include a `dependency_reason` with the category and specific artifact.

### B3: No Hallucinated File Paths
No code exists yet. Define `DIRECTORY-CONTRACT.md` FIRST (top 2 levels only). All task `files_touched` entries MUST reference paths from that contract. The directory contract requires human confirmation. Do NOT invent deeply nested paths — specify directory-level paths and let implementing agents decide file names.

### B4: Product Intent Preservation
Extract `PRODUCT-TRUTHS.md` as the VERY FIRST output. Every task file MUST include a "Product Context" section containing:
1. A 3-5 line compact summary of core product identity and anti-goals
2. The line: `Full product truths: see PRODUCT-TRUTHS.md`
3. Any product truths specifically relevant to THIS task (e.g., "Core is unified" for a Core task)

This keeps product intent present without duplicating the full document 50+ times. The build-plan-reviewer checks every task against the full PRODUCT-TRUTHS.md. Without product context, "agent-first operational backbone" decomposes into "CRM with AI chat bolted on."

### B5: Consistent Task Metadata
All tasks MUST conform to the exact template in `references/task-template.md`. Required fields cannot be omitted — use `TBD` if unknown and add a corresponding RISKS.md entry.

### B6: No Code in Tasks
Tasks describe WHAT to implement, not HOW. Tasks MAY include interface contracts (signatures, type definitions, endpoint shapes). Tasks MUST NOT include function bodies, SQL statements, React JSX, or any runnable code. Exception: natural-language test assertions in acceptance criteria.

### B7: No Over-Decomposition
Target 30-60 tasks for a 1000-2000 line blueprint. Minimum task size: 2 hours. Maximum: 8 hours. If smaller, merge; if larger, split into vertical slices (not horizontal layers). A vertical slice implements a feature path (schema + API + test for one entity), NOT a horizontal layer (all schemas, all endpoints). Count tasks and report — if >60, consolidate.

### B8: No Silent Product Decisions
When the blueprint is ambiguous, document the ambiguity in RISKS.md, tag affected tasks with `blueprint_ambiguity: true`, state the assumption in the task's `assumptions` field, and flag for human review. Never resolve ambiguities silently.

### B9: Positional Decay Prevention
Each workstream MUST be processed in isolation with dedicated context. Do NOT process all workstreams in sequence within one pass. After defining workstreams, each workstream's task generation is independent. Later workstreams must have equivalent task density and specificity to earlier ones.

### B10: Task Sizing as Vertical Slices
A task produces exactly one PR, touches at most 2 directories, and takes 2-8 estimated hours. Tasks are vertical slices through the stack, never horizontal layers. See `references/decomposition-rules.md` for the full sizing validation table and grouping rules.

---

## Rationalization Prevention

If you catch yourself thinking any of these, a boundary is about to be violated:

| Thought | Reality | Boundary |
|---------|---------|----------|
| "This feature is obviously needed" | If not in blueprint, it's invented | B1 |
| "These tasks are conceptually related" | Conceptual ≠ code-level dependency | B2 |
| "I know what the file structure should be" | No code exists. Human confirms. | B3 |
| "The blueprint clearly implies this" | Implications are assumptions. Mark inferred. | B8 |
| "Let me include a code snippet" | Code snippets are hallucinated implementations | B6 |
| "This workstream only needs 1 build block" | Probably under-decomposed. Re-examine. | B9 |
| "I can hold all of this in context" | No you can't. Process in sections. | Rule 2 |
| "This task is simple, skip some fields" | Every template field required. | B5 |
| "The dependency reason is obvious" | Code it explicitly or it's fabricated | B2 |
| "70 tasks isn't that many" | It's too many. Consolidate. | B7 |

---

## Output Artifact Structure

The complete build plan package:

```
build-plan/
├── PLAN-SUMMARY.md                  # Plan overview with stats
├── PRODUCT-TRUTHS.md                # Non-negotiable product constraints
├── DIRECTORY-CONTRACT.md            # Project folder structure (human-confirmed)
├── DEPENDENCY-GRAPH.md              # Full DAG + adjacency list + critical path
├── WORKSTREAMS.md                   # Workstream definitions with scope boundaries
├── CONTRACTS.md                     # Schema/API/type contracts with sequencing
├── HUMAN-GATES.md                   # All human-gated tasks grouped by reason
├── RISKS.md                         # Blueprint gaps, ambiguities, risks
├── REVIEW-CHECKLIST.md              # Human review verification items
└── workstreams/
    ├── WS0-{name}/
    │   ├── WORKSTREAM.md
    │   └── tasks/
    │       ├── WS0-BB1-T1-{name}.md
    │       └── ...
    ├── WS1-{name}/
    │   ├── WORKSTREAM.md
    │   └── tasks/
    │       └── ...
    └── ...
```

Every file is markdown with structured YAML frontmatter. No proprietary formats.
