# Pipeline Research Strategy

This file steers the nightly self-improvement cycle. The dispatch agent reads it
to know what to focus on, what's off-limits, and what success looks like.

Edit this file to change the system's priorities. The AI iterates on pipeline
artifacts; you iterate on this strategy.

---

## Focus Areas (ranked by priority)

1. **CI pass rate** — Templates and agent instructions should produce docs/code that
   pass validation on first attempt. Every CI failure costs time and tokens.

2. **Template quality** — Templates should guide agents to produce complete,
   well-linked documents without missing sections or broken cross-references.

3. **Validation coverage** — `validate-docs.sh` should catch all real violations
   without false positives. A missed violation means bad docs reach main.

4. **Agent instruction clarity** — `CLAUDE.md` and `.agent-rules.md` should be
   unambiguous. Agents shouldn't need multiple attempts to follow the rules correctly.

5. **Signal processing quality** — Ingested signals should capture enough context
   from the original GitHub Issue for effective discovery work downstream.

---

## Metric Targets

| Metric | Target | How It's Measured |
|---|---|---|
| CI pass rate | >95% | `ci.pass_rate` in pipeline-metrics.jsonl |
| Proposal approval rate | >85% | `proposals.merged / proposals.total` |
| Time-to-merge (proposals) | <8 hours | `time_to_merge.proposals_hours` |
| Signal completion rate | >80% | `signals.completed_pipeline / signals.created` |
| Agent task success rate | >90% | `tasks.completed / tasks.dispatched` |

The "Current" column is filled by the dispatch agent from live metrics data.

---

## Modifiable Artifacts

The research agent MAY modify these files during experiments:

- `.templates/raw_input_template.md` — signal ingestion template
- `.templates/discovery_template.md` — PRB (discovery) template
- `.templates/adr_template.md` — ADR (architecture) template
- `.templates/prd_template.md` — PRD (specification) template
- `CLAUDE.md` — agent pipeline instructions
- `.agent-rules.md` — the 7 mandatory agent rules
- `scripts/validate-docs.sh` — document validation logic
- `scripts/ingest-signal.sh` — signal processing script

---

## Off-Limits

The research agent MUST NOT modify these files:

- `.github/workflows/*.yml` — workflow triggers, permissions, job structure
- `pipeline.yaml` — pipeline mode and configuration (human decision)
- `agent-orchestrator.yaml` — Agent Orchestrator configuration
- `stack.yaml` — technology constraints (human decision)
- `docs/00-foundation/*.md` — project vision, brand, personas, constraints (human decision)
- `scripts/nightly-cycle.sh` — the research system orchestrator
- `scripts/collect-metrics.sh` — metrics collection
- `scripts/poll-and-spawn.sh` — agent dispatch bridge
- `scripts/submit-upstream.sh` — upstream contribution submission
- `.claude/skills/dispatch/SKILL.md` — dispatch agent instructions
- `.claude/skills/research/SKILL.md` — research agent instructions
- `.claude/skills/pipeline/SKILL.md` — pipeline management skill
- `.claude/skills/build-plan-generator/` — build plan generation skill
- `.claude/skills/buildplan-review/` — build plan review and certification skill
- `docs/06-operations/research-strategy.md` — this file
- `pipeline-metrics.jsonl` — metrics data (append-only by collect-metrics.sh)

---

## Eval Requirements

Every experiment MUST:

1. Define a measurable baseline before making changes
2. Run at least 3 synthetic test cases per iteration
3. Compare results quantitatively (not "it looks better")
4. Be revertable — use `git checkout` if no improvement
5. Log results to `research-log.jsonl` regardless of outcome
6. Attempt ALL iterations specified by `max_iterations` (minimum 3). Early
   termination is only permitted when the target metric is reached or the
   time budget is exceeded

---

## Notes

- The nightly cycle runs one experiment per night. Patience is part of the design.
- After ~30 cycles, review `research-log.jsonl` to see what's working and adjust
  priorities above accordingly.
- If a metric plateaus despite multiple experiments, it may need structural changes
  beyond what artifact modification can achieve. The dispatch agent will flag this
  as an ESCALATE case for you to review.
- When `template.upstream_repo` is set in `pipeline.yaml`, successful research
  experiments are automatically submitted as cross-fork PRs to the upstream
  template repo. Only upstream-relevant files are included via cherry-pick in
  an isolated worktree — no project files leak. This is best-effort; failures
  do not affect the local research cycle.
