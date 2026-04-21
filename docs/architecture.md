# Architecture: Project-Mindflayer

## What This Is

A distribution toolkit that installs portable AI coding assistant configurations across
multiple client engagements. Supports Claude Code, Codex, Gemini CLI, Cursor, and Copilot
from a single source of truth.

---

## Three-Layer Configuration Model

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Baseline (global/AGENTS.md)                       │
│  Universal data-consultant standards — Hard Rules,          │
│  engineering principles, Kimball/medallion, stack prefs,    │
│  Conventional Commits, GDPR/NIS2/ISO 27001 awareness.       │
│  Shippable across any consultant without modification.      │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: Repo (./AGENTS.md + .claude/settings.json)        │
│  Client name, platform, build commands, safety rules.       │
│  Committed to the project repo — client-specific.           │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Skills (~/.ai-toolkit/skills/*/SKILL.md)          │
│  Reusable capabilities (ADR, Terraform scaffold, Kimball,   │
│  setup-repo). Read the layers above and adapt automatically.│
└─────────────────────────────────────────────────────────────┘
```

**Copy-at-install-time mechanism.** The baseline is copied to each agent's global
config location by the installer — e.g. `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`,
`~/.gemini/GEMINI.md`. This gives cross-agent parity without per-agent include
mechanics. Re-running the installer (or `~/.ai-toolkit/sync-global.sh`) refreshes
each agent from the canonical baseline at `~/.ai-toolkit/AGENTS.md`.

Skills are cross-platform — the `SKILL.md` format is an open standard readable by all
supported agents, not Claude-specific.

**Why three layers, not four.** A short-lived experiment added a personal-overlay layer
between Baseline and Repo (individual quirks that shouldn't ship with the baseline).
That experiment was reverted; see [ADR-0013](decisions/0013-revert-personal-overlay-and-client-adrs.md)
for the reasoning. The three-layer model above is the intentional final state.

---

## Distribution Flow

```
Project-Mindflayer (this repo)
│
├── global/AGENTS.md         ──▶  ~/.ai-toolkit/AGENTS.md            (baseline, always)
│                            ──▶  ~/.claude/CLAUDE.md                (Claude global config, conditional)
│                            ──▶  ~/.codex/AGENTS.md                 (Codex global config, conditional)
│                            ──▶  ~/.gemini/GEMINI.md                (Gemini global config, conditional)
│                            ──▶  ~/.cursor/rules.md                 (Cursor global config, conditional)
│
├── skills/*/SKILL.md       ──▶  ~/.ai-toolkit/skills/*/SKILL.md (agent-neutral, always)
│   (source at repo root)   ──▶  ~/.claude/skills/*/SKILL.md     (Claude auto-discovery, if claude selected)
│
├── docs/*.md               ──▶  ~/.ai-toolkit/docs/*.md         (reference docs, always)
│
├── docs/decisions/*.md     ──▶  ~/.ai-toolkit/docs/decisions/   (decision log, always)
│
├── settings/claude/*.json  ──▶  ~/.claude/settings.json         (global permissions, if claude selected)
│                           ──▶  .claude/settings.json           (per-repo permissions)
│
├── templates/AGENTS.md      ──▶  ~/.ai-toolkit/templates/        (repo template, always)
│                           ──▶  ./AGENTS.md                     (repo layer, per client)
│
├── docs/decisions/platform/ ──▶  ~/.ai-toolkit/docs/decisions/platform/ (platform conventions as ADRs)
│
├── settings/codex/         ──▶  ~/.ai-toolkit/templates/codex/  (if codex selected)
│
└── settings/copilot/       ──▶  ~/.ai-toolkit/templates/copilot/ (if copilot selected)
                            ──▶  .github/copilot-instructions.md
```

The installer (`install.sh`) handles all of the above in two modes:
- **`--global`**: installs global layer — shared content always goes to `~/.ai-toolkit/`; agent-specific config only to selected agents' directories
- **`--project`**: installs repo layer (AGENTS.md, per-repo settings) to the current directory

---

## Installer Operation

`install.sh` supports two source modes:

| Mode | Trigger | Source |
|---|---|---|
| **Curl-pipe** | `bash <(curl -sL URL)` | Fetches files via `curl` from GitHub raw URLs |
| **Local** | `bash install.sh --local` | Reads from `$SCRIPT_DIR` (the repo checkout) |

Detection: `$0` matches `/dev/fd/*` → curl-pipe mode. Otherwise local mode with
`SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`.

File manifests are hardcoded arrays in the installer. When adding new files to the repo,
the corresponding array must be updated in `install.sh`.

---

## Multi-Agent Fan-Out

One install pass writes to all selected agents. Shared content always goes to `~/.ai-toolkit/`
(agent-neutral); agent-specific directories are only created when the agent is selected.

| Agent | Global config | Shared toolkit | Per-repo config |
|---|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` + `~/.claude/settings.json` | `~/.ai-toolkit/` + `~/.claude/skills/` | `.claude/settings.json` |
| Codex | `~/.codex/AGENTS.md` | `~/.ai-toolkit/` | `AGENTS.md` |
| Gemini CLI | `~/.gemini/GEMINI.md` | `~/.ai-toolkit/` | `AGENTS.md` |
| Cursor | `~/.cursor/rules.md` | `~/.ai-toolkit/` | `AGENTS.md` |
| Copilot | — | `~/.ai-toolkit/` | `.github/copilot-instructions.md` |

`~/.ai-toolkit/` is never agent-specific. `~/.claude/` is only created when Claude Code is
among the selected agents.

`AGENTS.md` is the universal repo instruction file — all agents read it, so safety rules
and platform context are expressed there rather than in tool-specific files.

---

## Platform Profiles

Three platform profiles, each with matching `settings-*.json`:

| Profile | Use case | Key auto-approved commands |
|---|---|---|
| `terraform` | IaC repos | `init`, `validate`, `fmt`, `plan` |
| `databricks` | Databricks repos | `bundle validate`, `workspace list` |
| `fabric` | Microsoft Fabric repos | `pytest`, `ruff`, `az account show` |

### Platform Conventions as ADRs (v2.0.0)

Platform-specific conventions (Fabric medallion layers, Databricks Unity Catalog structure, Terraform module structure, etc.) are expressed as ADRs in `docs/decisions/platform/`:

- **0011**: Safety rules (cross-platform)
- **0012-0015**: Fabric conventions
- **0016-0018**: Databricks conventions
- **0019-0020**: Terraform conventions

The universal `templates/AGENTS.md` (v2.0.0) is installed with a platform-specific ADR list injected by `install.sh`. Legacy v1 repos (with per-platform templates) are still supported but deprecated.

---

## Permission Philosophy

- **Auto-approve:** read, validate, lint, test — low blast radius, reversible
- **Always ask:** deploy, destroy, modify secrets — irreversible or affects shared state
- Expressed in `AGENTS.md` (cross-platform) and reinforced in `settings.json` (Claude-specific deny rules)

---

## Template Versioning

The universal `AGENTS.md` template carries an HTML comment header:

```
<!-- template: AGENTS | version: 2.0.0 | updated: 2026-03-30 -->
```

`tools/check-template-update.sh` compares the installed template's version against the
current source and reports drift. This gives manual control over when to pull updates —
no automatic overwrites.
