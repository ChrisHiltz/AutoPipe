# Specification: [Short Title]
**ID:** PRD-[Issue-Number]
**Implements Architecture:** [Link to ADR-xxx.md]

## 1. Pre-requisites
[Required environment variables, configurations, or prior tasks that must be complete.
e.g., "Requires SUPABASE_URL and SUPABASE_KEY in .env"]

## 2. Acceptance Criteria (Booleans)
[Each criterion must be independently testable. Write them as pass/fail checks.]
- [ ] Criteria 1: [e.g., "POST /api/leads returns 201 with valid payload"]
- [ ] Criteria 2: [e.g., "Invalid email returns 400 with error message"]
- [ ] Criteria 3: [e.g., "Lead appears in Supabase leads table after creation"]
- [ ] Criteria 4: [e.g., "UI displays success toast after lead creation"]

## 3. Scope Boundaries
**In scope:**
- [Exactly what this task builds]

**Out of scope:**
- [What this task explicitly does NOT build — prevents scope creep]

## 4. Local Development Requirements
[Every feature must be runnable locally. Reference stack.yaml `local_dev` for the project's strategy.]

- [ ] Bootstrap: `{bootstrap_command from stack.yaml}` starts all services needed for this feature
- [ ] Environment: All new env vars documented in `.env.example` with non-secret defaults
- [ ] Seed data: Dev seed data covers this feature's happy path
- [ ] Isolation: Feature works without network access to production/staging services
- [ ] Verification: Developer can manually verify this feature works locally before pushing

## 5. Testing Requirements
[Name the exact test files that must be created or updated.]
- Backend: `tests/backend/test_[feature].py`
- Frontend: `tests/frontend/[feature].test.ts`
- E2E: `tests/e2e/[feature].spec.ts` (if applicable)

## 6. Files to Create/Modify

**Codebase verification:** [Confirm you read CODEBASE-MAP.md and verified the ADR's Existing Codebase section. Note any discrepancies.]

**Create:**
- `src/backend/[path]` — [purpose]

**Modify:**
- `src/backend/[existing-path]` — [what changes and why]

**Existing patterns to follow:**
- [e.g., "Tests mirror src/ structure under tests/"]

## 7. Codebase Discrepancies (if any)
[If the ADR's "Existing Codebase" section contains errors you discovered during your own
exploration, document them here. This flags issues for the human reviewer before code
implementation begins. If no discrepancies found, write "None — ADR codebase analysis verified."]
