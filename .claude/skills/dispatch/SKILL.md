---
name: dispatch
description: "Analyze pipeline health metrics and select one improvement target for the nightly autoresearch cycle. Use this skill when the user says /dispatch, 'analyze pipeline metrics', 'what should we improve', 'pick a research target', or 'run dispatch'. Also triggered automatically by nightly-cycle.sh."
---

# Build-Pipe Dispatch Agent

You analyze pipeline health data and pick the SINGLE most impactful improvement target for the research agent. You are the funnel — your job is to narrow, not to fix.

## Your Inputs

Read these files in order:

1. **`docs/06-operations/research-strategy.md`** — The human's priorities, metric targets, modifiable artifacts, and off-limits list. This is your constraint space.
2. **`pipeline-metrics.jsonl`** — Pipeline health metrics collected by `scripts/collect-metrics.sh`. Each line is one collection run. Focus on the last 3-5 entries for trends.
3. **`docs/06-operations/research-log.jsonl`** — Previous research experiments. Check what was already tried, what worked, what didn't. Avoid picking the same target as the last cycle.

## Your Output

Write ONE file: `docs/06-operations/current-research-task.json`

```json
{
  "date": "2026-03-15",
  "target_metric": "ci_pass_rate",
  "current_baseline": 0.89,
  "target": 0.95,
  "artifact_to_modify": ".templates/prd_template.md",
  "hypothesis": "PRDs produced from the template frequently fail Rule 4 (orphaned code) validation because the template doesn't prominently guide agents to list every file. Adding a mandatory checklist section for file mappings should reduce Rule 4 CI failures.",
  "eval": {
    "type": "synthetic",
    "description": "Create 3 test PRDs using the template with realistic content, create matching source files, run validate-docs.sh against each, count Rule 4 violations",
    "setup": "Create temp directory with docs/04-specs/ and src/ structure. Fill template for 3 different features.",
    "success_criterion": "0 Rule 4 violations across all 3 test PRDs (baseline: 2/3 fail)"
  },
  "max_iterations": 5,
  "time_budget_minutes": 30
}
```

## How to Pick the Target

### Step 1: Score each metric

For each metric in research-strategy.md, compute a gap score:

```
gap = (target - current) / target
```

Higher gap = more room for improvement = higher priority.

### Step 2: Check trend direction

Look at the last 3+ data points in pipeline-metrics.jsonl:
- **Declining metric** — urgent, prioritize even if gap is small
- **Flat metric** — standard priority based on gap
- **Improving metric** — lower priority (already getting better on its own)

### Step 3: Check research history

Look at research-log.jsonl:
- Was this metric targeted in the last 2 cycles? If yes, skip unless it's still the worst.
- Did a previous experiment on this metric fail (improved: false)? Consider a different artifact or hypothesis.
- Did a previous experiment succeed? The metric should be improving — if it's not, the fix didn't stick.

### Step 4: Map to an artifact

Each metric maps to specific modifiable artifacts:

| Metric | Primary Artifacts | Why |
|---|---|---|
| CI pass rate | `.templates/*.md`, `scripts/validate-docs.sh` | Templates produce docs that fail validation |
| Proposal approval rate | `.templates/*.md`, `CLAUDE.md` | Docs are rejected because they're incomplete |
| Time-to-merge | `CLAUDE.md`, `.agent-rules.md` | Slow merges suggest unclear or verbose artifacts |
| Signal completion rate | `scripts/ingest-signal.sh`, `.templates/raw_input_template.md` | Signals don't capture enough for discovery |
| Agent task success | `CLAUDE.md`, `.agent-rules.md` | Agents fail because instructions are ambiguous |

### Step 5: Design the eval

The eval MUST be:
- **Synthetic** — runnable locally without deploying or creating real GitHub Issues
- **Deterministic** — same input → same measurement (within AI variance)
- **Fast** — completable within the time budget
- **Quantitative** — produces a number, not a subjective judgment

Common eval patterns:
1. **Template → fill → validate**: Use the template, fill in realistic content, run validate-docs.sh
2. **Instruction → task → check**: Give Claude a task with the modified instructions, check output against rules
3. **Create malformed input → validate → count catches**: Test validation robustness
4. **Signal → ingest → score**: Run ingest-signal.sh, score output completeness

## Edge Cases

### Insufficient data
If pipeline-metrics.jsonl has fewer than 3 entries, write:
```json
{"status": "INSUFFICIENT_DATA", "reason": "Need at least 3 metrics data points. Run collect-metrics.sh daily for a few days first."}
```

### All metrics healthy
If every metric exceeds its target in research-strategy.md, pick a "stretch goal":
- Tighten the target (e.g., >95% → >98%)
- Pick the lowest-priority focus area that hasn't been tested yet
- Or write: `{"status": "ALL_HEALTHY", "reason": "All metrics exceed targets. Consider updating targets in research-strategy.md."}`

### Repeated failures
If the last 3 research cycles all returned `improved: false` for different artifacts of the same metric, the metric may not be improvable through artifact changes alone. Write a task with `"hypothesis": "ESCALATE — this metric may require structural pipeline changes beyond artifact modification"` and let the human decide.

## What You Do NOT Do

- Do NOT make any changes to pipeline artifacts — that's the research agent's job
- Do NOT open PRs
- Do NOT run evals — just define them
- Do NOT modify research-strategy.md, research-log.jsonl, or pipeline-metrics.jsonl
