# ADR-0027: Use a NAT Gateway for Outbound Egress from Databricks Subnets

**Status:** Accepted
**Date:** 2026-04-24
**Deciders:** Michael Bendfeldt
**Scope:** Databricks on Azure / Networking

## Context

Databricks clusters in a VNet-injected workspace need outbound access to
the Databricks control plane, package registries (PyPI / Maven / GitHub),
and external SaaS APIs called from notebooks. Two egress options exist:

- **Default Azure outbound** (load-balancer SNAT) — works out of the box
  but uses ephemeral public IPs that change over time and exhausts SNAT
  ports under load.
- **NAT Gateway** — a dedicated managed service with a static public IP,
  much higher SNAT port budget, and predictable behaviour.

Many downstream systems (corporate proxies, vendor APIs, partner systems)
require a **stable** egress IP to allow-list, which rules out default
outbound.

## General Principle

A VNet-injected Databricks workspace whose downstream consumers need a
**predictable egress IP** should use a **dedicated NAT Gateway** with a
Standard Static Public IP. Default load-balancer SNAT is unsuitable for
any workload whose outbound traffic must be allow-listed.

## Technology-Specific Application

Provision an Azure NAT Gateway in the network module, with a single
Standard Static Public IP, associated to **both** the public and private
Databricks subnets:

```hcl
resource "azurerm_public_ip" "egress" {
  allocation_method = "Static"
  sku               = "Standard"
}

resource "azurerm_nat_gateway" "egress" {
  sku_name = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "egress" {
  nat_gateway_id       = azurerm_nat_gateway.egress.id
  public_ip_address_id = azurerm_public_ip.egress.id
}

resource "azurerm_subnet_nat_gateway_association" "public_subnet" {
  subnet_id      = var.public_subnet_id
  nat_gateway_id = azurerm_nat_gateway.egress.id
}

resource "azurerm_subnet_nat_gateway_association" "private_subnet" {
  subnet_id      = var.private_subnet_id
  nat_gateway_id = azurerm_nat_gateway.egress.id
}
```

The Public IP becomes the IP that downstream systems allow-list as the
Databricks workspace egress.

### Trade-offs in this realisation

- Cost: roughly €30–€40/month per environment for the NAT Gateway and
  Public IP combined. Modest, but multiplies by environment count.
- One environment = one egress IP. Geographically distinct workspaces
  need distinct allow-list entries downstream.
- The Static Public IP is critical state. A `terraform destroy` followed
  by re-apply issues a new IP and breaks downstream allow-lists.
  Mitigations: do not destroy the Public IP routinely, import it on
  rebuild, and consider a delete lock on the resource.

## Alternatives Considered

### Alternative A: Default Azure outbound (load-balancer SNAT)
- **Pros:** No resource to provision; zero cost.
- **Cons:** Public IP changes; SNAT port exhaustion under load; cannot
  be allow-listed.
- **Rejected because:** Fails the stable-egress-IP requirement.

### Alternative B: Azure Firewall for egress
- **Pros:** Application-layer filtering, FQDN allow-lists, central log.
- **Cons:** Significant fixed cost; operational overhead; overkill when
  the egress policy is "allow outbound from a known IP".
- **Rejected because:** Cost vs. benefit not justified at typical
  lakehouse scale. Reconsider when application-layer egress controls
  are required.

### Alternative C: User-defined route to an on-prem firewall via VPN/ExpressRoute
- **Pros:** Reuses existing corporate egress controls.
- **Cons:** Requires ExpressRoute or VPN; routes Databricks traffic
  through on-prem hardware.
- **Rejected because:** Out of scope for the default service-endpoint
  model (ADR-0026); reconsider together with a Private-Link redesign.

## Consequences

- One stable egress IP per environment to allow-list externally.
- NAT Gateway scales SNAT ports far higher than load-balancer outbound,
  eliminating port exhaustion under load.
- A single gateway serves both Databricks subnets — no NIC/route
  confusion.
- Cost is non-zero but predictable.
- The Static Public IP must be treated as protected state; loss of the
  IP breaks downstream allow-lists.
- NAT Gateway is regional and zonal — cross-region failover requires a
  separate design.
- A stable egress IP often satisfies vendor/partner contractual
  requirements for source-IP attestation.

## Related

- ADR-0025 — VNet injection that this NAT Gateway sits within.
- ADR-0026 — Service endpoints for inbound PaaS traffic.
