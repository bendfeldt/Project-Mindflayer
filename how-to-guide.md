# How-to Guide

## Prerequisites

Use Bash 3.2+ on Linux or macOS, or PowerShell 7.4+ (the LTS baseline) on
Windows 10/11. Native Windows uses NTFS directory junctions and does not require
Git Bash or WSL. Git Bash is unsupported; WSL2 remains best effort. Installed
lifecycle tools are Bash scripts on Linux/macOS and PowerShell scripts on
Windows. The bootstrap uses an existing Cosign executable or downloads a
checksum-pinned temporary copy to verify signed release bundles before execution.
Release-draft tooling installs the AppleScript helper on macOS and the
portable Python `.eml` generator on Linux/Windows. Native Windows behavior is
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

## Lifecycle

Run project drift and synchronization commands from the project root:

```bash
~/.ai-toolkit/check-skills-update.sh
~/.ai-toolkit/sync-skills.sh --dry-run
~/.ai-toolkit/check-template-update.sh
~/.ai-toolkit/check-stores.sh --file ./stores.yml
~/.ai-toolkit/uninstall.sh --global
~/.ai-toolkit/uninstall.sh --global --confirm
```

Windows uses the equivalent PowerShell lifecycle commands:

```powershell
& "$HOME/.ai-toolkit/check-skills-update.ps1"
& "$HOME/.ai-toolkit/sync-skills.ps1" -DryRun
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
