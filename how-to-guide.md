# How-to Guide

## Prerequisites

Use Bash 3.2+ on Linux or macOS, or PowerShell 7.4+ (the LTS baseline) on
Windows 10/11. Native Windows uses NTFS directory junctions and does not require
Git Bash or WSL. Git Bash is unsupported; WSL2 remains best effort. Installed
lifecycle tools are Bash scripts on Linux/macOS and PowerShell scripts on
Windows. The bootstrap uses an existing Cosign executable or downloads a
checksum-pinned temporary copy to verify signed release bundles before execution.
Release-draft tooling installs one portable Python generator on every
platform; on macOS it opens the draft in Outlook. Native Windows behavior is
CI-tested on GitHub's Windows runner. Python 3.12+, Git, and provider CLIs are
required only by the capabilities identified in the normative
[system requirements](docs/system-requirements.md), which also defines supported
consumers, network access, and filesystem requirements.

## Global installation

Choose tools explicitly. The wrapper automatically selects Linux or macOS and uses amd64 or arm64 for its temporary verifier.

```bash
curl -fsSL --proto '=https' --proto-redir '=https' https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.sh | bash -s -- --global --tools claude,codex,copilot
```

Windows uses the amd64 Cosign binary on both AMD64 and ARM64, with Windows x64 emulation on ARM64:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.ps1'))) -Global -Tools claude,codex,copilot
```

Canonical skills remain under `~/.ai-toolkit/skills/`. Verified links expose them to the selected consumers. Replacements are opt-in:

```bash
"$HOME/.ai-toolkit/install.sh" --global --tools claude,codex,copilot --force
```

## Project installation

Run the command from the target repository, never from Project-Mindflayer itself:

```bash
curl -fsSL --proto '=https' --proto-redir '=https' https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.sh | bash -s -- --project --tools claude,codex --project-types data-platform,data-engineering --technologies databricks,databricks:asset-bundles,dbt,python,sql --client "Client" --prefix cl
```

Windows equivalent:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.ps1'))) -Project -Tools claude,codex -ProjectTypes data-platform,data-engineering -Technologies databricks,databricks:asset-bundles,dbt,python,sql -Client 'Client' -Prefix cl
```

`--project-types` accepts any non-empty combination of `infrastructure`, `data-platform`, and `data-engineering`. `--technologies` accepts canonical identifiers from `config/technology-catalog.tsv`. The legacy `--profile terraform|databricks|fabric` interface remains supported for existing automation; it is unrelated to a Databricks CLI profile. Every Databricks command still requires an explicitly selected `--profile <name>`.

Existing managed projects enter join mode: `AGENTS.md` is preserved while missing selected-tool artifacts are added. Project skills are installed as complete real-file trees under the selected consumers' discovery roots.

## Choosing and updating project skills

Project installs can include all eleven skills or only some of them.

- **In a terminal**, the installer shows every skill with its status, release
  version, and a short description, with the current selection ticked. Type
  numbers or names to toggle them (`3 5-7`, `adr`), `a` for all, `n` for none,
  Enter to continue, or `q` to cancel without changes. It then lists the
  planned installs, updates, and removals and asks `Proceed? [Y]es, [n]o, [d]iffs`.
- **In scripts and CI**, pass `--skills adr,smart-commit` (or `all`, or `none`).
  Without `--skills`, a new project gets every skill and an existing project
  keeps its current selection. Set `MINDFLAYER_NONINTERACTIVE=1` to never show
  the list; it is never shown when `CI` is set or output is redirected.

The selection is stored in the committed `AGENTS.md`, so everyone who clones the
repository gets the same skills:

```markdown
- **skills:** adr, smart-commit
```

The line is absent when every skill is selected, which is also how projects
installed by earlier releases are read. `none` records an empty selection.
Skills that are removed from the selection are deleted only where the files are
unchanged; edited files are kept and reported.

Check what is installed, and what an update would change, without writing
anything:

```bash
~/.ai-toolkit/install.sh --project --tools claude,codex --skills-status
```

Each skill has one of these statuses:

| Status | Meaning | What an install or sync does |
|---|---|---|
| `not installed` | Not present in the skill root | Installs it when selected |
| `up to date` | Identical to the release | Nothing |
| `update available` | Unchanged since the toolkit installed it; the release differs | Shows a diff and applies the update |
| `local changes` | Edited after the toolkit installed it | Shows a diff, keeps your file, and lists it under **Migration required** |
| `not managed` | Present but not installed by the toolkit | Same as local changes |

Diffs run from your file (`---`) to the release (`+++`), coloured when the
output is a terminal (set `NO_COLOR=1` to turn colour off). When anything is
listed under **Migration required**, the install or sync still completes but
exits with status 2. Move your customizations out of toolkit-managed files, for
example into a project-specific skill, then rerun with `--force`: each replaced
file is first saved as `<file>.bak.<timestamp>`.

## Lifecycle

Run project drift and synchronization commands from the project root:

```bash
~/.ai-toolkit/check-skills-update.sh
~/.ai-toolkit/sync-skills.sh --dry-run
~/.ai-toolkit/sync-skills.sh --add            # choose skills to add from a list
~/.ai-toolkit/sync-skills.sh --add kimball-model,smart-pr
~/.ai-toolkit/check-template-update.sh
~/.ai-toolkit/check-stores.sh --file ./stores.yml
~/.ai-toolkit/uninstall.sh --global
~/.ai-toolkit/uninstall.sh --global --confirm
```

Windows uses the equivalent PowerShell lifecycle commands:

```powershell
& "$HOME/.ai-toolkit/check-skills-update.ps1"
& "$HOME/.ai-toolkit/sync-skills.ps1" -DryRun
& "$HOME/.ai-toolkit/sync-skills.ps1" -Add
& "$HOME/.ai-toolkit/sync-skills.ps1" -Add kimball-model,smart-pr
& "$HOME/.ai-toolkit/check-template-update.ps1"
& "$HOME/.ai-toolkit/check-stores.ps1" -File ./stores.yml
& "$HOME/.ai-toolkit/uninstall.ps1" -Global
& "$HOME/.ai-toolkit/uninstall.ps1" -Global -Confirm
```

Verify the version stamp and a complete skill tree after installation:

```powershell
Test-Path (Join-Path $HOME '.ai-toolkit/version')
Test-Path (Join-Path $HOME '.ai-toolkit/skills/engineering-auditor/SKILL.md')
```

Drift checks compare every manifest-declared skill artifact, including declared
files under `agents/`, `references/`, and `scripts/`, while ignoring unmanifested
runtime caches. Synchronization copies only those declared artifacts, derives
roots exclusively from `.mindflayer-managed.tsv`, and refuses conventionally
named but unmanaged directories. Uninstall previews by default and preserves
modified files unless forced removal is explicitly requested.

## Adding an artifact

1. Add the source file.
2. Add exactly one `manifest.tsv` row with type, lifecycle version, consumers, and ownership.
3. Add or update validation for every declared consumer.
4. Run the complete test suite.

Do not maintain a second artifact list in lifecycle scripts or documentation.

## Adding a technology

1. Add one canonical entry to `config/technology-catalog.tsv`; use a namespaced identifier for an ecosystem component.
2. Add only verified, non-mutating Claude command patterns to `settings/claude/technology-permissions.tsv`. Guidance-only entries need no policy rows.
3. Bump the catalog or policy lifecycle version in `manifest.tsv` when it changes.
4. Test aliases, canonical ordering, mixed composition, deny precedence, and vendor-specific profile or connection requirements.
