# ADR-0028: Use ADLS Gen2 (StorageV2 + Hierarchical Namespace) as the Lakehouse Storage Layer

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Databricks on Azure / Storage

## Context

A Databricks lakehouse needs object storage that supports:

- POSIX-style directory operations (atomic rename, recursive delete) for
  Spark and Delta Lake performance.
- Per-directory ACLs alongside Azure RBAC, for Unity Catalog external
  locations.
- The `abfss://` scheme that Databricks treats as a first-class storage path.

Plain Azure Blob Storage offers none of these; ADLS Gen2 (StorageV2 with
hierarchical namespace enabled) is the platform answer.

## General Principle

The lakehouse storage layer should be **ADLS Gen2** — `StorageV2` accounts
with **hierarchical namespace enabled** — accessed via `abfss://`. This
is the Databricks-recommended Azure storage shape and a precondition for
Unity Catalog external locations.

The number of accounts (one shared vs. one per layer) is a separate
question handled by ADR-0029 / ADR-0030 and is driven by blast-radius
and isolation requirements rather than by capability.

## Technology-Specific Application

Provision a single `azurerm_storage_account` per environment with the
following baseline:

```hcl
resource "azurerm_storage_account" "lakehouse" {
  account_kind                    = "StorageV2"
  account_tier                    = var.datalake_sku            # "Standard"
  access_tier                     = var.datalake_access_tier    # "Hot"
  account_replication_type        = var.datalake_replication    # "LRS" in dev, ZRS/GZRS in prod
  is_hns_enabled                  = true                        # ADLS Gen2
  allow_nested_items_to_be_public = false
  min_tls_version                 = "TLS1_2"

  identity {
    type = "SystemAssigned"
  }

  blob_properties {
    delete_retention_policy           { days = 30 }
    container_delete_retention_policy { days = 30 }
  }
}
```

Containers are referenced via the
`abfss://<container>@<account>.dfs.core.windows.net` scheme by Databricks
external locations and catalogs (see ADR-0030).

### Trade-offs in this realisation

- HNS cannot be disabled after creation — wrong choice locks the account
  into ADLS Gen2 semantics (which is the desired state here).
- A single shared account couples the blast radius across layers — quota
  throttling on bronze can starve silver/gold. Acceptable at typical
  lakehouse scale; revisit per ADR-0029 if PII isolation hardens.
- Replication tier must be chosen per environment — `LRS` is appropriate
  for dev; production should adopt ZRS/GZRS. The choice is data-driven,
  not enforced by this decision.
- A `lifecycle { ignore_changes = [virtual_network_subnet_ids, ip_rules] }`
  block is commonly added to absorb pipeline-driven firewall churn (see
  ADR-0037). This silently keeps any other manual change too — operators
  should be aware.

## Alternatives Considered

### Alternative A: Plain Blob Storage (no HNS)
- **Pros:** Slightly cheaper transactions; simplest model.
- **Cons:** No POSIX semantics → expensive Delta operations; no
  directory ACLs; Unity Catalog external locations require ADLS Gen2.
- **Rejected because:** Not viable for a Databricks lakehouse.

### Alternative B: Premium block blob (`account_tier = "Premium"`)
- **Pros:** Lower latency, higher IOPS, suited to streaming/serving.
- **Cons:** Roughly an order of magnitude higher cost; no Cool/Archive
  tiers.
- **Rejected (default):** Not justified for batch-dominant workloads;
  consider per-workload for hot serving paths.

### Alternative C: Multiple storage accounts (one per layer)
- **Pros:** Per-layer firewall, RBAC, lifecycle policies; smaller blast
  radius.
- **Cons:** Multiplies network rules, RBAC, and monitoring; harder
  cross-layer copy; Unity Catalog still federates via external locations
  in either shape.
- **Rejected (default):** Single account + container-per-layer keeps the
  operational surface small; revisit when PII isolation requires it.

## Consequences

- One storage account per environment is cheap and simple, and aligns
  with the Unity Catalog "one credential, many external locations"
  pattern (ADR-0030 / ADR-0031).
- 30-day soft delete on blobs and containers protects against accidental
  destruction.
- HNS enables `abfss://` and Delta atomic rename, which the medallion
  pipelines depend on.
- `min_tls_version = "TLS1_2"` and `allow_nested_items_to_be_public = false`
  are baseline security hygiene.
- HNS is irreversible; replication choice is environment-driven and
  must be reviewed before promoting to production.

## Related

- ADR-0029 — Medallion container layout inside this account.
- ADR-0030 — Unity Catalog external locations and catalogs per container.
- ADR-0031 — Databricks Access Connector / Managed Identity that consumes
  this account.
- ADR-0037 — Agent IP allow-listing on this account during plan/apply.
