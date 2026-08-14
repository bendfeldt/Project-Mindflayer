# Microsoft Fabric Terraform modules

Confirm current provider resource support before scaffolding. Pin reviewed versions rather than copying a floating example into production.

```hcl
terraform {
  required_version = "~> 1.12.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.3"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "fabric" {}
```

Use workload identity through the execution environment. Do not place credentials in provider blocks.

```hcl
variable "workspace_definitions" {
  description = "Fabric workspaces keyed by stable logical name."
  type = map(object({
    display_name = string
    description  = string
  }))
}

resource "fabric_workspace" "this" {
  for_each = var.workspace_definitions

  display_name = "${var.resource_prefix}-${var.environment}-${each.value.display_name}"
  description  = each.value.description
  capacity_id  = var.capacity_id
}

output "workspace_ids" {
  description = "Workspace IDs keyed by logical name."
  value       = { for key, workspace in fabric_workspace.this : key => workspace.id }
}
```

Prefer Configure, Orchestrate, Ingest, Transform, Persist, Serve, and Report only when those workspaces match the actual operating model. Keep semantic-model deployment outside Terraform when the provider cannot manage the full lifecycle reliably; use a versioned TMDL deployment step instead of `local-exec`.
