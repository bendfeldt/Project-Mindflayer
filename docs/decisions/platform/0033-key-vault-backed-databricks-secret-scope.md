# ADR-0033: Use a Key Vault-Backed Databricks Secret Scope

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Databricks on Azure / Secrets

## Context

Databricks notebooks and jobs need access to operational values such as:

- Workspace host URL and workspace ID.
- Deploy principal client and tenant IDs.
- Per-pipeline credentials (database connection strings, vendor API
  tokens, partner credentials).

Databricks supports two secret scope backends:

- **Databricks-backed** — secrets stored inside Databricks itself,
  managed via the Databricks REST API.
- **Azure Key Vault-backed** — secrets stored in an Azure Key Vault,
  surfaced through a Databricks secret scope that proxies reads to the
  vault.

Most engagements have non-Databricks consumers (ADF, Functions, Logic
Apps, Power BI Gateway) that also need the same secrets, so a single
source of truth across consumers is preferable.

## General Principle

Secrets should live in **one authoritative store** that the rest of the
ecosystem reads from. On Azure with Databricks, that store is **Azure
Key Vault**, and Databricks consumers reach it via a **Key Vault-backed
secret scope**. Databricks-internal secret scopes are reserved for the
narrow case where the value is meaningful only inside Databricks and
nowhere else.

## Technology-Specific Application

```hcl
resource "databricks_secret_scope" "kv_scope" {
  name                     = "kv-${var.project_name}-scope"
  initial_manage_principal = "users"

  keyvault_metadata {
    resource_id = var.key_vault_id
    dns_name    = var.key_vault_uri
  }
}
```

Bootstrap secrets are written to Key Vault from Terraform itself:

```hcl
resource "azurerm_key_vault_secret" "databricks_host" {
  name         = "databrickshost"
  value        = azurerm_databricks_workspace.dbx.workspace_url
  key_vault_id = azurerm_key_vault.kv.id
}
# ...similarly for workspace ID, deploy SP client/tenant IDs, etc.
```

Notebooks consume them through standard Databricks ergonomics:

```python
host = dbutils.secrets.get(scope="kv-<client>-scope", key="databrickshost")
```

The scope name typically follows `kv-<project>-scope` or
`kv-<workspace>-scope`. Pick a convention and use it consistently across
environments.

### Trade-offs in this realisation

- Cluster start-up reads against Key Vault must succeed; if Key Vault
  firewall rules block the cluster subnet, jobs fail with a
  "secret not found" error that masks the real cause.
- `initial_manage_principal = "users"` grants workspace users `MANAGE`
  on the scope — appropriate for a shared development workspace,
  inappropriate for production. Tighten to a smaller group for
  prod-class workspaces.
- Bootstrap secrets written by Terraform produce minor `terraform plan`
  noise when their target values are stable.

## Alternatives Considered

### Alternative A: Databricks-backed secret scope
- **Pros:** No dependency on Key Vault; works in any cloud.
- **Cons:** Two places to manage secrets (Databricks plus everywhere
  else); Databricks-backed scopes do not appear in Azure audit logs.
- **Rejected because:** Dual sources of truth is exactly what this
  decision avoids.

### Alternative B: Read Key Vault directly with the Databricks managed identity (no secret scope)
- **Pros:** Even fewer abstractions.
- **Cons:** Requires per-cluster init scripts to install KV SDKs and
  authenticate; loses the `dbutils.secrets.get` ergonomics; not how the
  Databricks ecosystem documents secret access.
- **Rejected because:** Awkward developer experience and divergent from
  the Databricks-recommended path.

### Alternative C: CI library variables only (no Key Vault)
- **Pros:** Already in use for `ARM_*` deploy identity.
- **Cons:** Pipeline secrets are not reachable from notebooks at runtime.
- **Rejected because:** Wrong tool for runtime secrets.

## Consequences

- Single source of truth for secrets — Key Vault is authoritative;
  Databricks proxies.
- Rotation is a Key Vault operation; no Databricks restart required for
  the proxy to pick up a new value.
- Audit trail of secret reads lands in Key Vault diagnostic logs when
  enabled — verify diagnostic settings are turned on as part of the
  vault module.
- Cluster reads depend on Key Vault network reachability; firewall
  changes that exclude clusters cause confusing job failures.
- `initial_manage_principal` choice has real grant consequences;
  default for prod should not be `"users"`.
- Centralising secrets in Key Vault provides the audit story typically
  required for ISO 27001 A.9.4.1.

## Related

- ADR-0032 — Key Vault RBAC model that this scope authorises against.
- ADR-0022 — OIDC deploy identity used to write bootstrap secrets.
