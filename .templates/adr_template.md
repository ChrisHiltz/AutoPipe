# Architecture: [Short Title]
**ID:** ADR-[Issue-Number]
**Solves Problem:** [Link to PRB-xxx.md]

## 1. Context
[What is the technical context of this feature?
What does the system look like today? What constraints exist?
Reference stack.yaml for mandated technology choices.]

## 2. Decision
[What are we building? Describe the technical approach.
Be specific: name the components, APIs, data models involved.
If multiple approaches were considered, briefly explain why this one was chosen.]

## 3. Dependencies & Risks
- **Database:** [Any schema changes needed? New tables, columns, migrations?]
- **Third Party:** [Are we calling external APIs? What are the rate limits/costs?]
- **Security:** [Does this risk PII leakage? Authentication implications?]
- **Performance:** [Expected load? Latency requirements?]

## 4. Consequences
[What becomes harder because we made this decision?
Every architecture decision has trade-offs. Name them explicitly.
e.g., "Choosing X means we can't easily support Y later."]

## 5. Interface Contract
[Define the public API or interface this architecture exposes.
Other components will depend on this contract.
e.g., endpoint signatures, function interfaces, event schemas.]
