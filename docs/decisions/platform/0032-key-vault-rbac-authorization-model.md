# ADR-0032: Use Key Vault RBAC Authorization (not Access Policies)

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Azure Key Vault / Identity

## Context

Azure Key Vault supports two authorization models:

- **Access Policies** — legacy per-vault permission lists indexed by
  object ID.
- **Azure RBAC** — standard Azure RBAC at the vault scope, integrated
  with Entra ID, conditional access, PIM, and Azure Resource Graph.

Microsoft's stated direction is RBAC. Modern tooling (Terraform,
Databricks Key Vault-backed secret scopes, ADO Key Vault tasks) supports
both, but RBAC has a unified audit story and integrates with the rest
of the Azure identity stack.

## General Principle

Provision Azure Key Vaults with **RBAC authorization enabled**. Grant
access via Azure role assignments at the vault scope, not via Access
Policies. Reserve Access Policies for legacy systems that genuinely
cannot use RBAC, and document them as exceptions.

## Technology-Specific Application

```hcl
resource "azurerm_key_vault" "kv" {
  name                        = "kv-${var.project_name}-${var.environment}"
  location                    = var.location
  resource_group_name         = var.resource_group_name
  tenant_id                   = var.tenant_id
  sku_name                    = "standard"
  enabled_for_disk_encryption = true
  enable_rbac_authorization   = true
  purge_protection_enabled    = true   # see Trade-offs for non-prod relaxation
}

resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.aad_admin_object_id
}

resource "azurerm_role_assignment" "kv_terraform" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "kv_databricks" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = var.databricks_service_oid
}
```

Role choices:

- `Key Vault Secrets Officer` — read/write/list/delete secrets. Suitable
  for the Terraform deploy principal and operational admins.
- `Key Vault Secrets User` — read-only. Suitable for runtime principals
  that only need to fetch secrets.

### Trade-offs in this realisation

- RBAC role propagation can take a few minutes after assignment; a
  first `terraform apply` writing secrets immediately after vault
  creation can race the role assignment. Module dependency wiring
  helps; intermittent failures on fresh tenants still occur.
- `Key Vault Secrets Officer` is broad. Splitting into `Secrets User`
  for runtime principals improves least-privilege but doubles the
  number of role assignments — apply per environment as appropriate.
- `purge_protection_enabled = true` is the production-safe default. In
  short-lived dev/test environments where `terraform destroy` followed
  by re-apply must succeed cleanly, it is sometimes flipped to `false`
  — flag this explicitly per environment.
- The Terraform AzureRM provider has a `key_vault { purge_soft_delete_on_destroy }`
  setting that interacts with this; align both consciously.

## Alternatives Considered

### Alternative A: Access Policies
- **Pros:** Predates RBAC; some legacy SDKs still default to it.
- **Cons:** No conditional access; weaker audit at subscription level;
  Microsoft is steering customers off it.
- **Rejected because:** RBAC is the strategic direction and integrates
  with the rest of Azure IAM tooling.

### Alternative B: Premium SKU with HSM-backed keys
- **Pros:** FIPS 140-2 Level 2; required for some regulated workloads.
- **Cons:** Roughly an order of magnitude higher cost.
- **Rejected (default):** Standard SKU is sufficient for typical
  lakehouse secret scopes; choose Premium per workload when regulated.

### Alternative C: Mixed — RBAC for humans, Access Policies for service principals
- **Pros:** Backwards compatibility for legacy SPs.
- **Cons:** Two parallel models; common cause of "I have permission,
  why is it denied" debugging sessions.
- **Rejected because:** Modern consumers all support RBAC.

## Consequences

- Audit and conditional-access stories align with the rest of the
  Azure estate.
- The same `azurerm_role_assignment` pattern can be reused for any new
  principal.
- No legacy access-policy block that drifts out of sync with the RBAC
  view.
- RBAC propagation latency adds a small failure mode on first apply;
  module dependencies mitigate but do not eliminate it.
- `purge_protection_enabled` choice has compliance implications — for
  data classifications that require guaranteed retention of
  cryptographic material, the production setting must be `true`.
- RBAC + Entra audit logs satisfy "centralised authorization audit"
  requirements (ISO 27001 A.9.4.4).

## Related

- ADR-0033 — Key Vault-backed Databricks secret scope built on this
  vault.
- ADR-0022 — OIDC-derived deploy identity that holds the
  `Key Vault Secrets Officer` role at apply time.
