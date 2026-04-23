---
name: adr
description: >
  Create, update, and manage Architecture Decision Records (ADRs). Use whenever
  the user mentions "ADR", "architecture decision", "decision record", "design decision",
  "document this decision", or asks to record why a technical choice was made. Also trigger
  when the user says things like "why did we pick X over Y" and wants to formalize that
  reasoning. Works for any client engagement — not project-specific.
version: 1.0.0
updated: 2026-04-23
---

# Architecture Decision Records

ADRs capture the context, decision, and consequences of significant architecture choices.
They are essential in consulting — decisions outlive your engagement, and the next person
needs to understand *why*, not just *what*.

## When to Create an ADR

Create an ADR when a decision:
- Affects system structure or data flow
- Involves choosing between viable alternatives
- Has compliance or security implications
- Would be hard to reverse later
- Keeps coming up in discussion (a sign it needs to be settled and documented)

## ADR Format

Use this template exactly. The numbering is sequential within the project's `docs/adr/` directory.

```markdown
# ADR-NNNN: [Short Decision Title]

**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-NNNN
**Date:** YYYY-MM-DD
**Deciders:** [Names/roles of people involved]

## Context

What is the issue or situation that motivates this decision? Include relevant
constraints (technical, regulatory, organizational, timeline).

## Decision

What is the change that we're proposing and/or doing?
State it clearly and directly: "We will use X" or "We will adopt Y approach."

## Alternatives Considered

### Alternative A: [Name]
- **Pros:** ...
- **Cons:** ...

### Alternative B: [Name]
- **Pros:** ...
- **Cons:** ...

(Include at least 2 alternatives. If there's only one realistic option, explain why.)

## Consequences

### Positive
- What becomes easier or better?

### Negative
- What becomes harder? What do we give up?

### Risks
- What could go wrong? What assumptions might not hold?

## Compliance Notes

(Only include if relevant. Flag GDPR, NIS2, DS 484, ISO 27001, or sector-specific
regulation implications.)

## References

- Links to relevant documentation, RFCs, vendor docs, or prior ADRs
```

## Domain-Specific ADR Guidance

The base template above applies to all ADRs. But the *content* of the Context,
Alternatives, and Consequences sections should reflect the domain of the decision.

**Domain resolution order:**

1. **Repo AGENTS.md** (preferred) — look for `platform:` and `repo_type:` declarations.
   A Terraform repo means infrastructure ADRs. A Databricks repo means data platform ADRs.
   Use the declared domain directly.
2. **User's description** (fallback) — if no repo context, infer from what the user is
   describing (e.g., "should we use SCD2 or SCD1" → data modeling domain).
3. **Ask** — if ambiguous, ask: "Is this an infrastructure, data modeling, orchestration,
   or CI/CD decision?"

When the domain is clear, include the relevant domain-specific prompts below.

### Terraform / Infrastructure Decisions

When the decision involves IaC, cloud resources, networking, or deployment topology:

- **Context should include:** target cloud provider(s), existing infrastructure baseline,
  environment strategy (dev/test/prod), current IaC tooling, team Terraform experience level
- **Alternatives should compare:** provider-managed vs. self-managed services, module
  structure options, state backend choices, authentication patterns (service principal vs.
  managed identity vs. workload identity)
- **Consequences should address:** blast radius of changes, state migration requirements,
  CI/CD pipeline impact, cost implications across environments, provider lock-in degree
- **Compliance notes:** data residency (which Azure/GCP region and why), network isolation
  requirements, key/secret management approach

**Example decision titles:** "Use Azure Storage for Terraform remote state",
"Adopt microsoft/fabric provider for workspace provisioning",
"Use GCS bucket for Terraform remote state on GCP"

### Kimball / Data Modeling Decisions

When the decision involves dimensional modeling, data warehouse design, or data platform choices:

- **Context should include:** business process being modeled, source system(s), grain
  definition, query patterns and consumers (BI tool, API, ML pipeline), data volumes
- **Alternatives should compare:** modeling approaches (Kimball vs. Data Vault vs. flat),
  SCD strategies per attribute, fact table types (transaction vs. periodic snapshot),
  storage formats (Delta, Parquet)
- **Consequences should address:** query performance impact, historical analysis capability,
  ETL/ELT complexity, downstream semantic model / Power BI compatibility, reprocessing cost
- **Compliance notes:** PII handling in dimensions (pseudonymization, right to erasure),
  data retention periods, cross-border data movement

**Example decision titles:** "Use SCD Type 2 for customer address tracking",
"Use Delta Lake over Parquet for the curated layer",
"Implement bridge table for many-to-many customer-segment relationship"

### Azure DevOps / CI/CD Decisions

When the decision involves pipelines, branching strategy, or deployment automation:

- **Context should include:** current CI/CD setup, team size and workflow, repository
  structure (mono vs. multi-repo), approval and governance requirements
- **Alternatives should compare:** pipeline tools (ADO YAML vs. GitHub Actions vs. GitLab CI),
  branching models (trunk-based vs. Gitflow), deployment strategies (per-environment
  pipelines vs. single pipeline with stages), artifact management
- **Consequences should address:** feedback loop speed, approval gate complexity, secret
  management, pipeline maintainability, developer experience
- **Compliance notes:** separation of duties (who can approve production deployments),
  audit logging, change management traceability

**Example decision titles:** "Use YAML pipelines with template reuse over Classic pipelines",
"Adopt trunk-based development with short-lived feature branches",
"Implement environment-specific variable groups linked to Key Vault"

### Cross-Domain Decisions

Some decisions span multiple domains (e.g., "how should we implement SCD2 in Fabric
with Terraform-managed infrastructure"). In these cases, merge the relevant
prompts from each domain into a single ADR. The template structure stays the same — just
make sure Context and Consequences cover all affected domains.

## File Naming & Location

- Store ADRs in `docs/adr/` relative to the project root
- File naming: `NNNN-short-kebab-title.md` (e.g. `0001-use-delta-lake-for-curated-layer.md`)
- Number sequentially starting from 0001
- Check existing ADRs before creating a new one to avoid duplicates or conflicts

## Creating an ADR — Step by Step

1. Check `docs/adr/` for existing ADRs. Determine the next sequence number.
2. Ask the user for the decision context if not already clear from conversation.
3. Draft the ADR using the template above.
4. Present the draft for review before writing the file.
5. Save to `docs/adr/NNNN-short-kebab-title.md`.

## Updating an ADR

- Never delete an ADR. To reverse a decision, create a new ADR that supersedes it.
- Update the old ADR's status to `Superseded by ADR-NNNN`.
- Link between the old and new ADR in both directions.

## Tips for Good ADRs

- Write for the person who joins the project 6 months from now
- Be specific about constraints — "we had 3 weeks" matters as much as "we needed GDPR compliance"
- Don't oversell the chosen option. Honest trade-offs build trust.
- Keep it concise — one to two pages max. If you need more, the decision might be too big.
