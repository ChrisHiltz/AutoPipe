# Decomposition Rules

Reference document for Steps 4-6 of the build-plan-generator process.

## Hierarchy

```
Blueprint
  └── Workstream (major functional area)
        └── Build Block (developer-week chunk)
              └── Agent Task (vertical slice, one PR)
```

## Workstream Rules

- A workstream is a major functional area of the blueprint (e.g., "Shared Core Foundation", "Pipeline & Communication", "Onboarding & Knowledge")
- Each blueprint should produce 4-8 workstreams
- Workstreams align with the blueprint's build phases when possible, but may not be 1:1
- Each workstream has explicit scope boundaries: what's IN, what's OUT
- Workstreams have dependencies on other workstreams (not circular)
- A "fence point" is a workstream boundary where ALL tasks in the preceding workstream must complete before the next workstream begins
- Not all workstream transitions are fence points — some workstreams can overlap if their dependencies are at the build-block level, not workstream level

## Build Block Rules

- A build block is a coherent chunk of work within a workstream (~3-7 days)
- Each workstream has 2-5 build blocks
- Build blocks are named descriptively: `auth-and-rls`, `onboarding-graph`, `approval-queue`
- Build blocks within the same workstream may run in parallel IF they are in different lanes AND share no files
- Each build block has a clear "definition of done" that can be verified without running the full system

## Agent Task Rules

- An agent task is a vertical slice that produces exactly one PR
- Each build block has 2-4 agent tasks
- Estimated time: 2-8 hours
- Touches files in at most 2 directories
- MUST be a vertical slice (feature path from data to API to test), NOT a horizontal layer (all schemas, or all endpoints)
- Has explicit acceptance criteria (3-7 items, testable)
- Has explicit `depends_on` with coded reasons (shared file, shared data model, shared API, shared function, pattern reference)
- Has a `lane` assignment (backend, frontend, integrations)
- Has a `review_tier` (must_review, review_by_summary, auto_merge)
- Has `blueprint_refs` citing source sections
- Includes product truths context

## Sizing Validation

| Metric | Minimum | Maximum | If Violated |
|--------|---------|---------|-------------|
| Workstreams per blueprint | 4 | 8 | Re-examine scope grouping |
| Build blocks per workstream | 2 | 5 | Merge if <2; split if >5 |
| Tasks per build block | 2 | 4 | Merge if <2; split if >4 |
| Hours per task | 2 | 8 | Merge if <2; split if >8 |
| Total tasks for 1000-2000 line blueprint | 30 | 60 | If >60, consolidate aggressively |
| Directories touched per task | 1 | 2 | If 3+, split into vertical slices |
| Acceptance criteria per task | 3 | 7 | If <3, under-specified; if >7, over-scoped |

## What Must NEVER Be Grouped Together

- Schema migrations + application code
- Auth/RLS policies + feature code
- AI/LLM prompt content + graph/agent structure code
- Two different apps' UI in the same task
- Contract definitions + contract consumers

## What Must Be Sequential

- All database migrations (one at a time, merged before next starts)
- Schema → API endpoints → UI (within a vertical slice)
- Reference implementation (Phase 0) → all tasks that reference its patterns
- Contract artifacts → all dependent tasks

## What Can Be Parallel (Across Lanes)

- Backend tasks for different app domains (when shared middleware is stable)
- Frontend app views for different apps (when shared components are stable)
- Different integration setups (email, SMS, observability)
- Tests for independent modules

## Lane Definitions

| Lane | Scope | Files Owned |
|------|-------|-------------|
| Backend | FastAPI, Supabase, Inngest, LangGraph | `backend/`, `supabase/`, `inngest/` |
| Frontend | Next.js, React components, design system | `frontend/`, `app/` |
| Integrations | External service connectors, webhooks | `integrations/`, config files |

Within a lane, tasks are sequential. Across lanes, tasks can run in parallel. Cross-lane dependencies are mediated by contract artifacts (OpenAPI spec, TypeScript types generated from Pydantic models).

**Max concurrent agents: 3** (one per lane). Going higher creates merge conflict storms in a modular monolith.
