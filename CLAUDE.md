# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Project-Mindflayer** (Consultant Toolkit) manages AI coding assistant configurations across multiple client engagements. Supports Claude Code, Codex, Gemini CLI, Cursor, and GitHub Copilot. Separates global standards from project-specific settings using a layered approach.

## Architecture

### Layered Configuration

- **Global** (`~/.claude/CLAUDE.md`) — portable identity, coding standards, stack preferences, compliance awareness. Synced to Codex/Gemini/Cursor via `scripts/sync-global.sh`.
- **Repo** (`AGENTS.md`) — client-specific: platform, build commands, branching rules, safety rules. Cross-platform standard.
- **Skills** (`SKILL.md` open standard) — adapt to both layers automatically. Work across all supported agents.

### Permission Philosophy

- **Auto-approve:** read, validate, lint, test
- **Always ask:** deploy, destroy, modify secrets
- `.env` and secrets are NEVER read or exposed

### Template Versioning

Templates carry HTML comment version headers. `scripts/check-template-update.sh` detects drift.

## File Layout

```
install.sh              # Curl-installable cross-platform installer
README.md               # GitHub README with install instructions
how-to-guide.md         # Detailed usage documentation
global/CLAUDE.md        # Source of truth for global config
skills/                 # 4 skills: adr, kimball-model, setup-repo, terraform-scaffold
docs/                   # Reference docs: terraform-patterns.md, kimball-reference.md
templates/              # 4 repo templates: AGENTS-{terraform,databricks,fabric,dagster}.md
settings/               # Tool-specific permission settings (claude/, codex/, copilot/)
scripts/                # Utility scripts: check-template-update.sh, sync-global.sh
```

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
3. Repo templates are thin (~70 lines, client-specific only)
4. Version headers on templates enable drift detection
5. Safety rules expressed in `AGENTS.md` (cross-platform), not just `settings.json`
6. Permission settings are tool-specific (settings.json, config.toml, etc.)
7. `/setup-repo` creates configs for all detected tools automatically
8. Principle: read/validate = auto-approve, deploy/destroy = always ask

## What NOT to Change

- Content of skills, templates, settings, and `global/CLAUDE.md` is finalized
- The `SKILL.md` format, `AGENTS.md` format, and cross-platform approach
- The version header pattern for templates
- The safety rules section in `AGENTS.md` templates
- The secrets policy in global `CLAUDE.md`
