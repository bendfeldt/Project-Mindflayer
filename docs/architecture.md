# Architecture: Project-Mindflayer

## What This Is

A distribution toolkit that installs portable AI coding assistant configurations across
multiple client engagements. Supports Claude Code, Codex, Gemini CLI, Cursor, and Copilot
from a single source of truth.

---

## Three-Layer Configuration Model

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 1: Global (~/.claude/CLAUDE.md)                      │
│  Personal identity, coding standards, stack preferences,    │
│  compliance awareness. Travels with you to every repo.      │
├─────────────────────────────────────────────────────────────┤
│  Layer 2: Repo (./AGENTS.md + .claude/settings.json)        │
│  Client name, platform, build commands, safety rules.       │
│  Committed to the project repo — client-specific.           │
├─────────────────────────────────────────────────────────────┤
│  Layer 3: Skills (~/.claude/skills/*/SKILL.md)              │
│  Reusable capabilities (ADR, Terraform scaffold, Kimball,   │
│  setup-repo). Read both layers and adapt automatically.     │
└─────────────────────────────────────────────────────────────┘
```

Skills are cross-platform — the `SKILL.md` format is an open standard readable by all
supported agents, not Claude-specific.

---

## Distribution Flow

```
Project-Mindflayer (this repo)
│
├── global/CLAUDE.md        ──▶  ~/.claude/CLAUDE.md             (global layer)
│
├── skills/*/SKILL.md       ──▶  ~/.claude/skills/*/SKILL.md     (global skills)
│   (source at repo root)         (install destination)
│
├── docs/*.md               ──▶  ~/.claude/docs/*.md             (reference docs)
│
├── settings/claude/*.json  ──▶  ~/.claude/settings.json         (global permissions)
│                           ──▶  .claude/settings.json           (per-repo permissions)
│
├── settings/codex/         ──▶  ~/.codex/config.toml + AGENTS.md
│
├── settings/copilot/       ──▶  .github/copilot-instructions.md
│
└── templates/AGENTS-*.md   ──▶  ./AGENTS.md                     (repo layer, per client)
```

The installer (`install.sh`) handles all of the above in two modes:
- **`--global`**: installs global layer (CLAUDE.md, skills, docs, settings) to `~/`
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

One install pass writes to all detected agents:

| Agent | Global config | Per-repo config |
|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` + `~/.claude/settings.json` | `.claude/settings.json` |
| Codex | `~/.codex/config.toml` | `AGENTS.md` (shared with Claude) |
| Gemini CLI | Sync via `tools/sync-global.sh` | `AGENTS.md` |
| Cursor | Sync via `tools/sync-global.sh` | `AGENTS.md` |
| Copilot | — | `.github/copilot-instructions.md` |

`AGENTS.md` is the universal repo instruction file — all agents read it, so safety rules
and platform context are expressed there rather than in tool-specific files.

---

## Platform Profiles

Four platform profiles, each with a thin `AGENTS-*.md` template (~70 lines) and matching
`settings-*.json`:

| Profile | Use case | Key auto-approved commands |
|---|---|---|
| `terraform` | IaC repos | `init`, `validate`, `fmt`, `plan` |
| `databricks` | Databricks repos | `bundle validate`, `workspace list` |
| `fabric` | Microsoft Fabric repos | `pytest`, `ruff`, `az account show` |
| `dagster` | Orchestration repos | `definitions validate`, `asset list` |

---

## Permission Philosophy

- **Auto-approve:** read, validate, lint, test — low blast radius, reversible
- **Always ask:** deploy, destroy, modify secrets — irreversible or affects shared state
- Expressed in `AGENTS.md` (cross-platform) and reinforced in `settings.json` (Claude-specific deny rules)

---

## Template Versioning

Each `AGENTS-*.md` template carries an HTML comment header:

```
<!-- template: AGENTS-fabric | version: 1.0.0 | updated: 2026-03-24 -->
```

`tools/check-template-update.sh` compares the installed template's version against the
current source and reports drift. This gives manual control over when to pull updates —
no automatic overwrites.
