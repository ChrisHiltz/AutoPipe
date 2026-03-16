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

## 4. Testing Requirements
[Name the exact test files that must be created or updated.]
- Backend: `tests/backend/test_[feature].py`
- Frontend: `tests/frontend/[feature].test.ts`
- E2E: `tests/e2e/[feature].spec.ts` (if applicable)

## 5. Files to Create/Modify
[List the source files this spec will produce or change.]
- `src/backend/[path]`
- `src/frontend/[path]`
