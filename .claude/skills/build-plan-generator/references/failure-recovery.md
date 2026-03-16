# Failure Recovery Model

Reference document for Step 9 of the build-plan-generator process.

## Recovery Table

| Failure Type | Detection | Automated Recovery | Escalation |
|-------------|-----------|-------------------|------------|
| CI failure | CI pipeline red | Orchestrator feeds error log to agent. Max 2 retries. | Block task, notify human. |
| Schema collision | Migration ordering check | Reject PR. Agent rebases on latest main. | Human resolves. |
| Contract drift | TypeScript compile from OpenAPI spec | Regenerate types from updated spec. | Human reviews if spec changed semantically. |
| Merge conflict | Git detection | Later-lane agent rebases. | Human resolves if in shared code. |
| Under-specified task | Agent reports NEEDS_CONTEXT | Return to planning. Add implementation brief. | Human writes brief. |
| Over-scoped task | Agent exceeds 2x estimated hours | Split into sub-tasks. Re-plan. | Human approves split. |
| Product intent miss | Product intent test fails OR human catches | Reject PR. Provide blueprint ref + product truths. | Human clarifies intent. |
| Hidden dependency | Integration test failure | Add dependency to DAG. Block dependent tasks. | Human reviews new dependency. |
| Architecture violation | Architecture-guard flags | Reject PR. Agent re-implements. | Human reviews if pattern is wrong. |
| Blueprint gap | Agent cannot determine what to build | Document in RISKS.md. Mark task blocked. | Human fills gap. |

## Re-Planning Triggers

Re-plan the affected DAG subtree (NOT the entire plan) when:

1. A contract artifact changes (schema, API spec, type definitions)
2. A task is split into sub-tasks
3. A hidden dependency is discovered
4. A human gate changes the approach
5. 3+ tasks in the same workstream fail
