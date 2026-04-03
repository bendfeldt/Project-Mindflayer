# Microsoft Fabric Terraform Module Examples

Reference for provisioning Microsoft Fabric resources with the `microsoft/fabric`
Terraform provider. Load this reference when the project involves Fabric provisioning.

## Provider Setup

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    fabric = {
      source  = "microsoft/fabric"
      version = "~> 1.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "fabric" {}  # Uses Azure CLI / managed identity auth by default

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

## Seven-Workspace Architecture

The verb-based workspace naming pattern: Configure → Orchestrate → Ingest →
Transform → Persist → Serve → Report.

```hcl
variable "workspace_definitions" {
  description = "Workspace definitions following verb-based naming"
  type = map(object({
    display_name = string
    description  = string
  }))
  default = {
    configure = {
      display_name = "Configure"
      description  = "Platform configuration, connections, and governance"
    }
    orchestrate = {
      display_name = "Orchestrate"
      description  = "Pipeline orchestration and scheduling"
    }
    ingest = {
      display_name = "Ingest"
      description  = "Raw data ingestion from source systems"
    }
    transform = {
      display_name = "Transform"
      description  = "Data transformation and business logic"
    }
    persist = {
      display_name = "Persist"
      description  = "Lakehouse and warehouse storage layer"
    }
    serve = {
      display_name = "Serve"
      description  = "Semantic models and SQL analytics endpoints"
    }
    report = {
      display_name = "Report"
      description  = "Reports, dashboards, and end-user content"
    }
  }
}

resource "fabric_workspace" "ws" {
  for_each     = var.workspace_definitions
  display_name = "${var.client_prefix}-${var.environment}-${each.value.display_name}"
  description  = each.value.description
  capacity_id  = var.fabric_capacity_id
}
```

## Lakehouse Module

```hcl
# modules/fabric-lakehouse/main.tf

resource "fabric_lakehouse" "main" {
  display_name = "${var.name_prefix}-lakehouse"
  workspace_id = var.workspace_id
  description  = var.description
}

output "lakehouse_id" {
  value = fabric_lakehouse.main.id
}

output "sql_endpoint_connection_string" {
  value       = fabric_lakehouse.main.properties.sql_endpoint_properties.connection_string
  description = "SQL analytics endpoint for querying lakehouse tables"
}
```

## Warehouse Module

```hcl
# modules/fabric-warehouse/main.tf

resource "fabric_warehouse" "main" {
  display_name = "${var.name_prefix}-warehouse"
  workspace_id = var.workspace_id
  description  = var.description
}

output "warehouse_id" {
  value = fabric_warehouse.main.id
}

output "connection_string" {
  value = fabric_warehouse.main.properties.connection_string
}
```

## Semantic Model Considerations

As of the current provider version, semantic models (Power BI datasets) have limited
Terraform support. The typical pattern is:

1. **Terraform** provisions workspaces, lakehouses, and warehouses
2. **TMDL / TMSL** scripts manage semantic model definitions (stored in git)
3. **Azure DevOps pipelines** deploy semantic models via the Fabric REST API or
   `fabric-tools` CLI

```hcl
# You can use a null_resource + local-exec for semantic model deployment
# if you want to keep everything in Terraform, but this is fragile.
# Better: separate pipeline step.

# What Terraform CAN do: assign workspace roles
resource "fabric_workspace_role_assignment" "report_viewers" {
  workspace_id   = fabric_workspace.ws["report"].id
  principal_id   = var.report_viewer_group_id
  principal_type = "Group"
  role           = "Viewer"
}
```

## Capacity Management

Fabric capacities are typically provisioned at the Azure level, then referenced in Fabric:

```hcl
# Provision capacity via azurerm
resource "azurerm_fabric_capacity" "main" {
  name                = "${var.client_prefix}-${var.environment}-fc"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku {
    name = var.fabric_sku  # F2, F4, F8, F16, F32, F64, etc.
    tier = "Fabric"
  }
  administration_members = var.capacity_admins
  tags                   = var.common_tags
}

# Reference in Fabric resources
resource "fabric_workspace" "example" {
  display_name = "${var.client_prefix}-${var.environment}-Transform"
  capacity_id  = azurerm_fabric_capacity.main.id
}
```

## Environment Pattern: Dev vs. Prod

```hcl
# environments/dev/main.tf
module "fabric_workspaces" {
  source             = "../../modules/fabric-workspaces"
  client_prefix      = "pn"          # PostNord
  environment        = "dev"
  fabric_capacity_id = azurerm_fabric_capacity.main.id
  # Dev: smaller capacity, fewer role assignments
}

# environments/prod/main.tf
module "fabric_workspaces" {
  source             = "../../modules/fabric-workspaces"
  client_prefix      = "pn"
  environment        = "prod"
  fabric_capacity_id = azurerm_fabric_capacity.main.id
  # Prod: larger capacity, full role assignments, monitoring
}
```

## Connection / Gateway Setup

Fabric connections (e.g., to on-premises data sources) are managed via the Fabric
REST API, not Terraform. The Terraform role here is:

1. Provision the Azure resources the gateway connects to (VNet, private endpoints)
2. Provision Key Vault secrets that the gateway uses for authentication
3. Document the manual gateway setup step in the project README

## Common Pitfalls

- **Capacity must exist before workspaces** — use `depends_on` or reference the
  capacity resource output directly
- **Workspace names must be unique per tenant** — include client prefix + environment
  in the name to avoid collisions
- **Lakehouse SQL endpoints take time to provision** — plan for eventual consistency
  in downstream dependencies
- **RBAC propagation delay** — role assignments may take a few minutes to take effect;
  don't chain immediate dependent operations in CI
