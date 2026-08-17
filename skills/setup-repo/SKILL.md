---
name: setup-repo
description: Configure a client repository with Project-Mindflayer by collecting project types, technologies, client identity, optional resource prefix, and selected assistant tools.
---

# Set Up Repository

Delegate installation behavior to the toolkit installer for the host platform:
`install.sh` on Linux/macOS and `install.ps1` on Windows 10/11 with PowerShell
7.4 or newer (7.4 LTS baseline). Do not recreate it. Native Windows behavior is
CI-tested on GitHub's Windows runner; WSL2 remains best effort. Treat Python,
Git, and provider CLIs as capability-specific dependencies defined by the system
requirements, not as prerequisites for every setup. Git Bash is unsupported;
when a selected capability needs Python, require Python 3.12 or newer.

1. Confirm the target is not the Project-Mindflayer distribution repository.
2. Detect available assistants and ask for the explicit tool list to configure.
3. For a new project, collect:
   - One or more project types: `infrastructure`, `data-platform`, `data-engineering`.
   - Technologies from the installed `~/.ai-toolkit/config/technology-catalog.tsv`. If it is unavailable, read the canonical repository copy; never invent an identifier. Use namespaced identifiers for platform components.
   - Client name.
   - Resource prefix only when the repository uses one.
4. Use the release-hosted bootstrap entry point, which verifies the platform
   bundle checksum and Sigstore identity before invoking the bundled installer.
   Mode and tools stay explicit. Preview and obtain approval for:

```bash
curl -fsSL --proto '=https' --proto-redir '=https' https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.sh | bash -s -- --project --tools <comma-separated-tools> --project-types <comma-separated-project-types> --technologies <comma-separated-technologies> --client "<client>" [--prefix <prefix>]
```

On Windows, preview the equivalent native PowerShell command:

```powershell
& ([scriptblock]::Create((Invoke-RestMethod 'https://github.com/bendfeldt/Project-Mindflayer/releases/latest/download/bootstrap.ps1'))) -Project -Tools <comma-separated-tools> -ProjectTypes <comma-separated-project-types> -Technologies <comma-separated-technologies> -Client '<client>' [-Prefix <prefix>]
```

When the toolkit is already installed globally, preview the installed installer
instead: `~/.ai-toolkit/install.sh` on Linux/macOS or `~/.ai-toolkit/install.ps1`
on Windows, with the same flags.

5. Run it in the target repository and report only tool-conditional artifacts actually created.
6. Validate project instruction discovery:
   - Claude: `CLAUDE.md` is exactly `@AGENTS.md`.
   - Gemini: `GEMINI.md` is exactly `@AGENTS.md`.
   - Codex, Cursor, Copilot: use root `AGENTS.md` directly with no compatibility shim.
7. Validate selected settings and complete skill trees.

Project types are descriptive and may be combined freely. Technologies compose guidance and Claude permissions. A namespaced component identifies its ecosystem but does not inherit the parent ecosystem's permissions.

Existing automation may continue using `--profile terraform|databricks|fabric`; never combine that legacy interface with the plural flags. A Databricks technology or legacy profile never selects authentication. Never invent or auto-select a Databricks CLI profile, and require `--profile <name>` on every Databricks command.

Join mode preserves `AGENTS.md`. If explicit classification flags are supplied, they must match stored metadata.
