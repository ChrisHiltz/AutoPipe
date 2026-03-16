---
name: research
description: "Run an autoresearch improvement cycle on a Build-Pipe pipeline artifact. Use this skill when the user says /research, 'run research cycle', 'improve the pipeline', 'autoresearch', or 'run experiment'. Also triggered automatically by nightly-cycle.sh after dispatch. Follows Karpathy's autoresearch methodology: one metric, one eval, iterate until improved."
---

# Build-Pipe Research Agent

You improve pipeline artifacts through controlled experiments, following the autoresearch methodology. The dispatch agent already picked your target — you execute the experiment.

## Core Principle

From Karpathy's autoresearch: **one metric, one eval, iterate.** You modify one artifact at a time, measure the effect, and keep or discard each change based on whether the metric improved. No subjective judgments — only numbers.

## Your Inputs

1. **`docs/06-operations/current-research-task.json`** — Your assignment from the dispatch agent. Contains: metric, baseline, artifact to modify, hypothesis, eval definition, iteration limit.
2. **`docs/06-operations/research-strategy.md`** — Constraints. Check the off-limits list before modifying anything.
3. The artifact file specified in the task (e.g., `.templates/prd_template.md`)

## The Loop

**MANDATORY:** You MUST attempt ALL iterations from 1 through `max_iterations`. Do NOT stop after the first improvement — compound improvements are the goal. Each successful change raises the baseline for the next iteration.

For iteration X of `max_iterations` (announce each iteration with this header):

```
=== ITERATION X of {max_iterations} ===
```

### 1. Measure Baseline (first iteration only)

Before changing anything, run the eval to establish a baseline number. Record it.

For synthetic evals, this typically means:
- Create a temporary test directory structure
- Generate test documents using the current artifact
- Run the validation/check
- Run the eval script/procedure and record a single numeric score. The eval MUST produce a concrete number (e.g., 3/5 test cases pass = 0.60, 0 violations out of 3 documents = 1.00). Never use subjective assessments like "improved" or "looks better" — only numbers

### 2. Form Hypothesis

Based on the task's hypothesis (and any learnings from previous iterations), decide on a specific change. Be precise — "improve the template" is too vague. "Add a mandatory 'Files to Create/Modify' checklist with explicit instructions to list every source file" is specific enough.

### 3. Make the Change

Edit the artifact. Keep changes minimal and targeted. One change per iteration so you can isolate the effect.

### 4. Run the Eval

Run the exact same eval procedure as the baseline. Same test cases, same measurement method. The only difference is the modified artifact.

### 5. Compare

```
if final_metric > baseline_metric:
    KEEP → commit the change
else:
    DISCARD → revert the change (git checkout the file)
```

For metrics where lower is better (failure count, time), flip the comparison.

**Whether you KEEP or DISCARD, proceed to the next iteration.** A discarded change means you learned something — use that learning to form a better hypothesis. A kept change means the baseline just improved — build on it.

### 6. Record

Track each iteration internally:
```
Iteration 1: hypothesis="add file checklist", result=improved (0.67 → 1.00), KEPT
Iteration 2: hypothesis="add cross-link validator hint", result=no change (1.00 → 1.00), DISCARDED
```

### 7. Next Iteration

Use learnings from this iteration to form the next hypothesis. If you kept a change, the baseline for the next iteration is the new (improved) number.

### Stop Conditions

You may ONLY exit the loop early if:
1. You have completed ALL `max_iterations`
2. The metric has reached or exceeded the `target` value from the research task AND you have completed at least 3 iterations
3. The `time_budget_minutes` has been exceeded

If none of these conditions are met, you MUST continue to the next iteration. "I can't think of more hypotheses" is not a valid stop condition — try a different angle, a different section of the artifact, or a reversal of a previous hypothesis.

## After the Loop

### Log Results

Append ONE line to `docs/06-operations/research-log.jsonl`:

```json
{"date":"2026-03-15","target_metric":"ci_pass_rate","artifact":".templates/prd_template.md","hypothesis":"Add file mapping checklist to template","iterations":5,"kept":3,"discarded":2,"baseline":0.67,"final":1.0,"improved":true}
```

### If Improved (any iteration was kept)

1. Make sure all kept changes are committed on a new branch:
   ```
   git checkout -b research/2026-03-15-ci_pass_rate
   git add <modified artifact>
   git add docs/06-operations/research-log.jsonl
   git commit -m "research: improve ci_pass_rate via template changes"
   ```

2. Open a PR:
   ```
   gh pr create \
     --title "research: improve {metric} ({baseline} → {final})" \
     --body "## Research Experiment Results

   **Target Metric:** {metric}
   **Artifact Modified:** {artifact}
   **Baseline:** {baseline}
   **Final:** {final}
   **Iterations:** {total} ({kept} kept, {discarded} discarded)

   ### What Changed
   {description of the changes that were kept}

   ### Evidence
   {eval output showing improvement}

   ### Hypothesis
   {the reasoning behind the changes}

   ---
   *Generated by Build-Pipe nightly self-improvement cycle.*" \
     --label "pipeline:proposal"
   ```

### If NOT Improved (all iterations discarded)

1. Make sure all changes are reverted
2. Still log to research-log.jsonl with `"improved": false`
3. Do NOT open a PR
4. The dispatch agent will see this and pick a different target next time

## Synthetic Eval Recipes

Use these patterns when implementing the eval defined in the research task.

### Recipe 1: Template → Validate

Test whether documents produced from a template pass CI validation.

```bash
# Setup: create temporary pipeline structure
TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/docs/01-raw-inputs" "$TMPDIR/docs/02-discovery" \
         "$TMPDIR/docs/03-architecture" "$TMPDIR/docs/04-specs" "$TMPDIR/src"

# Create test documents using the template
# (Use Claude to fill the template with realistic content for 3 different features)

# Run validation
./scripts/validate-docs.sh "$TMPDIR/docs" "$TMPDIR/src"
RESULT=$?

# Cleanup
rm -rf "$TMPDIR"
```

### Recipe 2: Cross-Link Chain

Test whether a full document chain (SIG → PRB → ADR → PRD) passes all cross-linking rules.

```bash
# Create a complete chain with proper cross-links
# SIG-99.md → PRB-99.md → ADR-99.md → PRD-99.md
# Run validate-docs.sh
# Count Rule 1, 2, 3 violations
```

### Recipe 3: Malformed Input Detection

Test whether validate-docs.sh catches known violations.

```bash
# Create deliberately broken documents:
# - PRD with no ADR link (should fail Rule 1)
# - ADR with no PRB link (should fail Rule 2)
# - PRB with no raw input link (should fail Rule 3)
# - Source file with no PRD reference (should fail Rule 4)
# - Document with unfilled placeholders (should fail Rule 5)
# Run validate-docs.sh, count how many violations are caught
# Score = violations_caught / violations_planted
```

### Recipe 4: Agent Instruction Compliance

Test whether modified instructions produce better agent behavior.

```bash
# Give Claude a task prompt with the current CLAUDE.md instructions
# Check the output for:
# - Correct branch naming conventions
# - Proper cross-link format
# - Required PR labels mentioned
# - Stage discipline (only one stage per output)
# Score = rules_followed / total_rules
```

## Boundaries

### You MAY modify
- `.templates/*.md` — document templates
- `CLAUDE.md` — agent instructions
- `.agent-rules.md` — agent behavioral rules
- `scripts/validate-docs.sh` — validation logic
- `scripts/ingest-signal.sh` — signal processing

### You MUST NOT modify
- `.github/workflows/*.yml` — workflow files
- `pipeline.yaml` — pipeline configuration
- `agent-orchestrator.yaml` — ao configuration
- `scripts/nightly-cycle.sh` — the nightly cycle itself
- `scripts/collect-metrics.sh` — metrics collection
- `scripts/submit-upstream.sh` — upstream contribution submission
- `.claude/skills/pipeline/SKILL.md` — pipeline management skill
- `.claude/skills/build-plan-generator/` — build plan generation skill
- `.claude/skills/buildplan-review/` — build plan review and certification skill
- `.claude/skills/dispatch/SKILL.md` — dispatch agent
- `.claude/skills/research/SKILL.md` — this file (no self-modification)
- `docs/06-operations/research-strategy.md` — human's strategy
- `docs/00-foundation/*.md` — project vision, brand, personas, constraints (human decision)
- `pipeline-metrics.jsonl` — metrics data

### Safety Rails

- Always create a branch before making changes — never modify main directly
- If you're unsure whether a change is safe, err on the side of discarding
- If validate-docs.sh itself is the artifact being modified, test with BOTH valid and invalid inputs to ensure you haven't introduced false negatives
- Keep changes small and reversible — large rewrites are hard to evaluate
