# Project-Mindflayer

Portable configuration and operational skills for Claude Code, Codex, Gemini CLI, Cursor, and GitHub Copilot.

## Requirements

Linux and macOS require Bash 3.2+, `curl`, `shasum`, and `tar`. Native Windows requires Windows
10/11, PowerShell 7.4+ (the LTS baseline), and NTFS. The bootstrap uses an
existing Cosign executable or downloads a checksum-pinned temporary copy.
Python 3.12+, Git, and provider CLIs are capability-specific rather than core
installer requirements.
Installed lifecycle tools are Bash scripts on Linux/macOS and PowerShell scripts
on Windows. The release-draft helpers are AppleScript on macOS and a portable
Python `.eml` generator on Linux/Windows. Native Windows behavior is CI-tested on
GitHub's Windows runner. Git Bash is unsupported, WSL2 is best effort, and
Windows PowerShell 5.1 is unsupported. See the normative
[system requirements](docs/system-requirements.md) for network, filesystem,
consumer, capability-specific, and contributor dependencies.

## Install

Mode and tools are explicit. The bootstrap selects the platform, stages downloads outside the current directory, verifies the release bundle, and forwards all flags to the bundled installer.

Linux and macOS:

```bash
curl -fsSL --proto '=https' --proto-redir '=https' https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.sh | bash -s -- --global --tools claude,codex
```

Windows PowerShell:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.ps1'))) -Global -Tools claude,codex
```

Install into the current client repository by changing the mode and adding project flags:

```bash
curl -fsSL --proto '=https' --proto-redir '=https' https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.sh | bash -s -- --project --tools claude,codex --project-types data-platform,data-engineering --technologies databricks,python,sql --client "Client name" --prefix client
```

Common flags:

| Bash | PowerShell | Purpose |
|---|---|---|
| `--global` | `-Global` | Install user-level artifacts under `.ai-toolkit` and selected consumer roots |
| `--project` | `-Project` | Install into the current repository |
| `--tools LIST` | `-Tools LIST` | Required comma-separated consumers |
| `--project-types LIST` | `-ProjectTypes LIST` | Project classifications |
| `--technologies LIST` | `-Technologies LIST` | Technology identifiers |
| `--client NAME` | `-Client NAME` | Client name for a new project |
| `--prefix PREFIX` | `-Prefix PREFIX` | Resource prefix for a new project |
| `--force` | `-Force` | Back up and replace existing managed targets |

The one-line bootstrap is trusted through HTTPS and the repository release policy. It then verifies the selected archive checksum and GitHub Actions Sigstore identity before execution. Existing files are preserved unless `--force` is explicit.

## Contents

- Eleven public skills, including nested scripts and references.
- Portable global guidance plus legacy and composable project templates.
- Native project discovery: Claude and Gemini import `AGENTS.md`; Codex, Cursor, and Copilot read it directly.
- Manifest-driven install, drift, sync, update, store, and uninstall tooling.

`manifest.tsv` is the canonical artifact inventory. Its version column tracks artifact lifecycle versions. `VERSION` in `bootstrap.sh` and `install.sh` is the toolkit release, while project-template headers are schema versions. The technology catalog is semantic configuration, not a second artifact inventory.

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
