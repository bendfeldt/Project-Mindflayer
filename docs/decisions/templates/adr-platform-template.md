# ADR-NNNN: <Short Title>

**Status:** Proposed | Accepted | Superseded | Deprecated
**Date:** YYYY-MM-DD
**Deciders:** <names>
**Supersedes:** <ADR-XXXX> (optional)
**Superseded-by:** <ADR-XXXX> (optional)

**Scope:** <Platform name(s) — e.g. "Terraform on Azure", "Databricks /
Unity Catalog", "Cross-cutting (any stack)">

<!--
  This template is for **Platform ADRs** at docs/decisions/platform/.
  Platform ADRs describe generic best practice for a stack and must
  apply to any engagement on that stack.

  HARD RULES (see ADR-0015):
  - No client / company / project names.
  - No engagement-specific repository names or paths.
  - No "this repo" / "this engagement" framing.
  - Examples must be illustrative placeholders, not references to a
    real codebase.

  If your decision violates any of these, write it as a Client-Repo ADR
  using adr-client-template.md instead.
-->

## Context

Describe the problem space and the forces that motivated a decision.
State the question being answered. Stay stack-level — no specific
engagement, no specific repo. Two to four short paragraphs.

## General Principle

The universal intent, expressed as stack-agnostically as the topic
allows. This is the part another consultant could carry to a different
engagement on the same stack and apply unchanged.

One paragraph, sometimes a short bullet list. If the principle truly
cannot be stated independently of a specific technology, say so
explicitly and explain why — that is itself useful context.

## Technology-Specific Application

How the General Principle is realised on the concrete platform. Concrete
shapes, resource types, configuration keys, code patterns. Use generic
illustrative placeholders (`<client>`, `<env>`, `example.tfvars`,
`modules/<resource>/`) when showing structure. Never name a real
client codebase.

This section may be longer than General Principle. Sub-sections are
encouraged, e.g.:

### <Aspect 1>
### <Aspect 2>
### Trade-offs in this realisation

## Alternatives Considered

For each alternative: name it, state pros and cons, and explain why it
was not chosen.

### Alternative A: <name>
- **Pros:** …
- **Cons:** …
- **Rejected because:** …

### Alternative B: <name>
- **Pros:** …
- **Cons:** …
- **Rejected because:** …

## Consequences

What follows from accepting this decision. Include both the intended
benefits and any costs / new obligations the decision creates.

- <consequence>
- <consequence>

## Related

- ADR-XXXX — <how it relates>
