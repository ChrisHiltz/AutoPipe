---
name: pipeline
description: "Check pipeline status, dispatch work, validate build plans, or initialize new build plans. Works in both steady-state and execution modes. Use this skill when the user says /pipeline, 'pipeline status', 'what's next', 'dispatch tasks', 'validate build plan', 'init build plan', 'kick the pipeline', or any request to inspect or advance the pipeline."
---

# Build-Pipe Pipeline Manager

You provide visibility into pipeline state and manual control over pipeline advancement. You work across both steady-state and execution modes.

## Routing

Determine the user's intent from their prompt:

| User Says | Sub-Command |
|-----------|-------------|
| "status", "progress", "what's done", "what's next", "how's the pipeline" | **Status** |
| "dispatch", "run next", "kick", "advance", "start", "go" | **Kick** |
| "validate", "check build plan", "lint plan" | **Validate** |
| "init", "initialize", "scaffold", "create build plan" | **Init** |
| No clear intent | Run **Status** first, then ask what they want to do |

## Prerequisites

1. Read `pipeline.yaml` to determine the current mode (`steady-state`, `execution`, or `discovery`)
2. Read `.agent-rules.md` for pipeline rules

---

## Sub-Command: Status

Show the current pipeline state. Works in both modes.

### Process

1. **Read `pipeline.yaml`** — report the current mode
2. **If steady-state mode:**
   - Run: `gh issue list --label "pipeline:agent-task" --state open --json number,title,labels,createdAt`
   - Run: `gh pr list --label "pipeline:proposal" --state open --json number,title,labels,createdAt`
   - Run: `gh pr list --label "pipeline:task" --state open --json number,title,labels,createdAt`
   - Report: open agent tasks (dispatched work), open proposals (awaiting review), in-flight code PRs
   - If nothing is open: "Pipeline is idle — no work in progress."
3. **If execution mode:**
   - Run: `./scripts/read-build-plan.sh list`
   - Count: done, pending, blocked, ready tasks
   - Show progress percentage
   - Run: `./scripts/read-build-plan.sh next-batch` to show what's ready to dispatch
   - Check for in-flight work: `gh pr list --label "pipeline:task" --state open`
   - Check for dispatched work: `gh issue list --label "pipeline:agent-task" --state open`
4. **Check for pipeline:errata issues:** `gh issue list --label "pipeline:errata" --state open`
   - If any exist, warn: "There are {N} errata issues flagging ADR inaccuracies"

### Output Format

```
Pipeline Mode: {mode}
Status: {idle | active | blocked}

{mode-specific details}

Errata: {N open issues} (if any)
```

---

## Sub-Command: Kick

Manually trigger the next pipeline stage. Works in both modes.

### Process

1. **Determine what to kick:**
   - In steady-state: Check if there are merged docs that haven't triggered the orchestrator
   - In execution: Run `./scripts/read-build-plan.sh next` to find the next available task
2. **Show what will happen** — describe the action before executing
3. **Get user confirmation** via AskUserQuestion: "This will dispatch {description}. Proceed?"
4. **Execute:**
   - Steady-state: `gh workflow run pipeline-orchestrate.yml`
   - Execution with specific task: `gh workflow run pipeline-orchestrate.yml -f task_id="{TASK_ID}" -f mode_override="execution"`
   - Execution batch: For each ready task, trigger the workflow
5. **Report result** — show the workflow run URL or any errors

### Error Handling

- If `gh workflow run` fails with 403: "Workflow dispatch failed — check that the workflow exists and your token has `actions:write` permission. Exact error: {error}"
- If no tasks are available: "No tasks ready to dispatch. Run `/pipeline status` to see what's blocked."
- Do not retry automatically on failure.

---

## Sub-Command: Validate

Check build plan health. Execution mode only.

### Process

1. **Check mode** — if not execution mode, warn: "Pipeline is in {mode} mode. Validate is for execution mode build plans. Continue anyway?"
2. **Check directory** — verify `build-plan/` exists. If not: "No build-plan/ directory found. Run `/pipeline init` to create one, or `/build-plan-generator` to generate a plan."
3. **Run structural validation:**
   - `python scripts/validate_plan.py build-plan/` (if the script exists)
   - `./scripts/read-build-plan.sh list` to verify all tasks are parseable
4. **Check dependencies:**
   - For each task, run `./scripts/read-build-plan.sh check-deps {TASK_ID}`
   - Report any circular dependencies or dangling references
5. **Report:** Total tasks, tasks per workstream, dependency graph health, any structural issues

### Error Handling

- If `validate_plan.py` reports circular dependencies: list the cycle and stop. Do not attempt to auto-fix.
- If task files have malformed YAML: report which files and what's wrong.

---

## Sub-Command: Init

Create the build plan directory structure. Execution mode only.

### Process

1. **Check if `build-plan/` exists** — if yes, warn and confirm overwrite
2. **Create directory structure:**
   ```
   build-plan/
   └── workstreams/
   ```
3. **Initialize `.pipeline-status.json`** as `{}`
4. **Suggest next steps:**
   - "Build plan directory created. Next steps:"
   - "1. Run `/build-plan-generator` to generate a build plan from a blueprint"
   - "2. Or manually create task files in `build-plan/workstreams/*/tasks/`"
   - "3. After creating the plan, run `/buildplan-review` to certify it for autonomous execution"

---

## What You Do NOT Do

- Do NOT modify pipeline documents (signals, PRBs, ADRs, PRDs) — that's the pipeline agents' job
- Do NOT modify build plan task files — that's the generator's and reviewer's job
- Do NOT modify `pipeline.yaml` — that's a human decision
- Do NOT push code or create PRs — you only dispatch and inspect
- Do NOT retry failed workflow dispatches automatically — report the error and stop
