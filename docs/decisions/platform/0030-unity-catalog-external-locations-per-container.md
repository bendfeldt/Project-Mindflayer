# ADR-0030: One Unity Catalog External Location and Catalog per Storage Container

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Databricks on Azure / Unity Catalog

## Context

Unity Catalog (UC) governs Databricks data access. Two top-level objects
matter for storage federation:

- **External Location** — a (URL, storage credential) pair that grants
  data-plane access to a path on cloud storage.
- **Catalog** — the top-level UC namespace, optionally backed by an
  external storage root.

A medallion layout (ADR-0029) provisions multiple storage containers
under a single account. The question is the mapping from containers to
external locations and catalogs.

## General Principle

Map **one external location and one catalog per storage container**,
sharing a single storage credential. This produces a one-to-one
correspondence between physical storage layers and UC namespaces, which
makes per-layer governance, lineage, and grants natural.

The metastore itself is **not** owned by the workspace's Terraform root —
it lives at the Databricks account level and is provisioned separately.
The workspace is **assigned** to the existing metastore via
`databricks_metastore_assignment`.

## Technology-Specific Application

```hcl
resource "databricks_external_location" "layer" {
  for_each        = toset(var.container_list)
  name            = "${var.project_name}_${each.value}_${var.environment}"
  url             = "abfss://${each.value}@${var.storage_account_name}.dfs.core.windows.net"
  credential_name = databricks_storage_credential.uc.id
  skip_validation = true
}

resource "databricks_catalog" "layer" {
  for_each       = toset(var.container_list)
  metastore_id   = var.metastore_id
  name           = "${var.project_name}_${each.value}_${var.environment}"
  storage_root   = "abfss://${each.value}@${var.storage_account_name}.dfs.core.windows.net"
  isolation_mode = "ISOLATED"
  properties     = { purpose = var.environment }
}
```

Issue per-layer grants (`ALL_PRIVILEGES`, `MANAGE`, `USE CATALOG`,
`READ`) to account-level groups. Default to broader grants in dev/test
and tighter grants in production; the variable shape is the same.

The metastore is provisioned at the account level by a separate Terraform
root or a separate workflow; the workspace root only assigns to it.

### Trade-offs in this realisation

- The set of grants is typically hard-coded in the module while the
  group target is a variable — production may need finer differentiation
  than this default offers.
- `isolation_mode = "ISOLATED"` binds catalogs to the workspace by
  default; explicit cross-workspace sharing requires
  `databricks_workspace_binding`.
- `skip_validation = true` on external locations avoids a chicken-and-egg
  apply ordering problem but defers credential-validation errors to the
  first read.
- A single shared credential (ADR-0031) means a misconfigured external
  location can in principle reach all layers; mitigated by per-layer
  grant scoping.

## Alternatives Considered

### Alternative A: One external location and one catalog over the whole account
- **Pros:** Simpler; one grant set.
- **Cons:** Cannot grant per layer; loses the layer-aware governance
  enabled by the medallion split.
- **Rejected because:** Defeats the per-layer grant model.

### Alternative B: One catalog with per-layer schemas
- **Pros:** Reduced top-level clutter.
- **Cons:** Schemas under one catalog cannot easily back distinct
  storage roots; workspace binding is a catalog-level concept;
  per-schema default storage gets messy.
- **Rejected because:** Workspace-binding flexibility and per-layer
  storage roots both want the catalog level.

### Alternative C: External locations only, no catalogs (legacy `hive_metastore`)
- **Pros:** Simpler bootstrap.
- **Cons:** Foregoes UC governance, lineage, and audit; not
  future-proof.
- **Rejected because:** Unity Catalog is the strategic direction.

## Consequences

- Per-layer catalogs allow differential grants across layers (e.g.,
  developers `MANAGE` on `landing`/`raw`, `READ` on `curated`).
- Workspace-binding flexibility is preserved.
- The `${project}_${layer}_${env}` naming is consistent and parseable.
- `skip_validation = true` defers credential errors to first read.
- The metastore is shared infrastructure; misassignment is hard to
  reverse cleanly. Source the metastore ID with care.
- UC produces a centralised audit trail of data access, useful for
  ISO 27001 A.12.4.1.

## Related

- ADR-0028 — ADLS Gen2 storage layer.
- ADR-0029 — Container layout that drives the `for_each` keys.
- ADR-0031 — Databricks Access Connector providing the shared storage
  credential.
