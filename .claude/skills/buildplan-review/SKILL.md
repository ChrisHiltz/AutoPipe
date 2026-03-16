---
name: buildplan-review
description: >
  Adversarial audit AND remediation of build plans for autonomous multi-agent
  coding pipelines. Reviews, fixes, and certifies build plans until they score
  95+ and are ready for one-pass autonomous execution. Use whenever the user
  asks to review, audit, stress-test, validate, certify, or prepare a build
  plan for orchestrator execution. Triggers on "review build plan", "audit
  build plan", "is this build plan ready", "check this plan for orchestration",
  "stress test the build plan", "can agents execute this", "build plan review",
  "get this plan ready for agents", "certify the build plan", or any request
  to determine whether a build plan is safe and realistic for high-autonomy
  orchestrated coding. Also use when the user has a build plan and wants to
  prepare it for a Composio-style or similar agent orchestrator workflow.
---

# Build Plan Review & Remediation

This skill does not just review build plans — it **fixes them**. The output is not a report. The output is a certified, ready-to-execute build plan that scores 95+ on the autonomy readiness rubric.

Five phases:
0. **Catalog**: Deterministic scripts extract metadata and run 26 structural checks
1. **Pre-flight**: Collect every human input needed before any agent touches the plan
2. **Audit**: 5 independent agents score the plan against a 15-category rubric
3. **Fix loop**: Main agent creates fix plans, sub-agents execute edits, re-audit until score >= 95
4. **Certify**: Auto-generate REVIEW-CHECKLIST.md and present certified plan

The plan does not leave this skill until it is ready for one-pass autonomous execution.

## Announcement

> "Starting build-plan review and remediation. First: cataloging the plan and running structural validation."

## Required Checklist

Create a TodoWrite checklist with these items:

1. Gather and inventory all input materials
2. PHASE 0: Run catalog_plan.py to produce plan-catalog.json
3. PHASE 0: Run validate_plan_extended.py — fix any blockers before proceeding
4. PHASE 1: PRE-FLIGHT — Scan catalog for all human-required inputs
5. PHASE 1: PRE-FLIGHT — Ask user for ALL missing inputs (one AskUserQuestion batch)
6. PHASE 1: PRE-FLIGHT — Apply human inputs to the build plan
7. PHASE 2: AUDIT PASS 1 — Spawn 5 independent review agents
8. PHASE 2: AUDIT PASS 1 — Run parse_agent_report.py on each report
9. PHASE 2: AUDIT PASS 1 — Run synthesize_scores.py to produce audit-synthesis.json
10. PHASE 3: FIX — Create fix plan from synthesis + fix-patterns.md
11. PHASE 3: FIX — Spawn sub-agents to execute file edits
12. PHASE 3: FIX — Re-catalog, re-validate, re-audit (repeat until >= 95 or 3 passes)
13. PHASE 4: CERTIFY — Output the final certified build plan

---

## PHASE 0: CATALOG — Deterministic Pre-Processing

Run these scripts BEFORE any agent work. They produce compact JSON that all subsequent phases consume.

### Step 1: Catalog the plan

```bash
python scripts/catalog_plan.py <build-plan-dir>
```

This produces `plan-catalog.json` in the plan directory — a ~5KB structured map of all tasks, dependencies, quality signals, and merge hotspots.

**If the script fails:** Fall back to manual cataloging — use Glob to find all task files, Read each one, and build the catalog mentally. This is slower but functional.

### Step 2: Validate the plan

```bash
python scripts/validate_plan_extended.py <path-to-plan-catalog.json>
```

This produces `validation-report.json` with 26 structural checks, each tagged with severity (blocker/warning/info).

**BLOCKER GATE:** If `validation-report.json` has `"gate": "BLOCKED"`, fix the blocker issues BEFORE proceeding to Phase 1. Common blockers: circular dependencies, missing required artifacts, dangling dependency references, migration ordering conflicts.

**If the script fails:** Fall back to the original `validate_plan.py` from the blueprint-to-buildplan skill, which covers 16 of the 26 checks.

---

## PHASE 1: PRE-FLIGHT — Collect All Human Inputs

### User Focus Notes
If `build-plan/REVIEW-FOCUS.md` exists, read it before starting Phase 1.
These are the user's specific concerns about the plan — areas they want extra scrutiny on.
- Pass focus areas to all 5 audit agents as additional context in Phase 2
- Ensure the audit specifically evaluates the areas the user flagged
- In the fix loop (Phase 3), prioritize fixes related to user-flagged areas
- Delete REVIEW-FOCUS.md after incorporating (it's a one-time input, not a permanent artifact)

**This phase is MANDATORY. Do not skip it.**

Use `plan-catalog.json` to efficiently scan for human-dependent items:

### What to scan for:

1. **Credentials & API keys** — Check `top_level_artifacts` for SERVICE-PROVISIONING.md. Check task acceptance_criteria for mentions of API keys, OAuth, tokens.
2. **Design decisions with placeholder values** — Scan acceptance_criteria across tasks for "TBD", "TODO", "placeholder", "to be determined".
3. **Product ambiguities** — Check tasks where `has_decision_cross_refs` is false but description mentions decisions or tradeoffs.
4. **OAuth & external service setup** — Check for Composio, Twilio, OAuth mentions in contracts_consumed.
5. **Architecture decisions not yet locked** — Check if DECISIONS-LOCKED.md and TECH-DECISIONS.md exist in `top_level_artifacts`.
6. **Pre-flight fix plans** — Check if PRE-FLIGHT-FIX-PLAN.md exists in the plan directory. If so, read it and verify whether fixes have been applied.

### How to collect:

Use **one AskUserQuestion call** with up to 4 questions batching related inputs. If more than 4 questions of input needed, do multiple rounds.

**Do NOT proceed to Phase 2 until all human inputs are collected.**

### Apply the inputs:

After collecting answers, update the build plan files directly. Then re-run `catalog_plan.py` to refresh the catalog with applied changes.

---

## PHASE 2: AUDIT — 5 Independent Review Agents

### Agent Setup

Each agent receives:
- `plan-catalog.json` (compact full-plan map)
- `validation-report.json` (structural checks — agents skip re-checking these)
- 8-12 domain-relevant task files (assigned from catalog's `file_map`)
- `references/sub-agent-instructions.md` (full mission)
- `references/rubric.md` (scoring criteria with 9-vs-10 distinctions)
- `references/fix-patterns.md` (what "good" looks like)
- `references/failure-modes.md` (what to hunt for)

### The 5 Review Agents

Spawn all 5 with **10-minute timeout**. Each reads materials fresh and forms independent conclusions.

| Agent | Focus | Assigned Files (from catalog) |
|-------|-------|-------------------------------|
| 1 Arch+Deps | Task ordering, DAGs, sequencing, parallelization | DEPENDENCY-GRAPH.md, WORKSTREAMS.md, CONTRACTS.md, 3-4 critical-path tasks |
| 2 Repo+CI | Merge conflicts, test strategy, CI readiness | DIRECTORY-CONTRACT.md, .agent-rules.md, bootstrap task, CI/deploy tasks |
| 3 Env+Data | Bootstrap determinism, env vars, migrations | SERVICE-PROVISIONING.md, TECH-DECISIONS.md, schema/migration tasks |
| 4 Product+AC | Vague specs, edge cases, untestable requirements | PRODUCT-TRUTHS.md, DECISIONS-LOCKED.md, 4-5 tasks where has_error_path_ac is false |
| 5 Ops+Realism | Failure recovery, idempotency, human burden | RISKS.md, HUMAN-GATES.md, reliability task, e2e test task, deployment task |

Use the catalog's `file_map` to identify which task files to assign each agent. Prioritize: critical-path tasks, tasks with `has_error_path_ac: false`, human-gated tasks, and tasks with many dependencies.

### Score Extraction

After agents complete, extract scores deterministically:

```bash
python scripts/parse_agent_report.py --input agent-report-1.md --output agent-1-scores.json
python scripts/parse_agent_report.py --input agent-report-2.md --output agent-2-scores.json
# ... for all 5
```

**If parser fails on a report:** Extract scores manually from the agent's markdown scorecard table.

### Score Synthesis

```bash
python scripts/synthesize_scores.py --input-dir <dir-with-agent-jsons> --output audit-synthesis.json
```

This produces `audit-synthesis.json` with: median per category, overall score, fix_targets (categories < 9 with affected files), deduplicated findings.

**The overall score in audit-synthesis.json is the official score. No manual adjustments.**

---

## PHASE 3: FIX LOOP — Remediate Until 95+

This is where the skill earns its value. **HARD GATE: score must reach 95 before certification. Maximum 3 fix passes.**

### The Loop

```
pass_count = 0
while score < 95 AND pass_count < 3:
    pass_count += 1

    1. READ audit-synthesis.json — identify fix_targets (categories < 9)
    2. READ references/fix-patterns.md — get concrete fix actions for each weak category
    3. CREATE DETAILED FIX PLAN:
       For each fix_target:
         - List affected files (from fix_targets.affected_files)
         - List specific changes (from fix-patterns.md actions)
         - Write exact AC text to add, sections to create, etc.
         - Group by file to minimize agent context switches

    4. SPAWN 1-3 SUB-AGENTS to execute edits:
       - Each sub-agent gets a subset of files + explicit edit instructions
       - Sub-agents do the actual file editing (Edit tool)
       - Main agent preserves context for orchestration
       - Sub-agent instructions must be SPECIFIC:
         "In file WS3-BB2-T1-qualification-graph.md, add these acceptance criteria
          after the existing ACs: [exact text]. Also add this to the Scope Boundary
          In scope section: [exact text]."

    5. SNAPSHOT: Copy plan-catalog.json to plan-catalog-before.json
    6. RE-CATALOG: python scripts/catalog_plan.py <build-plan-dir>
    7. TRACK FIXES: python scripts/track_fixes.py --before plan-catalog-before.json --after plan-catalog.json --pass-number {pass_count}
    8. RE-VALIDATE: python scripts/validate_plan_extended.py <plan-catalog.json>

    9. RE-AUDIT with 2-3 agents (only categories that scored < 9):
       - Re-audit agents get: catalog + validation + fix-pass-{N}-changelog.md
       - Focus on whether fixes actually improved the weak categories

    10. PARSE + SYNTHESIZE:
        python scripts/parse_agent_report.py (for each re-audit report)
        python scripts/synthesize_scores.py --input-dir <dir> --output audit-synthesis.json --previous-synthesis audit-synthesis-prev.json

    11. SCORE MERGING: New scores for re-audited categories, carry forward old scores for unchanged categories

    12. STUCK DETECTION: If same category scores < 9 for 2 consecutive passes:
        - Stop and AskUserQuestion about the specific blocker
        - "Category X has scored {score} for 2 passes. The fix attempts were: [list]. What should we do?"
```

### What "fix" means:

Fixing means actually editing build plan files. The main agent creates the fix plan; sub-agents execute it:

- **Missing error-path ACs?** Write exact AC text for each affected task file
- **Missing decision cross-refs?** Add DA-N/BL-N/CC-N references to relevant ACs
- **Task too large?** Split into 2-3 tasks, write new task files, update DAG
- **Missing bootstrap task?** Write full task file with YAML frontmatter, scope, ACs
- **Missing .env.template?** Create it with all required variables
- **Vague acceptance criteria?** Rewrite as specific machine-checkable commands
- **Missing health check AC?** Add GET /health endpoint AC to deployment tasks
- **Missing idempotency?** Add idempotency key requirement to event-producing tasks

### What you cannot fix (requires user):

If the fix loop hits an issue requiring human judgment:
1. Stop the loop
2. AskUserQuestion with the specific decision needed
3. Apply the answer, resume the loop

---

## PHASE 4: CERTIFICATION

When the score reaches 95+:

1. Run one final `validate_plan_extended.py` to confirm all fixes are consistent
2. Update PLAN-SUMMARY.md with the certified score and changes made
3. Create or update REVIEW-CHECKLIST.md with full audit trail (track_fixes.py has been appending to it)
4. Present to user:
   - Final score with full 15-category scorecard
   - Summary of all changes made (files added, modified, removed)
   - Audit history (score per pass, issues fixed per pass)
   - Any remaining items below 9/10 with explanation
   - Confirmation that the plan is ready for autonomous execution

The user should be able to hand the output directory directly to the orchestrator.

---

## Style Rules

- Be ruthless, precise, and concrete
- No fluff, no fake confidence, no motivational language
- Say exactly what is broken and exactly how to fix it — then fix it
- Every finding must name the specific file, task, or config
- Treat ambiguity as a defect. Treat untestable requirements as a defect.
- The job is to make this build plan safe for autonomous execution

---

## Reference Files

Load these during execution:

- `references/sub-agent-instructions.md` — Full mission for review sub-agents
- `references/rubric.md` — 15-category scoring rubric with 9-vs-10 criteria
- `references/failure-modes.md` — Failure mode checklist and special audit areas
- `references/output-formats.md` — Output schemas for agents, synthesis, and certification
- `references/fix-patterns.md` — Fix pattern library (what 10 looks like, how to get there)

## Scripts

Run these via Bash tool:

- `scripts/catalog_plan.py <build-plan-dir>` — Produce plan-catalog.json
- `scripts/validate_plan_extended.py <plan-catalog.json>` — Produce validation-report.json
- `scripts/parse_agent_report.py --input <report.md> --output <scores.json>` — Extract scores from agent markdown
- `scripts/synthesize_scores.py --input-dir <dir> --output <synthesis.json>` — Compute medians, fix targets
- `scripts/track_fixes.py --before <old.json> --after <new.json> --pass-number N` — Generate fix changelog
