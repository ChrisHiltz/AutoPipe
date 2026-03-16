# Output Formats Reference

All output formats used across the build plan review pipeline.

---

## 1. Agent Report Format (Markdown)

Each review agent produces a markdown report with a **parseable scorecard table**. The table format must be machine-readable for downstream synthesis.

### Template

```markdown
# Build Plan Review — Agent {N}

## Executive Summary

{2-3 sentence overall assessment}

## Scorecard

| Category | Score | Key Issue |
|----------|-------|-----------|
| Task Decomposition | 8/10 | WS3-BB2-T1 at 8h, could be split |
| Parallelization Safety | 9/10 | — |
| Dependency Sequencing | 7/10 | Circular ref between T3 and T7 |
| Instruction Clarity | 8/10 | T5 missing output contract |
| Determinism of Setup | 10/10 | — |
| Worktree/Branch/PR | 9/10 | — |
| CI/CD Readiness | 6/10 | No merge gates defined |
| Test Strategy | 7/10 | Missing contract tests for auth boundary |
| Merge-Conflict Risk | 8/10 | package.json touched by 4 tasks, no merge order |
| Human-in-the-Loop | 9/10 | — |
| Secrets/Config/Env | 8/10 | Missing .env.example |
| Data Migration Safety | 10/10 | — |
| Failure Recovery | 7/10 | T9 has no rollback path |
| Observability/Debugging | 8/10 | Error codes not unique |
| One-Pass Likelihood | 7/10 | Two categories at risk |

**Overall: 121/150 → 80.7/100**

## Findings

### Finding 1-1 [blocker]
- **Category:** Dependency Sequencing
- **Location:** WS2-BB1-T3, WS2-BB1-T7
- **Summary:** Circular dependency between auth middleware (T3) and user model (T7). T3 imports user type from T7, T7 imports auth context from T3.
- **Fix:** Extract shared types to a common types task that both depend on.

### Finding 1-2 [warning]
- **Category:** Task Decomposition
- **Location:** WS3-BB2-T1
- **Summary:** Task estimated at 8h, pushing the upper bound. Risk of incomplete PR.
- **Fix:** Split into T1a (API endpoints) and T1b (validation logic).

{...additional findings}
```

### Parsing Rules

- The scorecard table must have exactly 15 rows (one per category).
- Score column format: `{N}/10` where N is an integer 0-10.
- Key Issue column: `—` (em dash) if no issue, otherwise a concise description.
- Overall line format: `**Overall: {sum}/150 → {normalized}/100**`
- Finding IDs: `{agent_number}-{sequence}` (e.g., `1-1`, `1-2`, `2-1`).
- Severity in square brackets: `[blocker]`, `[warning]`, or `[info]`.

---

## 2. Parsed Agent Scores JSON

**Filename:** `agent-{N}-scores.json`

Produced by parsing each agent's markdown report into structured JSON.

### Schema

```json
{
  "agent_number": 1,
  "scores": {
    "task_decomposition": 8,
    "parallelization_safety": 9,
    "dependency_sequencing": 7,
    "instruction_clarity": 8,
    "determinism_of_setup": 10,
    "worktree_branch_pr": 9,
    "cicd_readiness": 6,
    "test_strategy": 7,
    "merge_conflict_risk": 8,
    "human_in_the_loop": 9,
    "secrets_config_env": 8,
    "data_migration_safety": 10,
    "failure_recovery": 7,
    "observability_debugging": 8,
    "one_pass_likelihood": 7
  },
  "overall_score": 81,
  "findings": [
    {
      "id": "1-1",
      "severity": "blocker",
      "category": "dependency_sequencing",
      "fix_location": ["WS2-BB1-T3", "WS2-BB1-T7"],
      "summary": "Circular dependency between auth middleware and user model",
      "fix_suggestion": "Extract shared types to a common types task"
    },
    {
      "id": "1-2",
      "severity": "warning",
      "category": "task_decomposition",
      "fix_location": ["WS3-BB2-T1"],
      "summary": "Task at 8h upper bound, risk of incomplete PR",
      "fix_suggestion": "Split into T1a (API endpoints) and T1b (validation logic)"
    }
  ],
  "parse_warnings": []
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `agent_number` | integer | The agent's assigned number (1-based) |
| `scores` | object | 15 snake_case category keys, integer values 0-10 |
| `overall_score` | integer | Mean of 15 scores, multiplied by 10, rounded to nearest integer |
| `findings` | array | All findings extracted from the agent report |
| `findings[].id` | string | Format: `{agent}-{sequence}` |
| `findings[].severity` | string | One of: `blocker`, `warning`, `info` |
| `findings[].category` | string | Snake_case category key matching `scores` keys |
| `findings[].fix_location` | array | Task IDs or file paths affected |
| `findings[].summary` | string | One-sentence description |
| `findings[].fix_suggestion` | string | Concrete fix action |
| `parse_warnings` | array | Any issues encountered while parsing the markdown |

---

## 3. Audit Synthesis JSON

**Filename:** `audit-synthesis.json`

Produced by combining all agent score files into a single synthesis.

### Schema

```json
{
  "overall_score": 82,
  "agents_reporting": 5,
  "category_scores": {
    "task_decomposition": {
      "median": 9,
      "scores": [8, 9, 9, 10, 9],
      "range": 2,
      "classification": "consensus"
    },
    "parallelization_safety": {
      "median": 8,
      "scores": [7, 8, 8, 9, 8],
      "range": 2,
      "classification": "consensus"
    }
  },
  "fix_targets": [
    {
      "category": "cicd_readiness",
      "median": 7,
      "all_scores": [6, 7, 7, 7, 8],
      "classification": "consensus",
      "agent_findings": [
        {
          "agent": 1,
          "finding_id": "1-5",
          "severity": "warning",
          "summary": "No merge gates defined"
        }
      ],
      "affected_files": ["/.github/workflows/ci.yml", "/package.json"],
      "fix_pattern_key": "add-merge-gates"
    }
  ],
  "deduplicated_findings": [
    {
      "canonical_id": "F-001",
      "severity": "blocker",
      "category": "dependency_sequencing",
      "summary": "Circular dependency between auth middleware and user model",
      "reported_by": [1, 3, 5],
      "agent_finding_ids": ["1-1", "3-2", "5-1"],
      "fix_location": ["WS2-BB1-T3", "WS2-BB1-T7"],
      "fix_suggestion": "Extract shared types to a common types task"
    }
  ],
  "deltas": {},
  "timestamp": "2026-03-16T14:30:00Z"
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `overall_score` | integer | Mean of all 15 category medians, multiplied by 10 |
| `agents_reporting` | integer | Number of agents whose reports were synthesized |
| `category_scores` | object | 15 category keys, each with median, raw scores, range, and classification |
| `category_scores[].median` | number | Median of all agent scores for this category |
| `category_scores[].scores` | array | All agent scores in agent-number order |
| `category_scores[].range` | integer | Max score minus min score |
| `category_scores[].classification` | string | One of: `consensus`, `split`, `outlier` (see Synthesis Method) |
| `fix_targets` | array | Categories scoring below threshold (median < 9), ordered by median ascending |
| `fix_targets[].fix_pattern_key` | string | Key referencing a pattern in fix-patterns.md |
| `deduplicated_findings` | array | Findings merged across agents by similarity |
| `deduplicated_findings[].canonical_id` | string | Format: `F-{NNN}` |
| `deduplicated_findings[].reported_by` | array | Agent numbers that reported this finding |
| `deltas` | object | Score changes from previous audit run (empty on first run) |
| `timestamp` | string | ISO 8601 timestamp of synthesis generation |

---

## 4. Validation Report JSON

**Filename:** `validation-report.json`

Produced by running the validation checklist against the build plan.

### Schema

```json
{
  "gate": "PASS",
  "total_checks": 26,
  "passed": 24,
  "failed": 2,
  "blockers_failed": 0,
  "checks": [
    {
      "check_number": 1,
      "check_name": "all_tasks_have_unique_ids",
      "severity": "blocker",
      "passed": true,
      "detail": "26 tasks, all IDs unique"
    },
    {
      "check_number": 2,
      "check_name": "dag_is_acyclic",
      "severity": "blocker",
      "passed": true,
      "detail": "Topological sort succeeded, no cycles detected"
    },
    {
      "check_number": 15,
      "check_name": "env_vars_have_defaults",
      "severity": "warning",
      "passed": false,
      "detail": "DATABASE_URL and REDIS_URL missing defaults in .env.example"
    }
  ]
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `gate` | string | `PASS` if zero blocker checks failed, `FAIL` otherwise |
| `total_checks` | integer | Total number of checks executed |
| `passed` | integer | Number of checks that passed |
| `failed` | integer | Number of checks that failed |
| `blockers_failed` | integer | Number of blocker-severity checks that failed |
| `checks` | array | All checks in execution order |
| `checks[].check_number` | integer | Sequential check number |
| `checks[].check_name` | string | Snake_case identifier for the check |
| `checks[].severity` | string | One of: `blocker`, `warning`, `info` |
| `checks[].passed` | boolean | Whether the check passed |
| `checks[].detail` | string | Human-readable explanation of the result |

### Gate Logic

- `PASS`: Zero blocker-severity checks failed (warnings and info do not block).
- `FAIL`: One or more blocker-severity checks failed.

---

## 5. Fix Changelog Format

**Filename:** `fix-changelog.md`

Tracks all fixes applied to the build plan during the review cycle.

### Template

```markdown
# Fix Changelog

## Round {N} — {date}

### Fix {round}-{seq}: {short title}
- **Category:** {rubric category}
- **Finding:** {canonical finding ID or agent finding ID}
- **Severity:** blocker | warning | info
- **Before:** {description or snippet of original state}
- **After:** {description or snippet of fixed state}
- **Files Changed:** {list of files modified}
- **Verified:** {how the fix was verified — test pass, lint clean, manual review}
```

---

## 6. Certification Output Format

**Filename:** `certification.md`

Final certification document issued after the plan passes all gates.

### Template

```markdown
# Build Plan Certification

## Plan
- **Name:** {plan name}
- **Version:** {plan version or commit hash}
- **Date:** {certification date}

## Result: {CERTIFIED | NOT CERTIFIED}

## Scores Summary

| Category | Median | Classification |
|----------|--------|----------------|
| Task Decomposition | 9 | consensus |
| ... | ... | ... |

**Overall Score: {score}/100**

## Gate Status
- Validation: {PASS/FAIL}
- Blockers resolved: {count}
- Warnings acknowledged: {count}

## Conditions
{Any conditions or caveats on the certification}

## Reviewers
- Agent 1: {agent description or model}
- Agent 2: ...

## Certification Statement
This build plan has been reviewed by {N} independent agents, scored {score}/100 overall, passed all blocker-level validation checks, and is certified for autonomous execution.
```

---

## 7. Synthesis Method

How individual agent scores are combined into the audit synthesis.

### Score Aggregation

1. **Per-category median:** For each of the 15 categories, take the median of all agent scores. Median is used over mean to resist outlier influence.

2. **Overall score:** Compute the mean of all 15 category medians, then multiply by 10 to produce a score on a 0-100 scale. Round to the nearest integer.

   ```
   overall = round(mean(category_medians) * 10)
   ```

3. **Range:** For each category, compute `max(scores) - min(scores)`.

### Classification Rules

Each category is classified based on the range and distribution of agent scores:

| Classification | Condition |
|----------------|-----------|
| `consensus` | Range <= 2 |
| `split` | Range 3-4, no single outlier (scores distributed across the range) |
| `outlier` | Range >= 3 and exactly one score is 3+ points from the median |

### Fix Target Selection

A category becomes a fix target when:
- Its median score is below 9, OR
- Its classification is `split` or `outlier` (indicating reviewer disagreement regardless of median)

Fix targets are ordered by median ascending (worst first), then by range descending (most disagreement first) as a tiebreaker.

### Finding Deduplication

Findings from multiple agents are deduplicated by:
1. Matching on `category` + `fix_location` overlap (any shared task ID or file path).
2. If locations match, merge into a single canonical finding with all reporting agents listed.
3. Severity takes the highest across merged findings (blocker > warning > info).
4. The canonical summary is taken from the agent with the most detailed description.
5. Each canonical finding gets a sequential ID: `F-001`, `F-002`, etc.
