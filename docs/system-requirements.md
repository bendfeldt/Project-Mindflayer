# System Requirements

This document is the normative platform and dependency contract for installing,
running, and contributing to Project-Mindflayer.

## Supported platforms

| Platform | Runtime | Support level |
|---|---|---|
| Linux | Bash 3.2 or newer | Supported and tested |
| macOS | Bash 3.2 or newer | Supported and tested |
| Windows 10 or 11 | PowerShell 7.4 LTS or newer | Supported; native behavior is CI-tested on GitHub's Windows runner |
| Windows Subsystem for Linux 2 | Bash inside the Linux distribution | Best effort |
| Git Bash | — | Not supported |
| Windows PowerShell 5.1 | — | Not supported |

Native Windows operation does not require Git Bash or WSL. Git Bash is not a
supported runtime. Windows installations use PowerShell scripts and NTFS
directory junctions. Use an NTFS volume for the user profile and target
repository. WSL2 remains best effort and is not the native Windows test
environment.

## Installed artifact scope

| Artifact family | Installed platforms |
|---|---|
| Bash installer and lifecycle scripts | Linux and macOS |
| PowerShell installer and lifecycle scripts | Windows |
| Outlook AppleScript release-draft helper | macOS |
| Portable Python `.eml` release-draft generator | Linux and Windows |

Platform-specific artifacts are not installed on other platforms. Skill content
remains portable except where its capability explicitly selects one of these
platform helpers.

## Core installation requirements

### Linux and macOS

- Bash 3.2 or newer.
- `curl`, `shasum`, and `tar` for downloading, hashing, and extracting the
  signed release bundle. The bootstrap uses an
  existing Cosign executable or downloads a checksum-pinned temporary copy.
- Standard command-line utilities supplied by supported operating systems,
  including `awk`, `sed`, `grep`, `find`, `cksum`, `cmp`, `mktemp`, and `readlink`.
- Write access to the user profile for global installation or the target
  repository for project installation.

### Windows

- Windows 10 or 11 with PowerShell 7.4 or newer (`pwsh`); PowerShell 7.4 LTS is
  the supported baseline.
- An existing Cosign executable is optional; the bootstrap downloads a
  checksum-pinned temporary amd64 binary when Cosign is unavailable. Windows
  ARM64 uses Windows x64 emulation for that binary.
- NTFS directory-junction support and write access to the user profile.
- Write access to the target repository for project installation.

The installers do not install or authenticate assistant applications. Install
the selected assistant separately. No minimum assistant version is declared;
the assistant must support the discovery path shown below.

## Consumer support

| Consumer | Repository guidance | Global/project skill discovery |
|---|---|---|
| Claude | `CLAUDE.md` imports `AGENTS.md` | `.claude/skills/` |
| Codex | Reads `AGENTS.md` | `.agents/skills/` |
| Gemini | `GEMINI.md` imports `AGENTS.md` | Guidance only |
| Cursor | Reads `AGENTS.md` | Guidance only |
| Copilot | Reads `AGENTS.md` | `.copilot/skills/` globally and `.claude/skills/` in projects |

## Network access

Remote installation and lifecycle checks require outbound HTTPS access to:

- `github.com` for versioned release assets and pinned contributor tools.
- `api.github.com` for toolkit and external-store update checks.
- `tuf-repo-cdn.sigstore.dev` for Cosign trust-root metadata.
- `rekor.sigstore.dev` for Sigstore transparency-log verification when required.

Provider-specific skills may also require their service endpoints, such as
`dev.azure.com`, GitHub Enterprise, Databricks, Snowflake, or Terraform provider
registries. Proxy and certificate configuration remains an operating-environment
responsibility.

## Capability-specific dependencies

| Capability | Additional requirement |
|---|---|
| ADR, Kimball modeling, repository setup | No runtime beyond the selected assistant and toolkit installer |
| Branch cleanup, smart commit, smart PR, promotion workflows | Git; provider CLI when the workflow accesses a remote pull request |
| Engineering auditor | Python 3.12 or newer; bundled scripts use only the standard library |
| Release notes | Python 3.12 or newer; Azure CLI for Azure DevOps, GitHub CLI for GitHub, and existing provider authentication |
| Linux/Windows release email draft | Python 3.12 or newer; produces an unsent `.eml` file without authentication or recipients |
| macOS Outlook draft | Microsoft Outlook and `osascript`; the workflow creates an unsent draft only after approval |
| Terraform scaffold | Terraform CLI for formatting, initialization, and validation; relevant provider access when requested |
| Databricks operations | Databricks CLI and an explicitly user-selected `--profile <name>` |
| Snowflake operations | Snowflake CLI and an explicitly selected named connection |

Bundled Python utilities have no third-party Python package dependency. Optional
provider CLIs are required only when the selected workflow invokes them.

## Installation

The supported public entry point is a single release-hosted bootstrap command. Mode and tools remain mandatory.

Linux and macOS:

```bash
curl -fsSL --proto '=https' --proto-redir '=https' https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.sh | bash -s -- --global --tools claude,codex
```

Windows PowerShell:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.ps1'))) -Global -Tools claude,codex
```

The Bash wrapper supports Linux and macOS on amd64 and arm64. The PowerShell wrapper supports Windows AMD64 and ARM64; both use Sigstore's amd64 Windows Cosign binary, with x64 emulation on ARM64. Bootstrap downloads and extraction use a temporary directory and do not write into the caller's working directory.

The streamed wrapper is trusted through HTTPS and the repository's immutable-release policy. It downloads the pinned v3.7.0 platform bundle, verifies its published SHA-256 checksum and Sigstore identity, and only then invokes the bundled installer with the supplied flags. A separately authorized v3.7.0 release publication is required before the `releases/latest` commands resolve to this interface.

## Post-install verification

Linux and macOS:

```bash
test -f "$HOME/.ai-toolkit/version"
test -f "$HOME/.ai-toolkit/skills/engineering-auditor/SKILL.md"
```

Windows PowerShell:

```powershell
Test-Path (Join-Path $HOME '.ai-toolkit/version')
Test-Path (Join-Path $HOME '.ai-toolkit/skills/engineering-auditor/SKILL.md')
```

For Claude, Codex, or Copilot, also verify that the selected discovery root
contains the `engineering-auditor` skill directory or junction.

## Contributor requirements

- Git.
- Bash 3.2+ for Unix installer and lifecycle validation.
- PowerShell 7.4+ for Windows installer and lifecycle validation.
- Python 3.12+.
- ShellCheck 0.11.0.
- Network access for pinned validation-tool downloads when not already installed.

Run the complete local validation supported by the current platform:

```bash
bash tests/test-install.sh
python3.12 -m unittest discover -s tests -p 'test_*.py'
```

```powershell
pwsh -NoProfile -File tests/test-install.ps1
python -m unittest discover -s tests -p 'test_*.py'
```

CI validates Bash behavior on Ubuntu and macOS, PowerShell 7.4 compatibility,
native PowerShell behavior on GitHub's Windows Server runner, and Python behavior
on every CI runner. Windows 10 and 11 are supported target operating systems but
are not directly exercised by the hosted CI environment; WSL2 remains best effort.
