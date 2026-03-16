# Autonomy Policy

Reference document for Step 8 of the build-plan-generator process.

## Gate Levels

| Level | Who Designs | Who Implements | Who Reviews Before Merge |
|-------|------------|----------------|--------------------------|
| **Human-led** | Human | Agent (from human's design) | Human (must_review) |
| **Must review** | Agent (from blueprint) | Agent | Human (must_review) |
| **Review by summary** | Agent (from blueprint) | Agent | Human reads PR summary only |
| **Auto-merge** | Agent (from blueprint) | Agent | CI validates; human has 24hr window |

## Classification Rules

### Human-led (human designs, agent implements)

- AI/LLM system prompts and prompt engineering
- Conversation flow design (what an AI asks, in what order)
- UX interaction flows (wireframes, user journeys)
- Legal/compliance language (opt-in text, terms, disclaimers)
- Pricing logic and business rules
- Any feature described as "natural language" or "conversational" — requires conversation design

### Must-review (security-critical or architecturally foundational)

- Database schema and migrations
- RLS policies and tenant isolation
- Authentication and authorization middleware
- Core architectural patterns (e.g., workflow-engine/agent-runtime handoff)
- External service credentials and OAuth flows
- Brand/voice enforcement logic
- Data model changes to shared core objects
- Any task touching `auth`, `security`, `rls`, `tenant`, `credential`, or `secret`

### Review-by-summary (medium risk)

- App-specific UI components
- App-specific API endpoints (CRUD for app-owned objects)
- Read-only dashboard queries
- Settings/configuration pages
- Observability/trace tagging
- Non-security test files

### Auto-merge (low risk, CI-verified)

- Type definitions and interfaces — when NOT changing shared contracts
- Linting fixes and formatting
- Documentation files
- Configuration files (non-security)
- Unit test files for isolated functions

## Tagging Rule

Tag every task with the correct `review_tier`. When in doubt, escalate: use `must_review` instead of `review_by_summary`, use `review_by_summary` instead of `auto_merge`.
