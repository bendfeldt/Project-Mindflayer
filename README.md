# Consultant Toolkit

Portable AI coding assistant configuration for consultants working across multiple client engagements. Separates your personal standards from project-specific settings — switch between clients by changing directories.

Works across **Claude Code**, **Codex**, **Gemini CLI**, **Cursor**, and **GitHub Copilot**.

## Quick Install

```bash
# Global setup — installs skills, docs, templates, and settings to ~/
bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh) --global

# Project setup — creates AGENTS.md + tool configs in the current repo
cd ~/repos/my-project
bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh)
```

The installer detects which coding agents are installed on your machine and prompts you to choose which to configure.

## What It Does

Configuration is layered — global standards travel with you, repo-level config is unique to each client and platform:

| Layer | File | Scope |
|-------|------|-------|
| **Global** | `~/.claude/CLAUDE.md` | Your identity, coding standards, stack preferences, compliance awareness |
| **Repo** | `./AGENTS.md` | Client name, platform, build commands, branching rules, safety rules |
| **Skills** | `~/.ai-toolkit/skills/` | Reusable capabilities that adapt to both layers |

When you start a session, the agent loads global config + repo config + skills. No duplication between layers.

## Supported Agents

| Agent | Global Config | Project Config | Skills |
|-------|:---:|:---:|:---:|
| Claude Code | `~/.claude/CLAUDE.md` | `AGENTS.md` + `.claude/settings.json` | `~/.ai-toolkit/skills/` + `~/.claude/skills/` |
| Codex | `~/.codex/AGENTS.md` | `AGENTS.md` + `codex.md` | via SKILL.md standard |
| Gemini CLI | `~/.gemini/GEMINI.md` | `AGENTS.md` | via SKILL.md standard |
| Cursor | `~/.cursor/rules.md` | `AGENTS.md` | via SKILL.md standard |
| Copilot | project-level only | `.github/copilot-instructions.md` -> `AGENTS.md` | via AGENTS.md |

## Installer Options

| Flag | Description |
|------|-------------|
| `--global` | Install to user-level config directories |
| `--project` | Set up current repo (default if `--global` not set) |
| `--tools claude,codex,gemini,cursor,copilot` | Skip agent selection prompt |
| `--force` | Overwrite existing files without prompting |
| `--profile terraform\|databricks\|fabric` | Skip platform selection prompt |
| `--local` | Install from local checkout instead of GitHub |
| `--client NAME` | Client name for project install (skips prompt) |
| `--prefix PREFIX` | Resource prefix for project install (skips prompt) |

## Included Skills

| Skill | Command | Description |
|-------|---------|-------------|
| **ADR** | `/adr` | Architecture Decision Records with domain-specific prompts per platform |
| **Terraform Scaffold** | `/terraform-scaffold` | IaC project scaffolding with environment parity and module patterns |
| **Kimball Model** | `/kimball-model` | Dimensional model design with platform-aware DDL output |
| **Setup Repo** | `/setup-repo` | Auto-bootstrap repos with AGENTS.md + tool configs |
| **Smart Commit** | `/commit` | Review changes and generate business-friendly commit messages |
| **Smart PR** | `/pr` | Create pull requests with auto-complete for GitHub and Azure DevOps |

## Platform Profiles

Each profile provides a repo template (`AGENTS.md`) and matching permission settings:

| Profile | Auto-approved | Always asks |
|---------|--------------|-------------|
| **terraform** | `init`, `validate`, `fmt`, `plan` | `apply`, `destroy`, `import` |
| **databricks** | `bundle validate/summary`, catalog list | `bundle deploy/run/destroy` |
| **fabric** | `az account show/list`, pytest, ruff | `az rest` mutations, `az login` |

## Updating

Check if a newer version of the toolkit is available:

```bash
~/.ai-toolkit/check-update.sh
```

Re-run the global install to get the latest skills, templates, and settings:

```bash
bash <(curl -sL https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh) --global --force
```

Check existing repos for template drift:

```bash
~/.ai-toolkit/check-template-update.sh
```

## Uninstalling

Remove the global toolkit install:

```bash
# Preview what would be removed (dry-run)
~/.ai-toolkit/uninstall.sh --global

# Actually remove
~/.ai-toolkit/uninstall.sh --global --confirm
```

Remove project-level config from the current repo:

```bash
~/.ai-toolkit/uninstall.sh --project --confirm
```

The uninstaller is safe by default — it shows what would be removed without deleting anything. Use `--confirm` to actually remove files, and `--force` to also remove files you may have customized.

## Detailed Guide

See [how-to-guide.md](how-to-guide.md) for complete documentation on skills, permissions, day-to-day workflow, and customization.

## License

MIT
