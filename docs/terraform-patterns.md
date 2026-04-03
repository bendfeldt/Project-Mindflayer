# Terraform Patterns Reference

Quick-reference for common Terraform patterns across engagements.

## Remote State Backends

### Azure Storage
```hcl
backend "azurerm" {
  resource_group_name  = "rg-terraform-state"
  storage_account_name = "stterraformstate"
  container_name       = "tfstate"
  key                  = "{project}/{environment}.tfstate"
}
```

### GCS
```hcl
backend "gcs" {
  bucket = "terraform-state-{project}"
  prefix = "{environment}"
}
```

## Microsoft Fabric Provider Patterns

```hcl
# Workspace with verb-based naming
resource "fabric_workspace" "ingest" {
  display_name = "${local.name_prefix}-Ingest"
  description  = "Raw data ingestion workspace"
  capacity_id  = var.fabric_capacity_id
}

resource "fabric_workspace" "transform" {
  display_name = "${local.name_prefix}-Transform"
  description  = "Data transformation workspace"
  capacity_id  = var.fabric_capacity_id
}
```

Seven-workspace pattern: Configure → Orchestrate → Ingest → Transform → Persist → Serve → Report

## Useful Patterns

### For-each with map
```hcl
variable "workspaces" {
  type = map(object({
    display_name = string
    description  = string
  }))
}

resource "fabric_workspace" "ws" {
  for_each     = var.workspaces
  display_name = "${local.name_prefix}-${each.value.display_name}"
  description  = each.value.description
  capacity_id  = var.fabric_capacity_id
}
```

### Data source for Key Vault secrets
```hcl
data "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  key_vault_id = data.azurerm_key_vault.main.id
}
```
