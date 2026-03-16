# Project Constraints

Architectural and business constraints that agents must respect when making decisions.
Architecture documents (ADRs) reference this file for compliance, performance, and security requirements.

---

## Business Rules

[Rules that affect implementation. These prevent agents from building features that violate business logic.]

- [Example: "Free tier limited to 3 active projects and 1GB storage"]
- [Example: "All client-facing emails must include an unsubscribe link"]
- [Example: "Pricing changes require 30-day advance notice to existing customers"]

## Compliance & Regulatory

[Legal or regulatory requirements. If none apply yet, say so — agents need to know either way.]

- [Example: "GDPR — user data must be deletable within 30 days of request"]
- [Example: "SOC 2 Type II — audit logging required for all data access"]
- [Example: "None currently — revisit when we process payments or store PII"]

## Performance Budgets

[Quantitative targets that architecture decisions must respect.]

- [Example: "Page load < 2 seconds on 3G connection"]
- [Example: "API response < 200ms at p95"]
- [Example: "Bundle size < 250KB gzipped for initial load"]
- [Or: "No specific targets yet — optimize as issues arise"]

## Security Requirements

[Security baseline for the project.]

- [Example: "All PII encrypted at rest (AES-256) and in transit (TLS 1.3)"]
- [Example: "Authentication required for all API endpoints except /health"]
- [Example: "No third-party analytics scripts without explicit user consent"]
- [Or: "Standard web security practices — OWASP top 10 awareness"]

## Known Tech Debt

[Existing issues that affect new work. Update as debt is created or resolved.]

- [Example: "Auth system uses session cookies — migration to JWT planned for Q3"]
- [Example: "Database has no indexes on frequently-queried columns — causes slow list views"]
- [Or: "Greenfield project — no tech debt yet"]
