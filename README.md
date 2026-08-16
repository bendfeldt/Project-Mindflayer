# Project-Mindflayer

Portable configuration and operational skills for Claude Code, Codex, Gemini CLI, Cursor, and GitHub Copilot.

## Requirements

Linux and macOS require Bash 3.2+, `curl`, and Cosign. Native Windows requires Windows
10/11, PowerShell 7.4+ (the LTS baseline), and NTFS. Python 3.12+, Git, and
provider CLIs are capability-specific rather than core installer requirements.
Installed lifecycle tools are Bash scripts on Linux/macOS and PowerShell scripts
on Windows. The release-draft helpers are AppleScript on macOS and a portable
Python `.eml` generator on Linux/Windows. Native Windows behavior is CI-tested on
GitHub's Windows runner. Git Bash is unsupported, WSL2 is best effort, and
Windows PowerShell 5.1 is unsupported. See the normative
[system requirements](docs/system-requirements.md) for network, filesystem,
consumer, capability-specific, and contributor dependencies.

## Install

Choose an explicit release and verify its GitHub Actions identity before running
the bundled installer. Set `platform` to `linux` or `macos`:

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
"project-mindflayer-${version}-${platform}/install.sh" --global --tools claude,codex
```

On Windows PowerShell:

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
& ".\project-mindflayer-$Version-windows\install.ps1" -Global -Tools claude,codex
```

Install into a client repository:

```bash
"project-mindflayer-${version}-${platform}/install.sh" --project \
  --tools claude,codex \
  --project-types infrastructure,data-platform,data-engineering \
  --technologies terraform,databricks,dbt,python,sql \
  --client "Client name" --prefix client
```

Run the project command from the target repository. Project types and technologies are independent sets, so a monorepo can combine infrastructure, platform, and engineering responsibilities across Databricks, Fabric, Snowflake, and other cataloged technologies.

Installers read only from the verified, platform-scoped release bundle. Existing
files are skipped by default; `--force` explicitly authorizes replacement and
creates timestamped backups.

Global skills live in the canonical `~/.ai-toolkit/skills/` store. One capability-driven workflow exposes them through the discovery roots of every selected skill-aware tool. Project installs commit each complete skill tree once per distinct discovery root.

## Contents

- Eleven public skills, including nested scripts and references.
- Portable global guidance plus legacy and composable project templates.
- Native project discovery: Claude and Gemini import `AGENTS.md`; Codex, Cursor, and Copilot read it directly.
- Manifest-driven install, drift, sync, update, store, and uninstall tooling.

`manifest.tsv` is the canonical artifact inventory. Its version column tracks artifact lifecycle versions. `VERSION` in `install.sh` is the toolkit release, while project-template headers are schema versions. The technology catalog is semantic configuration, not a second artifact inventory.

See [architecture](docs/architecture.md), [operating standards](docs/operating-standards.md), [system requirements](docs/system-requirements.md), and the [how-to guide](how-to-guide.md).

## Safety

The installer never silently replaces existing agent configuration. Drift, synchronization, and uninstall operate only on paths recorded as toolkit-owned. Uninstall is dry-run by default. The toolkit repository deliberately cannot install its own generated `.claude/` or `.agents/` client layout.

## Validate

The Bash test suite requires ShellCheck `0.11.0`, matching the pinned CI version.

```bash
bash tests/test-install.sh
python3.12 -m unittest discover -s tests -p 'test_*.py'
```

```powershell
pwsh -NoProfile -File tests/test-install.ps1
python -m unittest discover -s tests -p 'test_*.py'
```
