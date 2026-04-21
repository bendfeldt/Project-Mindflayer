<!-- client-adr-template: danish-public-sector-compliance | version: 1.0.0 -->
# Client ADR: Danish Public-Sector Compliance

Copy this file into your client repo as `docs/decisions/NNNN-danish-public-sector-compliance.md` (renumbered for the repo), adjust context to match the specific client, and reference it from the repo's `AGENTS.md`.

## Status

Template — copy and adapt.

## Context

Danish public-sector clients operate under national and EU legislation that requires explicit awareness during design, development, and operations. These rules apply in addition to EU-wide frameworks (GDPR, NIS2, ISO 27001) already named in the data-consultant baseline.

## Decision

Agents working in a Danish public-sector client repo treat the following as mandatory awareness context. Flag any design choice that has compliance implications under these frameworks:

### EU frameworks (inherited from baseline)

- **GDPR** — data processing, consent, data subject rights
- **NIS2** — network and information security directive
- **ISO 27001** — information security management

### Danish-specific frameworks

- **DS 484** — Danish standard for information security
- **Databeskyttelsesloven** — Danish Data Protection Act (implements GDPR in Danish law)
- **Forvaltningsloven** — Danish Public Administration Act; governs case handling, documentation, and citizen rights in administrative decisions
- **Offentlighedsloven** — Danish Access to Public Administration Files Act; governs freedom of information and public access
- **Arkivloven** — Danish Archives Act; governs retention, preservation, and disposal of public records

## Consequences

- Agents do not over-explain these frameworks — the consultant knows them. Agents flag when a design choice touches one.
- Retention, archival, and deletion strategies (data lakehouse tiers, soft-delete vs hard-delete) must be traceable to Arkivloven requirements.
- Public accessibility of data or logs must be designed with Offentlighedsloven in mind (by default assume public access unless exempted).
- Case-handling workflows must preserve Forvaltningsloven's documentation and notification requirements.
- Personal data processing must map to Databeskyttelsesloven + GDPR lawful basis and data subject rights.

## Linked ADRs

- Baseline safety rules: `~/.ai-toolkit/docs/decisions/platform/0011-safety-rules-for-all-agents.md`

## Supersession

- n/a (template)
