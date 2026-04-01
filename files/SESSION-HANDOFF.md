# Consultant Toolkit — Session Handoff

## Status: Ready for GitHub repo restructure with curl installer

Everything below captures the full context from this session. Use this to continue
in a new session without losing anything.

---

## What Exists (complete and working)

The toolkit is fully built and functional as a tar-based install. All files are in
the attached `claude-code-setup.tar.gz`. The next step is restructuring it as a
GitHub repo with a Databricks ai-dev-kit-style curl installer.

### Files (27 total)

#### Global config (installed to ~/.claude/, ~/.codex/, ~/.gemini/)
- `CLAUDE.md` — 150 lines. Global identity, standards, stack, secrets policy, auto-detection for new repos
- `sync-global.sh` — syncs ~/.claude/CLAUDE.md to ~/.codex/AGENTS.md and ~/.gemini/GEMINI.md

#### Skills (4, installed to ~/.claude/skills/, cross-platform via SKILL.md standard)
- `skills/adr/SKILL.md` — 202 lines. Architecture Decision Records with domain-specific prompts per platform
- `skills/kimball-model/SKILL.md` — 288 lines. Kimball dimensional modeling, platform-aware DDL output
- `skills/terraform-scaffold/SKILL.md` — 225 lines. IaC project scaffolding with 3 reference files
- `skills/terraform-scaffold/references/dagster.md` — 156 lines
- `skills/terraform-scaffold/references/azure-devops-pipelines.md` — 288 lines
- `skills/terraform-scaffold/references/fabric-modules.md` — 213 lines
- `skills/setup-repo/SKILL.md` — 149 lines. Auto-bootstraps new repos with AGENTS.md + tool configs

#### Reference docs (installed to ~/.claude/docs/)
- `docs/terraform-patterns.md` — 69 lines. Terraform quick reference
- `docs/kimball-reference.md` — 55 lines. Kimball modeling quick reference

#### Repo templates (installed to ~/.claude/docs/repo-templates/)
- `AGENTS-terraform.md` — 73 lines. Terraform repo template with safety rules
- `AGENTS-databricks.md` — 75 lines. Databricks repo template with safety rules
- `AGENTS-fabric.md` — 74 lines. Fabric repo template with safety rules
- `AGENTS-dagster.md` — 99 lines. Dagster repo template with safety rules

#### Permission settings (Claude Code specific)
- `settings/settings-global.json` — 74 lines. Global permissions with strict secret blocking
- `settings/settings-terraform.json` — 31 lines. Terraform: plan auto, apply blocked
- `settings/settings-databricks.json` — 28 lines. Databricks: validate auto, deploy blocked
- `settings/settings-fabric.json` — 20 lines. Fabric: read auto, REST mutations blocked
- `settings/settings-dagster.json` — 27 lines. Dagster: validate auto, execute blocked

#### Cross-tool configs
- `codex/codex.md` — 10 lines. Codex project instructions (points to AGENTS.md)
- `codex/config.toml` — 14 lines. Codex CLI config template
- `copilot/copilot-instructions.md` — 16 lines. Copilot instructions (symlink target)

#### Utility scripts
- `check-template-update.sh` — 62 lines. Version drift checker for repo AGENTS.md
- `install.sh` — 155 lines. Current tar-based installer (to be replaced)
- `sync-global.sh` — 29 lines. Sync global config across tools

---

## Key Design Decisions Made

1. **Global = ~/.claude/CLAUDE.md, Repo = AGENTS.md** — Global config is Claude Code
   native path (also synced to Codex/Gemini). Repo-level uses the cross-platform
   AGENTS.md standard so any agent reads it.

2. **Skills use SKILL.md open standard** — all 4 skills work on Claude Code, Codex,
   Cursor, Copilot, Gemini CLI without modification.

3. **Repo templates are thin (~70 lines)** — they only contain client-specific info
   (name, prefix, platform, build commands). All standards come from global config + skills.

4. **Version headers on templates** — `<!-- template: AGENTS-fabric | version: 1.0.0 | updated: 2026-03-24 -->`
   enables drift checking with check-template-update.sh.

5. **Safety rules in AGENTS.md** — secrets and deploy protection expressed in plain
   language in every repo template, not just in Claude's settings.json. Cross-platform.

6. **Permission settings are tool-specific** — Claude Code gets settings.json, Codex
   gets config.toml, Copilot gets instructions in AGENTS.md. Each tool has its own
   permission mechanism; we create equivalents for each.

7. **Auto-detection** — Global CLAUDE.md instructs Claude Code to check for AGENTS.md
   at session start and offer /setup-repo if missing.

8. **/setup-repo creates configs for all tools** — AGENTS.md, .claude/settings.json,
   codex.md, .github/copilot-instructions.md (symlinked to AGENTS.md).

9. **Principle: read/validate = auto-approve, deploy/destroy = always ask.**
   .env and secrets NEVER read or exposed by any agent.

---

## What Needs to Happen Next: GitHub Repo + Curl Installer

### Target: Databricks ai-dev-kit style installation

```bash
# Global install for all tools
bash <(curl -sL https://raw.githubusercontent.com/{user}/consultant-toolkit/main/install.sh) --global

# Project-scoped install
bash <(curl -sL https://raw.githubusercontent.com/{user}/consultant-toolkit/main/install.sh)

# Specific tools only
bash <(curl -sL https://raw.githubusercontent.com/{user}/consultant-toolkit/main/install.sh) --tools claude,codex,gemini

# With flags
bash <(curl -sL https://raw.githubusercontent.com/{user}/consultant-toolkit/main/install.sh) --global --force
```

### Repo structure to create

```
consultant-toolkit/
├── README.md                              ← GitHub README with install instructions
├── install.sh                             ← Curl-installable installer (main entry point)
├── install.ps1                            ← Windows PowerShell equivalent (optional)
├── global/
│   └── CLAUDE.md                          ← Source of truth for global config
├── skills/
│   ├── adr/SKILL.md
│   ├── kimball-model/SKILL.md
│   ├── setup-repo/SKILL.md
│   └── terraform-scaffold/
│       ├── SKILL.md
│       └── references/
│           ├── dagster.md
│           ├── azure-devops-pipelines.md
│           └── fabric-modules.md
├── docs/
│   ├── terraform-patterns.md
│   └── kimball-reference.md
├── templates/
│   ├── AGENTS-terraform.md
│   ├── AGENTS-databricks.md
│   ├── AGENTS-fabric.md
│   └── AGENTS-dagster.md
├── settings/
│   ├── claude/
│   │   ├── settings-global.json
│   │   ├── settings-terraform.json
│   │   ├── settings-databricks.json
│   │   ├── settings-fabric.json
│   │   └── settings-dagster.json
│   ├── codex/
│   │   ├── config.toml
│   │   └── codex.md
│   └── copilot/
│       └── copilot-instructions.md
├── scripts/
│   ├── check-template-update.sh
│   └── sync-global.sh
└── how-to-guide.md
```

### Installer behavior (install.sh)

The new install.sh should:

1. **Detect available tools** — check if `claude`, `codex`, `gemini` CLIs are installed
2. **Accept flags:**
   - `--global` — install to user-level (~/.claude/, ~/.codex/, ~/.gemini/)
   - `--project` — install to current directory (default)
   - `--tools claude,codex,gemini,copilot` — install for specific tools only
   - `--force` — overwrite existing files without prompting
   - `--profile {type}` — pre-select a platform profile (terraform, databricks, fabric, dagster)
3. **For global install:**
   - Copy global config to all detected/selected tool locations
   - Install skills to ~/.claude/skills/ (and equivalents for other tools)
   - Install docs, templates, settings templates
   - Install utility scripts
   - Compare and merge existing settings.json if present
4. **For project install:**
   - Interactive: ask platform type and client name
   - Create AGENTS.md from template with placeholders filled
   - Create .claude/settings.json (and equivalents for other tools)
   - Create .github/copilot-instructions.md symlink
   - Create docs/adr/ directory
   - Update .gitignore
5. **Support --local flag** — for development, install from local checkout instead of fetching from GitHub

### GitHub README content

Should include:
- One-liner install command
- What it does (consultant portable toolkit)
- What tools are supported
- What skills are included
- How to set up a new repo
- How to update
- Cross-platform compatibility table
- Link to how-to-guide.md

---

## Michael's Context (for memory)

- Solution Lead & Senior Business Analytics Architect at twoday (Denmark)
- Works across 8+ clients simultaneously: PostNord, Pandora, KOMBIT, Aller, etc.
- Repos are tool-scoped: one for Terraform, one for Databricks, one for Fabric per client
- Core stack: Databricks, Fabric, dbt, Terraform, Dagster, Trino, Azure (primary), GCP (expanding)
- Compliance: GDPR, NIS2, DS 484, ISO 27001
- Wants cross-platform compatibility across Claude Code, Codex, Cursor, Copilot, Gemini CLI
- Secrets must NEVER be exposed to any agent
- Permission interruptions are a major flow-breaker — auto-approve safe commands
- Modular rules (.claude/rules/) and agents (.claude/agents/) discussed but not yet built — planned for future
- Uses Apple devices (Mac + iPhone), Proton ecosystem for privacy

---

## Files to Carry Forward

1. `claude-code-setup.tar.gz` — complete current toolkit (all 27 files)
2. `how-to-guide.md` — current guide (needs updating for curl installer)
3. This handoff document

---

## What NOT to change

- File content is finalized — skills, templates, settings, global config are all done
- The SKILL.md format, AGENTS.md format, and cross-platform approach are settled
- The version header pattern for templates stays
- The safety rules section in AGENTS.md templates stays
- The secrets policy in global CLAUDE.md stays

The only work remaining is:
1. Restructure into a GitHub repo layout
2. Rewrite install.sh as a curl-installable script with flags
3. Update README for GitHub
4. Update how-to-guide.md for the new install method
5. Optionally add install.ps1 for Windows
