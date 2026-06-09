# ADR-0031: Databricks Access Connector with System-Assigned Managed Identity for Unity Catalog

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Databricks on Azure / Unity Catalog

## Context

Unity Catalog needs a credential to authenticate workspace clusters to
ADLS Gen2. The two supported patterns on Azure are:

- **Service Principal** with a client secret stored in a UC storage
  credential — long-lived secret, manual rotation.
- **Databricks Access Connector** (a Microsoft-managed Azure resource
  with a managed identity) — no secret to manage, RBAC-based access.

The Access Connector is the Microsoft-recommended pattern and removes
the secret-rotation burden.

## General Principle

Use a **Databricks Access Connector with a system-assigned managed
identity** as the storage credential for Unity Catalog. Grant that
identity the minimum data-access roles on the storage account it serves.
Avoid client secrets for storage authentication.

## Technology-Specific Application

```hcl
resource "azurerm_databricks_access_connector" "uc" {
  name                = "dbxac-${var.project_name}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location

  identity {
    type = "SystemAssigned"
  }
}

locals {
  uc_roles = [
    "Storage Blob Data Contributor",   # data access
    "Storage Queue Data Contributor",  # file-arrival triggers
    "EventGrid EventSubscription Contributor",
  ]
}

resource "azurerm_role_assignment" "uc" {
  for_each             = toset(local.uc_roles)
  scope                = azurerm_storage_account.lakehouse.id
  role_definition_name = each.value
  principal_id         = azurerm_databricks_access_connector.uc.identity[0].principal_id
}

resource "databricks_storage_credential" "uc" {
  name = "dbxacc-${var.project_name}-${var.environment}"
  azure_managed_identity {
    access_connector_id = azurerm_databricks_access_connector.uc.id
  }
}
```

If file-arrival event triggers (Auto Loader) or notification mode are
used, the additional Queue and EventGrid role assignments above are
required. Some operations (e.g., creating managed identities under the
account from the connector) historically required `Contributor` on the
storage account; minimise this where possible and document the scope
when granted.

Lock down the storage account network rules to recognise the connector
explicitly:

```hcl
private_link_access {
  endpoint_tenant_id   = var.tenant_id
  endpoint_resource_id = "/subscriptions/*/resourcegroups/*/providers/Microsoft.Databricks/accessConnectors/*"
}
```

### Trade-offs in this realisation

- A system-assigned identity is recreated if the connector is deleted —
  the new identity has a new principal ID, so all UC external locations
  break until re-granted. Treat the connector as protected state.
- One credential is shared across all external locations. Per-location
  credentials are possible but add operational overhead with little gain
  when all layers live in the same storage account.
- The `private_link_access` rule uses `*` wildcards across
  subscription/RG/connector — this is the documented Microsoft syntax
  but is wider than typical IaC reviewers expect.

## Alternatives Considered

### Alternative A: Service Principal with secret
- **Pros:** Works for non-Databricks consumers too.
- **Cons:** Secret to rotate, store, and protect; secret-leakage blast
  radius.
- **Rejected because:** No reason to take on secret management when MI
  is supported and recommended.

### Alternative B: User-assigned MI on the access connector
- **Pros:** Identity survives connector recreate; reusable across
  resources.
- **Cons:** Extra resource and an extra RBAC step; no real benefit when
  the connector is the only consumer.
- **Rejected because:** System-assigned is simpler and sufficient for
  the typical lakehouse shape.

### Alternative C: One access connector per layer
- **Pros:** Per-layer blast radius.
- **Cons:** Multiplies RBAC; UC supports per-external-location
  credentials, but there is no security gain when all layers share one
  storage account.
- **Rejected because:** Single connector + single credential matches
  the single-storage-account decision (ADR-0028).

## Consequences

- Zero-secret credential model — no rotation, no Key Vault entry for
  storage access.
- File-arrival event triggers (Auto Loader notification mode) work
  because the connector holds the Queue and EventGrid roles in
  addition to Blob Data Contributor.
- The connector identity is scoped to the storage account, not the
  subscription — least-privilege by default.
- The connector is critical state; deletion breaks all UC external
  locations until re-granted with the new identity.
- If `Contributor` is granted on the storage account for connector
  bootstrapping, it is broader than `Storage Blob Data Contributor` and
  may be flagged in audits — document the justification.
- Removing static secrets from the data-access path is a measurable
  improvement for SOC2 CC6.1 / ISO 27001 A.9.4.3 evidence.

## Related

- ADR-0028 — Single ADLS Gen2 storage account that this connector serves.
- ADR-0030 — Unity Catalog external locations using this credential.
