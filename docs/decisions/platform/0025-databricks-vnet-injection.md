# ADR-0025: Deploy Databricks Workspace with VNet Injection and Secure Cluster Connectivity

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Databricks on Azure / Networking

## Context

A default Azure Databricks workspace runs in a Microsoft-managed VNet.
Cluster nodes get public IPs and traffic flows over the public internet
into PaaS services. For any environment that requires:

- Auditable network paths between Databricks and ADLS / Key Vault / Event Hub.
- The ability to apply NSGs to data-plane traffic.
- Service endpoints (or Private Link) to PaaS resources.
- A stable egress IP that downstream systems can allow-list.

…a workspace deployed into a customer-controlled VNet (VNet injection) is
the only viable option.

A platform default also has to accommodate ad-hoc sandboxes that do not
need the full network treatment, without forking the module.

## General Principle

Production-class Databricks workspaces on Azure should run **inside a
customer-controlled VNet** with **Secure Cluster Connectivity** (no public
worker IPs). The workspace should be the only Databricks-delegated
consumer of its subnets, the network module should expose the toggles
needed to relax this for a sandbox, and the standard mode should remain
"injected + SCC".

## Technology-Specific Application

The Databricks workspace module exposes a boolean (e.g. `dbx_in_vnet`,
driven by `enable_vnet` at the root level) that selects between two
shapes:

- `dbx_in_vnet = true` → `azurerm_databricks_workspace` with
  `custom_parameters` (vnet, public + private subnets, NSG associations)
  and `no_public_ip = true` for Secure Cluster Connectivity.
- `dbx_in_vnet = false` → `azurerm_databricks_workspace` with no custom
  parameters (Microsoft-managed VNet). Reserved for sandbox use only.

The accompanying network module provides:

- A VNet (commonly a `/16`) split into two subnets (public + private).
- Databricks subnet delegation (`Microsoft.Databricks/workspaces`) on
  both subnets.
- Service endpoints to `Microsoft.Storage`, `Microsoft.KeyVault`,
  `Microsoft.EventHub` (see ADR-0026).
- NSGs associated with both subnets.
- A NAT Gateway providing a stable egress IP (see ADR-0027).

### Trade-offs in this realisation

- VNet injection cannot be retrofitted to an existing workspace —
  switching modes requires destroy + recreate (and metastore
  re-attachment).
- CIDR planning is required up front; changing CIDRs later forces a
  workspace recreate.
- Subnet delegation pins the subnet to Databricks; reusing it for
  anything else later is not possible.

## Alternatives Considered

### Alternative A: Default Databricks workspace (Microsoft-managed VNet)
- **Pros:** Zero networking code; simplest deploy.
- **Cons:** Cannot apply NSGs; no service endpoints; workers have public
  IPs; egress IP is variable and cannot be allow-listed downstream.
- **Rejected because:** Fails the security baseline expected of a
  production-class lakehouse.

### Alternative B: VNet injection with Private Link only (no service endpoints)
- **Pros:** Strongest network isolation; on-prem reachable over
  ExpressRoute/VPN; PaaS resources need not be publicly resolvable.
- **Cons:** Requires private DNS zones per service; per-endpoint cost;
  longer setup; broken Databricks connectivity if DNS zones drift.
- **Rejected (default):** Heavier than the default needs to be when
  on-prem connectivity is not in scope. Adopt as a variant when
  on-prem reachability or full public-IP-elimination is required.

### Alternative C: VNet injection without Secure Cluster Connectivity
- **Pros:** Marginally easier outbound troubleshooting (workers
  reachable by public IP).
- **Cons:** Each worker exposes a public IP, widening the attack surface.
- **Rejected because:** SCC is the documented Databricks recommendation
  and costs nothing extra.

## Consequences

- All Databricks data-plane traffic stays inside the customer VNet,
  egressing via a known NAT Gateway IP.
- NSGs and service endpoints provide the policy hooks needed for
  storage / Key Vault / Event Hub firewall rules.
- The toggle keeps a fast sandbox path available without forking the
  module.
- Switching a live workspace from default to injected (or vice versa)
  is a destructive operation; this must be communicated up front.
- Service endpoints do not extend to on-prem networks; if a future
  requirement adds ExpressRoute / VPN traffic, this decision must be
  revisited (likely superseded by a Private-Link variant).
- Injected + SCC + private subnets supports network-segregation
  controls expected under ISO 27001 A.13.1 and similar frameworks.

## Related

- ADR-0026 — Service endpoints over private endpoints.
- ADR-0027 — NAT Gateway egress from Databricks subnets.
- ADR-0032 — Key Vault firewall hardening that depends on this network shape.
- ADR-0037 — Agent IP allow-listing during plan/apply.
