# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, Gemini CLI,
Cursor, Copilot) when working with code in this repository.

## Project Overview

**Project-Mindflayer** (Consultant Toolkit) manages AI coding assistant configurations across multiple client engagements. Supports Claude Code, Codex, Gemini CLI, Cursor, and GitHub Copilot. Separates global standards from project-specific settings using a layered approach.

## Architecture

### Layered Configuration

- **Global** (`~/.claude/CLAUDE.md`) — portable identity, coding standards, stack preferences, compliance awareness. Synced to Codex/Gemini/Cursor via `tools/sync-global.sh`.
- **Repo** (`AGENTS.md`) — client-specific: platform, build commands, branching rules, safety rules. Cross-platform standard.
- **Skills** (`SKILL.md` open standard) — adapt to both layers automatically. Work across all supported agents.

### Permission Philosophy

- **Auto-approve:** read, validate, lint, test
- **Always ask:** deploy, destroy, modify secrets
- `.env` and secrets are NEVER read or exposed

### Template Versioning

Templates carry HTML comment version headers. `tools/check-template-update.sh` detects drift.

## File Layout

```
install.sh              # Curl-installable cross-platform installer
README.md               # GitHub README with install instructions
how-to-guide.md         # Detailed usage documentation
global/AGENTS.md        # Source of truth for global config (installed to ~/.claude/CLAUDE.md)
skills/                 # Distribution source for skills (installed to ~/.ai-toolkit/skills/ + ~/.claude/skills/ if Claude)
docs/                   # Reference docs, architecture overview, and ADRs
  architecture.md       # System design: layered config model, distribution flow, multi-agent fan-out
  decisions/            # Toolkit-level ADRs (design decisions for this repo itself)
  terraform-patterns.md # Reference: Terraform patterns (installed to ~/.ai-toolkit/docs/)
  kimball-reference.md  # Reference: Kimball modeling (installed to ~/.ai-toolkit/docs/)
templates/              # Distribution source for repo templates (installed to ~/.ai-toolkit/templates/)
settings/               # Tool-specific permission settings (claude/, codex/, copilot/, gemini/, cursor/)
stores.yml              # External stores registry (installed to ~/.ai-toolkit/stores.yml)
tools/                  # Utility scripts: check-template-update.sh, check-stores.sh, check-update.sh, sync-global.sh, uninstall.sh
```

Note: `skills/` and `templates/` are *distribution sources* in this repo. Their install
destinations are `~/.ai-toolkit/skills/` (all agents) and `~/.claude/skills/` (Claude only)
for skills, and `~/.ai-toolkit/templates/` for repo templates. See
`docs/architecture.md` for the full distribution flow. See `docs/decisions/0004-*.md`
for why skills live at repo root rather than under `.claude/skills/`.

## Install Script (`install.sh`)

The installer works both via `bash <(curl -sL URL)` and from local checkout (`bash install.sh --local`).

Key flags: `--global`, `--project`, `--tools`, `--force`, `--profile`, `--local`, `--client`, `--prefix`

**Source resolution:** detects curl-pipe mode (when `$0` is `/dev/fd/*`) and falls back to remote fetching. Local mode uses `SCRIPT_DIR` from `BASH_SOURCE[0]`.

**File manifests:** hardcoded arrays list every file to fetch — must be updated when adding new files.

### Cross-platform requirements

- `#!/usr/bin/env bash` (not `#!/bin/bash`)
- `command -v` (not `which`)
- `sed` without `-i` flag (macOS vs GNU incompatibility)
- No `grep -oP` (Perl regex unavailable on macOS BSD grep — use `sed -n` or `grep -oE`)
- `tput` colors with fallback for dumb terminals

## Key Design Decisions (Finalized)

These are settled — do not revisit:

1. Global config via `~/.claude/CLAUDE.md`, repo-level via `AGENTS.md`
2. Skills use the `SKILL.md` open standard (cross-platform)
3. The repo template is thin (~50 lines, client-specific only)
4. Version headers on templates enable drift detection
5. Safety rules expressed in `AGENTS.md` (cross-platform), not just `settings.json`
6. Permission settings are tool-specific (settings.json, config.toml, etc.)
7. `/setup-repo` creates configs for all detected tools automatically
8. Principle: read/validate = auto-approve, deploy/destroy = always ask

## What NOT to Change

- Content of skills, templates, settings, and `global/AGENTS.md` is finalized
- The `SKILL.md` format, `AGENTS.md` format, and cross-platform approach
- The version header pattern for templates
- The safety rules section in `AGENTS.md` templates
- The secrets policy in global `CLAUDE.md`
