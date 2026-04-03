---
name: setup-repo
description: >
  Bootstrap a new client repo with AGENTS.md, .claude/settings.json, and folder
  structure. Triggers automatically at session start when the global CLAUDE.md
  detects the repo has no AGENTS.md yet. Can also be invoked manually with
  /setup-repo. Use when the user says "set up this repo", "initialize repo",
  "new client repo", "bootstrap repo", or accepts the automatic prompt to
  configure a new project.
---

# Repo Setup

Initialize the current repo with the right AGENTS.md template (cross-tool compatible),
permission settings, and folder structure for a specific client and platform.

AGENTS.md is the open standard read by Claude Code, Codex, Cursor, GitHub Copilot,
Gemini CLI, and others. By using AGENTS.md instead of CLAUDE.md at the repo level,
any agent used by any team member gets the same project context.

## Prerequisites

Templates and settings must be installed at `~/.claude/docs/repo-templates/`. If they're
not found, tell the user to run the toolkit installer first.

## Setup Workflow

### Step 1: Check current state

Before doing anything, check what already exists in the repo:

- Does `AGENTS.md` exist at the repo root?
- Does `CLAUDE.md` exist at the repo root? (legacy — offer to migrate to AGENTS.md)
- Does `.claude/settings.json` exist?
- Does `docs/adr/` exist?

If any exist, inform the user and ask whether to overwrite or skip each one.
If a `CLAUDE.md` exists but no `AGENTS.md`, offer to rename it to `AGENTS.md`.

### Step 2: Gather information

Ask the user for:

1. **Platform** — which type of repo is this?
   - `terraform` — Infrastructure as Code
   - `databricks` — Databricks data platform
   - `microsoft-fabric` — Microsoft Fabric data platform
   - `dagster` — Orchestration

2. **Client name** — e.g., KOMBIT, PostNord, Pandora, Aller, Matas

3. **Client prefix** — short lowercase prefix for resource naming (e.g., `kbt`, `pn`, `pdr`)

If the user provided this information in their initial request (e.g., "set up this repo
for PostNord Fabric"), don't ask again — extract it from the request.

### Step 3: Copy and customize templates

1. **Copy the AGENTS.md template** from `~/.claude/docs/repo-templates/AGENTS-{platform}.md`
   to `./AGENTS.md` at the repo root.

2. **Fill in known placeholders:**
   - Replace `{CLIENT_NAME}` with the client name
   - Replace `{prefix}` with the client prefix
   - Replace `{ClientPrefix}` with the prefix in PascalCase (for Fabric workspace naming)
   - Leave other placeholders like `{subscription_name_or_id}`, `{state_storage_account_name}`,
     `{connection_name}` as-is with a comment: `<!-- TODO: fill in -->`

3. **Create tool-specific config directories and files:**

   **Claude Code:**
   - Create `.claude/` directory
   - Copy `~/.claude/docs/repo-templates/settings/settings-{platform}.json` to `./.claude/settings.json`

   **Codex CLI:**
   - Copy `~/.claude/docs/repo-templates/codex/codex.md` to `./codex.md`

   **GitHub Copilot:**
   - Create `.github/` directory
   - Create `.github/copilot-instructions.md` as a symlink to `../AGENTS.md`
     (or copy `~/.claude/docs/repo-templates/copilot/copilot-instructions.md` if
     symlinks are problematic on the team's OS)

4. **Create `docs/adr/` directory** for Architecture Decision Records.

5. **Create `.gitignore` entries** (append if `.gitignore` exists, create if not):
   - `.claude/settings.local.json`
   - `CLAUDE.local.md`

### Step 4: Report what was created

After setup, show a summary:

```
Repo initialized for {client_name} ({platform}):

  AGENTS.md                          ← project instructions — all agents read this (commit)
  .claude/settings.json              ← Claude Code permissions (commit)
  .github/copilot-instructions.md    ← symlink to AGENTS.md for GitHub Copilot
  codex.md                           ← Codex-specific notes (commit)
  docs/adr/                          ← architecture decision records
  .gitignore                         ← updated

Remaining TODOs in AGENTS.md:
  - {list any unfilled placeholders}

Next steps:
  - Fill in the TODOs in AGENTS.md
  - Review .claude/settings.json permissions
  - Commit both files to git
```

## Platform-Specific Extras

### Terraform repos

After the base setup, also check if the standard directory structure exists and offer
to create it:

```
environments/
├── dev/
├── test/
└── prod/
modules/
```

### Databricks repos

Check for `databricks.yml` (DAB config). If missing, note it in the summary.

### Fabric repos

No additional structure needed — Fabric repos are typically managed via Fabric Git integration.

### Dagster repos

Check for `pyproject.toml` and `dagster.yaml`. If missing, note them in the summary.

## Important

- Never overwrite existing files without explicit confirmation
- Always show what will be created before doing it
- The AGENTS.md template version header must be preserved — it's used by the
  update checker script
- Settings files should be committed to git (they're team-shared permissions)
- `settings.local.json` and `CLAUDE.local.md` are gitignored (personal overrides)
- AGENTS.md is the cross-tool standard; `.claude/settings.json` is Claude Code-specific
  (other tools have their own permission mechanisms)
