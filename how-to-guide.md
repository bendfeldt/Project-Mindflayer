# Consultant Toolkit — How-To Guide

Version 2.0.0 | April 2026

---

## 1. Overview

This toolkit gives you a portable AI coding assistant setup that works across all your client engagements. It supports Claude Code, Codex, Gemini CLI, Cursor, and GitHub Copilot. It separates what belongs to you (coding standards, architecture preferences, reusable skills) from what belongs to each project (client name, resource prefixes, build commands).

**What you get:**

| Component | Location | Purpose |
|-----------|----------|---------|
| Global CLAUDE.md | `~/.claude/CLAUDE.md` | Your identity, standards, stack preferences |
| Skills (8) | `~/.ai-toolkit/skills/` | ADR, Terraform scaffold, Kimball modeling, Setup repo, Smart commit, Smart PR, Branch cleanup, Promote ADR |
| Reference docs | `~/.ai-toolkit/docs/` | Quick-reference for Terraform + Kimball |
| Repo templates (4) | `~/.ai-toolkit/templates/` | Starter AGENTS.md for each repo type |
| Update checker | `~/.ai-toolkit/check-template-update.sh` | Diff repo files against templates |

**How merging works:**

When you start a session inside a repo, Claude Code loads:

1. **`~/.claude/CLAUDE.md`** — your global standards (always loaded, every repo)
2. **`{repo}/AGENTS.md`** — client and platform specifics (layered on top)
3. **`~/.claude/skills/*`** — available everywhere, adapt to the repo context (Claude also auto-discovers from `~/.ai-toolkit/skills/` via @-includes)

> **Key principle:** Global = what travels with you. Repo = what's unique to this client + tool. Skills read both layers and adapt. No duplication between layers.

---

## 2. Installation

### One-liner (from GitHub)

```bash
# Global install — skills, docs, templates, settings to ~/
bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh) --global

# Project install — AGENTS.md + tool configs in the current repo
cd ~/repos/my-project
bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh)
```

### From local checkout

```bash
git clone https://github.com/bendfeldt/Project-Mindflayer.git
cd Project-Mindflayer
bash install.sh --global --local
```

### What the installer does

1. **Detects** which coding agents are installed on your machine (Claude Code, Codex, Gemini CLI, Cursor, Copilot)
2. **Prompts** you to select which agents to configure (defaults to all detected)
3. **Installs** global config, skills, docs, templates, and settings to each agent's config directory

Use `--tools claude,codex` to skip the interactive prompt. Use `--force` to overwrite without asking.

| Flag | Description |
|------|-------------|
| `--global` | Install to user-level config directories |
| `--project` | Set up current repo (default if --global not set) |
| `--tools TOOLS` | Comma-separated list of agents to configure |
| `--force` | Overwrite existing files without prompting |
| `--profile PROFILE` | Platform profile: terraform, databricks, fabric |
| `--local` | Use local checkout instead of fetching from GitHub |
| `--client NAME` | Client name (skips interactive prompt) |
| `--prefix PREFIX` | Resource prefix (skips interactive prompt) |

After installation, verify in Claude Code:

```bash
# Start a new Claude Code session (from any directory)
claude

# List available skills
/skills
# You should see: adr, terraform-scaffold, kimball-model, setup-repo
```

---

## 3. The Global CLAUDE.md

The file at `~/.claude/CLAUDE.md` loads automatically at the start of every Claude Code session, regardless of which repo you are in. It defines:

- Your communication preferences (English for code, direct style, push back when needed)
- Coding standards (naming, error handling, commit format, general principles)
- Your technology stack (Databricks, Fabric, Terraform, SQL Server, etc.)
- Architecture preferences (Kimball, medallion, environment parity, verb-based naming)
- Compliance awareness (GDPR, NIS2, DS 484, ISO 27001)

**Editing:** Open `~/.claude/CLAUDE.md` in any editor. Changes take effect in the next Claude Code session. You can also press `#` during a session to add instructions that update the file.

> **What NOT to put here:** Client names, resource prefixes, subscriptions, build commands, team-specific branching rules. Those belong in the per-repo AGENTS.md.

---

## 4. Skills

Eight skills are installed globally and available in every session. They can be invoked explicitly with a slash command, or the agent picks them up automatically based on your conversation.

### 4.1 ADR — `/adr`

Creates Architecture Decision Records. The skill provides a structured template and adapts its prompts based on the repo's platform declaration.

| Repo Platform | ADR Prompts Focus On |
|---------------|----------------------|
| `terraform` | Blast radius, state migration, provider lock-in, cost implications |
| `databricks` | Grain, SCD type, compute choices, DLT vs. notebook |
| `microsoft-fabric` | Lakehouse vs. Warehouse, DirectLake vs. Import, RLS strategy |

```bash
# Explicit invocation
/adr

# Or just describe the decision — Claude triggers it automatically
"We need to decide between SCD Type 1 and Type 2 for customer address"
```

ADRs are saved to `docs/adr/NNNN-short-kebab-title.md` in the project.

### 4.2 Terraform Scaffold — `/terraform-scaffold`

Bootstraps Terraform project structures with environment parity (dev/test/prod), module layout, provider configs, and naming conventions.

The skill has three reference files that load on demand when relevant:

- **`references/azure-devops-pipelines.md`** — CI/CD pipeline templates with approval gates
- **`references/fabric-modules.md`** — Seven-workspace Fabric pattern as Terraform `for_each`

### 4.3 Kimball Model — `/kimball-model`

Guides dimensional model design through the Kimball four-step process (business process → grain → dimensions → facts). Generates platform-appropriate DDL and structure.

Platform resolution order:

1. **Repo AGENTS.md** (preferred) — if it declares `platform: databricks`, output is Spark SQL with Unity Catalog namespaces
2. **File detection** (fallback) — scans for PySpark imports, Fabric artifacts, T-SQL patterns, etc.
3. **Asks you** — if neither resolves, asks before guessing

### 4.4 Smart Commit — `/commit`

Reviews your staged and unstaged changes, understands what they mean for the project, and generates a business-friendly commit message. Stages files, commits, and optionally pushes.

```bash
# Explicit invocation
/commit

# Or just describe what you want
"commit my changes"
"save my work and push"
```

The skill follows Conventional Commits format (`type(scope): description`) and runs safety checks before every commit — verifying no secrets, tokens, or sensitive data are staged.

### 4.5 Smart PR — `/pr`

Reviews all commits and file changes in your current branch, writes a clear PR title and description, creates the PR, and sets auto-complete so it merges once policies pass. Works for both GitHub (`gh`) and Azure DevOps (`az repos`) repos.

```bash
# Explicit invocation
/pr

# Or describe it naturally
"create a pull request for this branch"
"raise a PR to main"
```

The PR description is structured with a summary, what changed, and why — written so a non-technical stakeholder can understand the business value.

### 4.6 Branch Cleanup — `/prune`

Prunes stale local branches whose remote tracking branch has been deleted from origin. Runs automatically after every push via smart-commit, or invoke manually.

```bash
# Explicit invocation
/prune

# Or describe it naturally
"clean up old branches"
"delete stale branches"
```

The skill runs `git fetch --prune`, identifies branches showing `: gone]` in tracking status, and deletes them with `git branch -d` (safe — refuses unmerged branches). Protected branches (main, master, develop, current branch) are never touched.

### 4.7 Promote ADR — `/promote-adr`

Lift a client-repo ADR into the Project-Mindflayer toolkit as a global standard so it applies to every future engagement. Use when a decision you made in one project turns out to be broadly reusable.

```
"promote this ADR"
"elevate this decision to the toolkit"
"/promote-adr"
"this should be a global ADR"
```

The skill reviews the source ADR for client-specific markers (names, paths, compliance scope), generalizes the language, assigns the next toolkit ADR number, and writes it to `~/repos/Bendfeldt/Project-Mindflayer/docs/decisions/`. It never auto-commits — it hands off to `/commit` in each repo. It also offers to replace the source ADR with a pointer to the canonical toolkit version.

---

## 5. Permission Settings

Claude Code asks for confirmation before running commands. This gets disruptive fast — especially for safe, read-only commands like `terraform validate` or `git diff`. Settings files control which commands are auto-approved and which always require confirmation.

The principle: **read and validate = auto-approve. Deploy and destroy = always ask.**

### Global settings

The installer places a `~/.claude/settings.json` with safe defaults — git commands, file reading, linting, and pytest are auto-approved everywhere. Destructive operations (`rm -rf`), secret files (`.env`), and deployment commands are always blocked or require confirmation.

### Per-repo settings

Each repo type has its own permission profile. The project installer handles this automatically:

```bash
cd ~/repos/kombit-terraform
bash install.sh --profile terraform --tools claude
```

Or manually copy from the installed templates:

```bash
mkdir -p .claude
cp ~/.ai-toolkit/templates/settings/settings-terraform.json .claude/settings.json
```

### What's auto-approved vs. blocked per repo type

| Repo type | Auto-approved | Always asks |
|-----------|--------------|-------------|
| **Terraform** | `init`, `validate`, `fmt`, `plan`, `show`, `state list/show` | `apply`, `destroy`, `import`, `state rm/mv` |
| **Databricks** | `bundle validate/summary`, workspace/catalog list commands | `bundle deploy/run/destroy`, `clusters start/delete` |
| **Fabric** | `az account show/list`, pytest, ruff, nbstripout | `az rest` with POST/PUT/DELETE/PATCH, `az login` |

You can edit any `settings.json` to fit your needs. The format is straightforward — `allow` patterns auto-approve, `deny` patterns always block. Anything not matched still prompts for confirmation.

> **Tip:** Commit `.claude/settings.json` to git so your team gets the same guardrails. Use `.claude/settings.local.json` (auto-gitignored) for personal overrides.

---

## 6. Setting Up a New Repo

### The easy way — automatic detection

Just open Claude Code in your new repo:

```bash
cd ~/repos/postnord-fabric
claude
```

Claude detects there's no `AGENTS.md` and prompts you immediately:

> "This repo doesn't have an AGENTS.md yet. Want me to set it up? I'll need to know the
> platform (Terraform, Databricks, or Fabric) and the client name."

Answer the questions and Claude handles the rest — copies the right template, fills in what it can, creates `.claude/settings.json`, sets up `docs/adr/`, and updates `.gitignore`. It shows a summary with any remaining TODOs.

You can also trigger it manually anytime with `/setup-repo`, or give it everything upfront: `"Set up this repo for PostNord Fabric"`.

### The installer way

Run the project installer from inside the repo:

```bash
cd ~/repos/postnord-fabric
bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh)
# Select "Project" mode, pick "fabric" profile, enter client name
```

Or non-interactively:

```bash
bash install.sh --profile fabric --tools claude,codex,copilot
```

### The manual way

If you prefer to do it yourself:

```bash
# Copy template + settings
cp ~/.ai-toolkit/templates/AGENTS.md ./AGENTS.md
mkdir -p .claude
cp ~/.ai-toolkit/templates/settings/settings-fabric.json .claude/settings.json

# Create ADR directory and gitignore entries
mkdir -p docs/adr
echo '.claude/settings.local.json' >> .gitignore
echo 'CLAUDE.local.md' >> .gitignore

# Fill in {placeholders} in AGENTS.md and inject ADR list for platform
vim AGENTS.md
```

Then open the file and fill in the `{placeholders}`:

- `{CLIENT_NAME}` → the client name (e.g., PostNord, KOMBIT, Pandora)
- `{prefix}` → resource prefix (e.g., `pn`, `kbt`, `pdr`)
- Build commands, subscription IDs, branching strategy
- Client-specific compliance notes

> **Templates are thin on purpose.** Each template is roughly 40–60 lines. They only contain what's unique to the repo — client identity, platform, build commands, branching. All coding standards, architecture principles, and tool expertise come from your global ~/.claude/CLAUDE.md and skills.

**Platform-specific guidance:**

Since v2.0.0, a single universal `AGENTS.md` template is used for all platforms. Platform conventions are expressed as ADRs in `docs/decisions/platform/`:

| Platform | Relevant ADRs | Key Topics |
|----------|---------------|------------|
| `terraform` | 0011, 0019-0020 | Safety rules, module structure, remote state conventions |
| `databricks` | 0011, 0016-0018 | Safety rules, Unity Catalog structure, DLT naming, compute choices |
| `fabric` | 0011, 0012-0015 | Safety rules, workspace pattern, medallion architecture, semantic models |

The installer injects the appropriate ADR list into `AGENTS.md` based on the `--profile` flag.

---

## 7. Keeping Repos Up to Date

### Checking for toolkit updates

The toolkit stamps its version at install time. To check if a newer release is available:

```bash
~/.ai-toolkit/check-update.sh
```

This compares your installed version against the latest GitHub release. If an update is available, it shows the update command. To update:

```bash
bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh) --global --force
```

### Checking repos for template drift

Every repo template includes a version header:

```html
<!-- template: AGENTS | version: 2.0.0 | updated: 2026-03-30 -->
<!-- To check for updates: diff this file against ~/.ai-toolkit/templates/AGENTS.md -->
```

When you copy a template into a repo, this header travels with it.

### When you update a template

1. Edit the template in `~/.ai-toolkit/templates/AGENTS.md`
2. Bump the version number in the header (e.g., `2.0.0` → `2.1.0`)
3. New repos automatically get the latest version

### Checking existing repos for drift

From any repo root that has an AGENTS.md created from a template:

```bash
~/.ai-toolkit/check-template-update.sh
```

The script reads the version header, compares it against the current template version, and shows a diff if they've diverged. You decide what to pull in — new sections are worth adding, but your filled-in client values stay as they are.

Example output when versions match:

```
Repo file: AGENTS.md
  Template:  AGENTS
  Version:   2.0.0

Current template:
  Location:  ~/.ai-toolkit/templates/AGENTS.md
  Version:   2.0.0

✓ Versions match. No structural template updates available.
```

Example output when the template has been updated:

```
⚠ Template has been updated (1.0.0 → 1.1.0).

Structural diff (ignoring filled-in values is up to you):
---
(diff output shown here)
---
```

---

### Uninstalling

To remove the toolkit entirely:

```bash
# Preview what would be removed
~/.ai-toolkit/uninstall.sh --global

# Actually remove global install
~/.ai-toolkit/uninstall.sh --global --confirm

# Also remove user-modified files (CLAUDE.md, settings.json)
~/.ai-toolkit/uninstall.sh --global --confirm --force
```

To remove project-level config from the current repo:

```bash
~/.ai-toolkit/uninstall.sh --project --confirm
```

The uninstaller preserves user content — `docs/adr/`, `.gitignore` entries, and files you've customized are not touched unless you pass `--force` (which creates backups first).

---

## 8. Day-to-Day Workflow

### Starting work on a client repo

```bash
cd ~/repos/kombit-terraform
claude

# Claude now has:
#   - Your global standards (from ~/.claude/CLAUDE.md)
#   - KOMBIT Terraform specifics (from ./AGENTS.md)
#   - All three skills available (/adr, /terraform-scaffold, /kimball-model)
```

### Switching between clients

Just change directories. No config switching, no environment variables, no mode toggles.

```bash
cd ~/repos/postnord-fabric
claude
# /kimball-model generates T-SQL + lakehouse schemas

cd ~/repos/pandora-databricks
claude
# /kimball-model generates Spark SQL + Unity Catalog
```

### Recording a decision

```bash
/adr

# Or describe it naturally:
"Document why we chose Delta Lake for the curated layer"
```

### Scaffolding new infrastructure

```bash
/terraform-scaffold

# Claude asks: which provider(s), what's being provisioned,
# environment needs, state backend. Then generates the full structure.
```

---

## 9. Customization

### Adding a new skill

```bash
mkdir -p ~/.ai-toolkit/skills/my-new-skill

cat > ~/.ai-toolkit/skills/my-new-skill/SKILL.md << 'EOF'
---
name: my-new-skill
description: >
  When to trigger this skill. Be specific and slightly pushy
  so Claude actually uses it when relevant.
---

# My New Skill

Instructions for Claude when this skill activates.
EOF
```

### Adding a reference doc

```bash
vim ~/.ai-toolkit/docs/my-reference.md

# Add @-include to global CLAUDE.md
echo '@~/.ai-toolkit/docs/my-reference.md' >> ~/.claude/CLAUDE.md
```

### Creating a new platform profile

```bash
# Create new platform ADRs in docs/decisions/platform/
vim ~/.ai-toolkit/docs/decisions/platform/0021-sqlserver-conventions.md

# Update install.sh to inject the new ADR list for --profile sqlserver
vim ~/repos/Project-Mindflayer/install.sh
```

### Useful skill repositories

For inspiration or direct use:

- **[anthropics/skills](https://github.com/anthropics/skills)** — Anthropic's official skills (docx, pdf, pptx, xlsx)
- **[VoltAgent/awesome-agent-skills](https://github.com/VoltAgent/awesome-agent-skills)** — Curated skills from real engineering teams
- **[travisvn/awesome-claude-skills](https://github.com/travisvn/awesome-claude-skills)** — Well-organized catalogue by category
- **[trailofbits/claude-code-config](https://github.com/trailofbits/claude-code-config)** — Opinionated global config + hooks
- **[hesreallyhim/awesome-claude-code](https://github.com/hesreallyhim/awesome-claude-code)** — Skills, hooks, agents, and orchestration patterns

---

## 10. Team Lifecycle — Onboarding and Offboarding

Mindflayer is designed for teams where multiple people work on the same client
repo. The layered architecture (global = personal, project = team-shared) makes
this work cleanly:

| Layer | Where it lives | Owned by |
|---|---|---|
| Global config | `~/.claude/CLAUDE.md`, `~/.ai-toolkit/` | Each developer (personal) |
| Project config | `AGENTS.md`, `.claude/settings.json`, `docs/adr/` | The repo (committed, team-shared) |
| Personal overrides | `.claude/settings.local.json`, `CLAUDE.local.md` | Each developer (gitignored) |

### Onboarding a new teammate

When a new developer joins a project where Mindflayer is already set up:

1. **Install Mindflayer globally on the new machine** (one-time, per machine):
   ```bash
   bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh) --global
   ```
   Pick the agents this developer uses (Claude Code, Codex, Gemini, Cursor, Copilot).

2. **Clone the repo and open the coding agent.** `AGENTS.md` loads automatically
   — the new developer immediately gets the same project context as everyone
   else. `.claude/settings.json` (committed) applies the same team permissions.

3. **Only run `/setup-repo` if a config file your agent needs is missing.**
   The skill auto-detects the state and switches to **join mode**:
   - Never rewrites `AGENTS.md`.
   - Infers the profile from the template header.
   - Only creates files that are absent (e.g., the new teammate uses Cursor
     but the repo never had `.cursor/rules/project.md` committed).
   - Runs `check-template-update.sh` at the end to surface any template
     drift as an informational note.

4. **Check for toolkit drift** (optional):
   ```bash
   ~/.ai-toolkit/check-template-update.sh
   ```
   If the repo's `AGENTS.md` was generated from an older template than what
   the new machine has installed, this flags it. Fixing drift is always a
   team decision — never automatic.

**What the new teammate does NOT need to do:**
- Recreate `AGENTS.md` — it's already correct and committed.
- Ask anyone for shared secrets — project config never contains secrets.
- Copy anyone's `CLAUDE.local.md` or `settings.local.json` — those are
  personal overrides, not team config.

### Offboarding a departing teammate

When a teammate leaves the project, almost nothing needs to happen in the repo:

1. **Nothing to remove from the repo.** The committed team config
   (`AGENTS.md`, `.claude/settings.json`, `docs/adr/`, `.gitignore`) belongs
   to the team and stays. Other developers keep using it unchanged.

2. **Personal local overrides stay on the departing dev's machine.** Because
   `.claude/settings.local.json` and `CLAUDE.local.md` are gitignored, they
   were never shared. No secrets or personal notes leak through the repo.

3. **Promote useful local overrides before leaving (optional).** If the
   departing dev had local-only settings or notes that the team should
   inherit, move the content into the committed equivalents before they
   leave:
   - Content in `CLAUDE.local.md` that is team-relevant → merge into
     `AGENTS.md` (via PR).
   - Permissions in `.claude/settings.local.json` that should be team-wide
     → merge into `.claude/settings.json` (via PR).

4. **On the departing dev's personal machine (optional).** They can remove
   Mindflayer entirely if they're no longer using any of their clients' repos:
   ```bash
   ~/.ai-toolkit/uninstall.sh --global --confirm
   ```
   This is purely personal hygiene — it doesn't affect the repo or any
   remaining teammates.

5. **Revoke access to the repo** (out of Mindflayer's scope — this is GitHub /
   Azure DevOps / etc. access management).

---

## 11. Quick Reference

| Task | Command |
|------|---------|
| Install the toolkit (global) | `bash <(curl -sL .../install.sh) --global` |
| Set up a project | `bash <(curl -sL .../install.sh)` or `bash install.sh --local` |
| Set up a new repo (easy) | `/setup-repo` (inside Claude Code, in the repo) |
| Onboard new teammate | Install globally, clone repo, open agent — `AGENTS.md` loads automatically |
| Offboard a teammate | Nothing to remove from the repo; optionally `~/.ai-toolkit/uninstall.sh --global --confirm` on their machine |
| Set up a new repo (manual) | `cp ~/.ai-toolkit/templates/AGENTS-{type}.md ./AGENTS.md` |
| Add repo permissions (manual) | `cp ~/.ai-toolkit/templates/settings/settings-{type}.json .claude/settings.json` |
| Check for template updates | `~/.ai-toolkit/check-template-update.sh` |
| List available skills | `/skills` (inside Claude Code) |
| Create an ADR | `/adr` (inside Claude Code) |
| Scaffold Terraform project | `/terraform-scaffold` (inside Claude Code) |
| Design a dimensional model | `/kimball-model` (inside Claude Code) |
| Edit global config | `vim ~/.claude/CLAUDE.md` |
| Edit global permissions | `vim ~/.claude/settings.json` |
| Edit repo permissions | `vim .claude/settings.json` |
| Add instructions during session | Press `#` (inside Claude Code) |
| Check for toolkit updates | `~/.ai-toolkit/check-update.sh` |
| Uninstall (preview) | `~/.ai-toolkit/uninstall.sh --global` |
| Uninstall (execute) | `~/.ai-toolkit/uninstall.sh --global --confirm` |
