# Project Instructions

<!-- template: AGENTS | version: 2.2.0 | updated: 2026-04-23 -->
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

## Project Layout

This repo follows the canonical Claude Code per-project layout (see
**ADR-0014: Per-Project `.claude/` Layout**):

```
.
├── AGENTS.md                 # this file — cross-agent instructions
└── .claude/
    ├── settings.json         # permissions and hooks (profile-specific)
    ├── skills/               # toolkit skills, committed for Cowork visibility
    ├── rules/                # client-specific modular guidance (optional)
    ├── commands/             # repeatable project workflows (optional)
    ├── agents/               # specialized sub-agents (optional)
    └── hooks/                # event-driven shell scripts (optional)
```

Each optional folder ships with a `README.md` explaining its purpose. Populate
as the engagement needs; leave empty folders untouched.

## Claude Cowork

Claude Cowork (the "Cowork" tab in the desktop app, and `claude.ai/code`) runs
sessions in Anthropic-managed cloud VMs that see only what's in the git clone.
Because skills live under `.claude/skills/` and are committed to this repo,
they travel into every Cowork session automatically — no per-user setup needed.

User-global skills at `~/.claude/skills/` do **not** reach Cowork; only the
in-repo copies do. Keep the two in sync via:

- `tools/check-skills-update.sh` — detect drift
- `tools/sync-skills.sh` — refresh from the toolkit

## Promoting Changes Back to the Toolkit

Decisions and skills authored in this repo that prove broadly useful can be
elevated to Project-Mindflayer so future engagements inherit them:

- **ADRs** — run `/promote-adr` to generalize and lift a client ADR up to the toolkit
- **Skills** — run `/promote-skill` to generalize and lift a skill from `./.claude/skills/<name>/` up to the toolkit

Both workflows never auto-commit and always show a diff before writing.

## Stack Conventions

This repo follows the conventions established in the following ADRs. Accepted
ADRs are binding — read them before any non-trivial change, including tooling,
CI, and operations, not only architecture and modeling. If a change would
violate an ADR, stop and resolve the conflict before proceeding (see the
**Respect the Decision Log** Hard Rule in the baseline instructions).

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
