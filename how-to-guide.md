# How-to Guide

## Prerequisites

Use Bash 3.2+ on Linux or macOS, or PowerShell 7.4+ (the LTS baseline) on
Windows 10/11. Native Windows uses NTFS directory junctions and does not require
Git Bash or WSL. Git Bash is unsupported; WSL2 remains best effort. Installed
lifecycle tools are Bash scripts on Linux/macOS and PowerShell scripts on
Windows. Cosign is required to verify signed release bundles before execution.
Release-draft tooling installs the AppleScript helper on macOS and the
portable Python `.eml` generator on Linux/Windows. Native Windows behavior is
CI-tested on GitHub's Windows runner. Python 3.12+, Git, and provider CLIs are
required only by the capabilities identified in the normative
[system requirements](docs/system-requirements.md), which also defines supported
consumers, network access, and filesystem requirements.

## Global installation

Choose an explicit version and platform (`linux` or `macos`), verify the archive
against the release workflow identity, then choose tools explicitly:

```bash
version=3.6.0
platform=linux
asset="project-mindflayer-${version}-${platform}.tar.gz"
base="https://github.com/bendfeldt/Project-Mindflayer/releases/download/v${version}"
curl -fLO --proto '=https' "${base}/${asset}"
curl -fLO --proto '=https' "${base}/${asset}.sha256"
curl -fLO --proto '=https' "${base}/${asset}.sigstore.json"
shasum -a 256 -c "${asset}.sha256"
cosign verify-blob --bundle "${asset}.sigstore.json" \
  --certificate-identity "https://github.com/bendfeldt/Project-Mindflayer/.github/workflows/release.yml@refs/tags/v${version}" \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com "$asset"
tar -xzf "$asset"
installer="project-mindflayer-${version}-${platform}/install.sh"
"$installer" --global --tools claude,codex,copilot
```

Canonical skills remain under `~/.ai-toolkit/skills/`. Verified links expose them to selected consumers: Codex under `~/.agents/skills/`, Claude under `~/.claude/skills/`, and Copilot under `~/.copilot/skills/`.

Replacements are opt-in:

```bash
"$installer" --global --tools claude,codex,copilot --force
```

Windows global installation uses the same tool selection and replacement rules:

```powershell
$Version = '3.6.0'
$Asset = "project-mindflayer-$Version-windows.zip"
$Base = "https://github.com/bendfeldt/Project-Mindflayer/releases/download/v$Version"
Invoke-WebRequest "$Base/$Asset" -OutFile $Asset
Invoke-WebRequest "$Base/$Asset.sha256" -OutFile "$Asset.sha256"
Invoke-WebRequest "$Base/$Asset.sigstore.json" -OutFile "$Asset.sigstore.json"
$ExpectedHash = ((Get-Content "$Asset.sha256") -split '\s+')[0]
$ActualHash = (Get-FileHash $Asset -Algorithm SHA256).Hash.ToLowerInvariant()
if ($ActualHash -ne $ExpectedHash) { throw 'release checksum verification failed' }
cosign verify-blob --bundle "$Asset.sigstore.json" `
  --certificate-identity "https://github.com/bendfeldt/Project-Mindflayer/.github/workflows/release.yml@refs/tags/v$Version" `
  --certificate-oidc-issuer https://token.actions.githubusercontent.com $Asset
Expand-Archive $Asset -DestinationPath .
$Installer = ".\project-mindflayer-$Version-windows\install.ps1"
& $Installer -Global -Tools claude,codex,copilot
```

Every replaced path receives a timestamped sibling backup. The version stamp changes only after a complete installation succeeds.

## Project installation

Run in the target client repository, never from Project-Mindflayer itself:

```bash
"$installer" --project --tools claude,codex \
  --project-types data-platform,data-engineering \
  --technologies databricks,databricks:asset-bundles,dbt,python,sql \
  --client "Client" --prefix cl
```

Windows project installation:

```powershell
& $Installer -Project -Tools claude,codex `
  -ProjectTypes data-platform,data-engineering `
  -Technologies databricks,databricks:asset-bundles,dbt,python,sql `
  -Client 'Client' -Prefix cl
```

`--project-types` accepts one or more of `infrastructure`, `data-platform`, and `data-engineering`. All non-empty combinations are valid. `--technologies` accepts canonical identifiers from `config/technology-catalog.tsv`, including namespaced ecosystem components such as `databricks:unity-catalog`, `fabric:warehouse`, and `snowflake:snowpark`.

Project types are descriptive. Technologies compose guidance and Claude permissions. A namespaced component contributes its own policy but does not inherit its parent ecosystem's policy.

The legacy `--profile terraform|databricks|fabric` interface remains supported for existing automation and cannot be combined with the plural flags. It selects legacy project metadata and settings, not a Databricks authentication profile. Every Databricks command requires an explicitly user-selected `--profile <name>`. Snowflake commands requiring a connection must name it explicitly.

Existing managed projects enter join mode: `AGENTS.md` is preserved while missing selected-tool artifacts are added. Join mode reads plural metadata from new projects and falls back to the legacy `platform` field. Explicit flags must match stored metadata.

Project skills are complete real-file trees under `.agents/skills/` for Codex and `.claude/skills/` for Claude or Copilot. A mixed install writes shared trees once.

| Consumer | Project instruction entry point |
|---|---|
| Claude | `CLAUDE.md` imports `AGENTS.md` |
| Gemini | `GEMINI.md` imports `AGENTS.md` |
| Codex | Reads `AGENTS.md` directly |
| Cursor | Reads `AGENTS.md` directly |
| Copilot | Reads `AGENTS.md` directly |

Upgrades remove legacy Cursor and Copilot shims only when recorded ownership proof still matches. Modified or unowned files are preserved.

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
