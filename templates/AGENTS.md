# Project Instructions

<!-- template: AGENTS | version: 2.0.0 | updated: 2026-04-21 -->
<!-- To check for updates: diff this file against ~/.ai-toolkit/templates/AGENTS.md -->

## Repo Identity

- **client:** {CLIENT_NAME}
- **platform:** {PLATFORM}
- **repo_type:** {REPO_TYPE}

## Client Conventions

- **Resource/workspace prefix:** `{prefix}`
- Fill in per client — naming patterns, environments, capacity/SKU, region, etc.

## Branching

- `main` — production, protected
- `feature/{description}` — short-lived, one approval required

{Override per repo if branching differs.}

## Stack Conventions

This repo follows the conventions established in the following ADRs. Read them
before making changes that touch architecture, modeling, compute, or deployment.

{ADR_LIST}

## Client-Specific Compliance

{Edit per client — data residency, PII masking, column-level security, retention, etc.}

## Safety Rules

This repo follows the universal safety rules in
**ADR-0011: Safety Rules for All Agents**
(`~/.ai-toolkit/docs/decisions/platform/0011-safety-rules-for-all-agents.md`).

All agents — regardless of which consultant or which agent runtime — must follow
those rules in this repo. They cover secrets, destructive operations, and remote
writes. Do not duplicate the rules here; read the ADR.

## ADR Triggers

Conditions that require a client-scoped ADR are defined in the platform's
triggers ADR (see the Stack Conventions list above for the specific ADR number
for this platform).
