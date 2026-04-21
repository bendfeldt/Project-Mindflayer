# Copilot Instructions

## Project Overview

Project-Mindflayer is a distribution toolkit that installs portable AI coding assistant configurations (Claude Code, Codex, Gemini CLI, Cursor, GitHub Copilot) across multiple client engagements. It separates universal standards from project-specific settings using a layered model.

## Architecture

### Layered Configuration Model

1. **Baseline** (`global/AGENTS.md`) — universal data-consultant standards, Hard Rules, engineering principles, Kimball/medallion, Conventional Commits, compliance awareness. Shippable across any consultant without modification.
2. **Repo** (`templates/AGENTS.md`) — thin template (~50 lines) installed as `./AGENTS.md` in client repos. Contains only client-specific: name, platform, build commands, branching. Platform conventions (ADR list) injected by installer. Remains the cross-agent instructions file for the repo.
3. **Skills** (`skills/*/SKILL.md`) — reusable capabilities using the cross-platform `SKILL.md` open standard. Installed to `~/.ai-toolkit/skills/` (all agents) and `~/.claude/skills/` (Claude only).

The baseline is copied to each agent's global config location (e.g. `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`) at install time, giving cross-agent parity without per-agent include mechanics.

### Distribution Flow

The `install.sh` installer distributes content from this repo to user machines in two modes:
- `--global`: installs shared content to `~/.ai-toolkit/`, agent-specific config to each selected agent's directory
- `--project`: installs `AGENTS.md` + per-repo settings to the current working directory

Files in `skills/`, `templates/`, `settings/`, and `docs/` are *distribution sources* — they are the canonical versions that get copied to install destinations.

### Key Design Patterns

- **AGENTS.md** is the universal repo instruction file read by all agents. Safety rules and platform context live here, not in tool-specific files.
- **Template versioning**: templates carry HTML comment version headers (`<!-- template: AGENTS | version: 2.0.0 -->`). `tools/check-template-update.sh` detects drift between installed and source versions.
- **Platform conventions as ADRs**: since v2.0.0, platform-specific guidance lives as ADRs in `docs/decisions/platform/` (injected into `AGENTS.md` by the installer).
- **File manifests**: `install.sh` uses hardcoded arrays listing every file to fetch. When adding new files to the repo, the corresponding manifest array in `install.sh` must be updated.
- **Copilot integration**: Copilot reads `.github/copilot-instructions.md` in client repos, which redirects to `AGENTS.md` (see `settings/copilot/copilot-instructions.md` for the template).

## Tests

```bash
# Run the full test suite (pure bash, no frameworks)
bash tests/test-install.sh

# ShellCheck linting (if installed) is run as part of the test suite
```

The test suite uses a sandbox pattern: `setup_sandbox` creates a temp directory with isolated `$HOME`, runs the installer, then `teardown_sandbox` cleans up. Tests cover syntax validation, ShellCheck, flag parsing, file manifest completeness, and end-to-end install scenarios.

## Shell Script Conventions

All scripts must be cross-platform (macOS + Linux):

- Shebang: `#!/usr/bin/env bash` (never `#!/bin/bash`)
- Feature detection: `command -v` (never `which`)
- No `sed -i` (macOS/GNU incompatibility)
- No `grep -oP` (BSD grep lacks Perl regex — use `sed -n` or `grep -oE`)
- Colors via `tput` with fallback for dumb terminals
- `set -euo pipefail` at the top of every script

## Key Conventions

- **Permission philosophy**: read/validate/lint/test = auto-approve; deploy/destroy/secrets = always ask. Expressed in `AGENTS.md` (cross-platform) and `settings.json` (Claude-specific).
- **Secrets policy**: `.env` files and secrets are never read or exposed. Code referencing secrets must use vault lookups or environment variables.
- **Commit format**: Conventional Commits — `type(scope): description` (imperative mood, lowercase, max 72 chars).
- **Three platform profiles**: `terraform`, `databricks`, `fabric` — each with matching `settings-*.json` and platform ADRs in `docs/decisions/platform/`.

## What NOT to Change

These are finalized design decisions (see `docs/decisions/` for ADRs):

- Content of skills, templates, settings, and `global/AGENTS.md` (baseline)
- The `SKILL.md` format, `AGENTS.md` format, and cross-platform approach
- The version header pattern for templates
- The safety rules and secrets policy
