---
name: setup-repo
description: >
  Bootstrap a new client repo OR safely onboard a new teammate to an existing
  Mindflayer-managed repo. Auto-detects state: fresh (full setup), join
  (additive-only — never clobbers AGENTS.md), or legacy (offers CLAUDE.md
  migration). Triggers automatically at session start when the global
  instructions detect a missing or incomplete setup. Can also be invoked
  manually with /setup-repo. Use when the user says "set up this repo",
  "initialize repo", "new client repo", "bootstrap repo", "I just joined this
  project", or accepts the automatic prompt to configure a project.
version: 1.0.0
updated: 2026-04-23
---

# Repo Setup

Initialize the current repo with the right AGENTS.md template (cross-tool compatible),
permission settings, and folder structure for a specific client and platform.

AGENTS.md is the open standard read by Claude Code, Codex, Cursor, GitHub Copilot,
Gemini CLI, and others. By using AGENTS.md instead of CLAUDE.md at the repo level,
any agent used by any team member gets the same project context.

## Prerequisites

The universal template must be installed at `~/.ai-toolkit/templates/AGENTS.md`.
Before anything else, verify it exists:

```bash
[ -f "$HOME/.ai-toolkit/templates/AGENTS.md" ] && echo "ok" || echo "missing"
```

If it prints `missing`, Mindflayer is not installed on this machine. Stop and
tell the user:

> Mindflayer is not installed globally on this machine. Install it first:
> `curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh | bash -s -- --global`

Do not try to continue without the templates — the fallback would produce a
broken setup.

## Setup Workflow

### Step 1: Detect repo state and branch

Before doing anything else, determine which of three states the repo is in:

1. **Mindflayer-managed already** — `AGENTS.md` exists AND contains a
   `<!-- template: AGENTS | version: ... -->` header comment.
   → **Join mode** (additive only). Go to [Step 1a: Join mode](#step-1a-join-mode).

2. **Legacy repo** — `CLAUDE.md` exists at the repo root but no `AGENTS.md`.
   → Offer to rename `CLAUDE.md` → `AGENTS.md` first (ADR-0001 alignment),
   then proceed as **fresh-setup mode**.

3. **Fresh repo** — neither `AGENTS.md` nor `CLAUDE.md` exists.
   → **Fresh-setup mode**. Go to [Step 2: Gather information](#step-2-gather-information).

Picking the right branch is the whole reason this skill is safe to run on any
repo. Do not skip it.

### Step 1a: Join mode

You are onboarding a new teammate to a repo that already has Mindflayer
configured. The team-shared config (`AGENTS.md`, committed settings) is already
correct — do not touch it.

1. **Do not rewrite `AGENTS.md`.** It belongs to the team; re-running the
   template generator would clobber client-filled placeholders.

2. **Infer the platform** from the `**platform:**` line in `AGENTS.md`:
   ```bash
   grep -i '^**platform:**' ./AGENTS.md | sed 's/.*: *\([a-z-]*\).*/\1/'
   ```
   (Legacy repos with `<!-- template: AGENTS-<platform> -->` header can use that as fallback.)

3. **Detect the user's installed agents** (same as fresh mode — see Step 2.4).

4. **For each selected agent, create only files that are missing.** Use
   `safe_copy`-style logic: if a file exists and matches the template, leave
   it; if it exists and is different, leave it (teammate customization); only
   create files that are absent entirely. Never prompt for overwrite.

5. **Skip client-info prompts.** The client name/prefix are already baked
   into `AGENTS.md`.

6. **Run the drift checker** at the end:
   ```bash
   bash ~/.ai-toolkit/check-template-update.sh
   ```
   Report any drift as an informational note. Do not auto-rewrite.

7. **Print a "Joined" summary** listing which agent-specific files you
   created (often none — which is a success, not a failure).

### Step 2: Gather information

Ask the user for:

1. **Platform** — which type of repo is this?
   - `terraform` — Infrastructure as Code
   - `databricks` — Databricks data platform
   - `microsoft-fabric` — Microsoft Fabric data platform

2. **Client name** — e.g., KOMBIT, PostNord, Pandora, Aller, Matas

3. **Client prefix** — short lowercase prefix for resource naming (e.g., `kbt`, `pn`, `pdr`)

If the user provided this information in their initial request (e.g., "set up this repo
for PostNord Fabric"), don't ask again — extract it from the request.

**Note:** Platform-specific conventions (Fabric medallion layers, Databricks Unity Catalog
structure, Terraform module patterns, safety rules, etc.) are documented in ADRs at
`~/.ai-toolkit/docs/decisions/platform/`. Point new users there for platform guidance.

4. **Detect installed agents** — run `command -v` checks to find what's available:
   - `claude` → `command -v claude`
   - `codex` → `command -v codex`
   - `gemini` → `command -v gemini`
   - `cursor` → `command -v cursor`
   - `copilot` → `command -v gh` (Copilot runs via the GitHub CLI)

   Show the results, defaulting the selection to detected agents (same UX as the installer):
   ```
   Detected agents:
     [1] claude     ✓ installed
     [2] codex      ✗ not found
     [3] gemini     ✗ not found
     [4] cursor     ✗ not found
     [5] copilot    ✓ installed (via gh)

   Configure agents [1,5]:
   ```
   Let the user add or remove agents before proceeding.

### Step 3: Run the installer

The installer handles template substitution, placeholder filling, and ADR injection.
**Do not manually copy or edit templates** — let `install.sh` do it.

Run:

```bash
bash ~/.ai-toolkit/install.sh --project --profile <platform> --client "<client_name>" --prefix <prefix>
```

Where:
- `<platform>` is `terraform`, `databricks`, or `microsoft-fabric`
- `<client_name>` is the client name (quoted if it contains spaces)
- `<prefix>` is the short lowercase prefix

Example:
```bash
bash ~/.ai-toolkit/install.sh --project --profile microsoft-fabric --client "PostNord" --prefix pn
```

The installer will:
- Copy `AGENTS.md` from the universal template
- Substitute `{CLIENT_NAME}`, `{PLATFORM}`, `{prefix}` placeholders
- Inject the platform-specific ADR list into the `{ADR_LIST}` placeholder
- Leave unfilled placeholders (like `{subscription_name_or_id}`) as TODOs

The installer also creates:
- `.claude/settings.json` (Claude Code permissions)
- Tool-specific config files for selected agents (Codex, Copilot, Gemini, Cursor)
- `docs/adr/` directory for Architecture Decision Records
- `.gitignore` entries for local overrides

### Step 4: Detect installed agents and configure

After the installer completes, detect which agents the user has installed (Step 2.4 above)
and offer to run the installer again for any agents not yet configured.

### Step 5: Report what was created

After setup, show a summary listing the files created by the installer:

```
Repo initialized for {client_name} ({platform}):

  AGENTS.md                          ← project instructions — all agents read this (commit)
  .claude/settings.json              ← Claude Code permissions (commit)
  {per-agent files created}
  docs/adr/                          ← architecture decision records
  .gitignore                         ← updated

Remaining TODOs in AGENTS.md:
  - {list any unfilled placeholders}

Platform guidance: ~/.ai-toolkit/docs/decisions/platform/

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

## Important

- **Idempotency first.** Running `/setup-repo` twice on the same repo must be
  safe. Join mode enforces this: never rewrites `AGENTS.md`, only adds missing
  agent-specific files.
- Never overwrite existing files without explicit confirmation
- Always show what will be created before doing it
- The AGENTS.md template version header must be preserved — it's used by the
  update checker script and by join-mode detection
- Settings files should be committed to git (they're team-shared permissions)
- `settings.local.json` and `CLAUDE.local.md` are gitignored (personal overrides)
- AGENTS.md is the cross-tool standard; `.claude/settings.json` is Claude Code-specific
  (other tools have their own permission mechanisms)
