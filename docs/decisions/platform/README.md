# Platform ADRs

Generic, technology-scoped best practices for engagements built on a given
stack (Terraform, Databricks, Microsoft Fabric, cross-cutting). See
[ADR-0015](../0015-adr-location-hierarchy-and-scope.md) for the full
location hierarchy and the rules that govern this folder.

## What belongs here

- Decisions that apply to **any** engagement on the named stack.
- Patterns, defaults, and conventions a consultant should adopt when
  starting a new engagement on that stack.

## What does NOT belong here

- Client, company, or project names.
- Concrete repository names tied to a specific engagement.
- Repository-specific paths or module names that exist only in one
  client codebase.
- Phrasing such as "this repo", "this engagement", "the repo committed
  to…". Platform ADRs describe a pattern, not a state.

If an ADR contains any of the above, it belongs in the **client's own
repo** under `docs/decisions/` or `docs/adr/`.

## Categories (informal — folder is flat)

- **Cross-cutting:** safety, ADR triggers, agent behaviour
  (e.g. 0011, 0015, 0020).
- **Terraform / Infrastructure-as-Code:** state, modules, env strategy,
  versioning, CI/CD (0019, 0021–0024, 0035–0038).
- **Networking & egress:** VNet injection, service endpoints, NAT
  egress, agent IP allowlisting (0025–0027, 0037).
- **Storage & data layout:** ADLS Gen2, medallion containers
  (0028–0029).
- **Identity & secrets:** OIDC, managed identity, Key Vault RBAC,
  Databricks secret scope (0022, 0031–0033).
- **Databricks platform:** Unity Catalog, compute defaults, external
  locations, cluster policy (0016–0018, 0030, 0034).
- **Microsoft Fabric:** medallion layers, semantic model, git
  integration, ADR triggers (0012–0015 in the legacy range).

ADR numbering is shared across all categories; the folder is flat.

## Templates

Use [`../templates/adr-platform-template.md`](../templates/adr-platform-template.md)
when adding an ADR here.

For ADRs that live inside a client repo (deviations, engagement-specific
choices), use
[`../templates/adr-client-template.md`](../templates/adr-client-template.md)
in the client repo.

## Review checklist for a Platform ADR

Before merging an ADR into this folder, confirm:

- [ ] No client or company names appear in the file.
- [ ] No repository-specific paths or module names appear.
- [ ] No "this repo" / "this engagement" framing.
- [ ] A `Scope` line names the platform(s) the ADR applies to.
- [ ] `General Principle` and `Technology-Specific Application` sections
      are both present and distinct.
- [ ] If it conflicts with an existing Platform ADR, the older one is
      marked **Superseded** with a `Superseded-by:` header.
