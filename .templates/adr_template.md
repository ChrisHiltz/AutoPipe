# Architecture: [Short Title]
**ID:** ADR-[Issue-Number]
**Solves Problem:** [Link to PRB-xxx.md]

## 1. Context
[What is the technical context of this feature?
What does the system look like today? What constraints exist?
Reference stack.yaml for mandated technology choices.]

## 2. Existing Codebase
**Codebase state:** [Greenfield | Active development | Mature]

**Modules examined:**
- `path/to/module/` — [why examined, what was found]

**Relevant interfaces this decision must work with:**
- `path/to/file` — [interface description, e.g. "exports createUser(), updateUser()"]

**Patterns this decision must follow:**
- [e.g., "All API routes use FastAPI router in src/backend/api/"]

**Naming conventions observed:**
- [e.g., "snake_case for Python, camelCase for TypeScript"]

## 3. Decision
[What are we building? Describe the technical approach.
Be specific: name the components, APIs, data models involved.
If multiple approaches were considered, briefly explain why this one was chosen.]

## 4. Dependencies & Risks
- **Database:** [Any schema changes needed? New tables, columns, migrations?]
- **Third Party:** [Are we calling external APIs? What are the rate limits/costs?]
- **Security:** [Does this risk PII leakage? Authentication implications?]
- **Performance:** [Expected load? Latency requirements?]

## 5. Local Development Impact
[How does this architecture decision affect the local dev experience?
Reference stack.yaml `local_dev` for the project's strategy.]

- **New services:** [New processes a developer must run locally? e.g., "Adds Redis — add to docker-compose"]
- **New environment variables:** [List any new env vars. Each must be added to .env.example]
- **Seed data:** [Data dependencies? How is dev/test data provisioned?]
- **Bootstrap changes:** [Does the bootstrap command need updating?]
- **Offline capability:** [Works without network access to external services? If not, what's the local fallback?]

## 6. Consequences
[What becomes harder because we made this decision?
Every architecture decision has trade-offs. Name them explicitly.
e.g., "Choosing X means we can't easily support Y later."]

## 7. Interface Contract
[Define the public API or interface this architecture exposes.
Other components will depend on this contract.
e.g., endpoint signatures, function interfaces, event schemas.]
