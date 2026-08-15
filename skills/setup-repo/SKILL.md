---
name: setup-repo
description: Configure a client repository with Project-Mindflayer after collecting its platform, client identity, prefix, and selected assistant tools.
---

# Set Up Repository

Delegate installation behavior to the toolkit `install.sh`; do not recreate it.

1. Confirm the target is not the Project-Mindflayer distribution repository.
2. Detect available assistants and ask for the explicit tool list to configure.
3. Ask for platform (`terraform`, `databricks`, or `fabric`), client name, and resource prefix.
4. Preview and obtain approval for:

```bash
curl -fsSL --proto '=https' \
  https://raw.githubusercontent.com/bendfeldt/Project-Mindflayer/main/install.sh \
  | bash -s -- --project \
  --tools <comma-separated-tools> --profile <platform> \
  --client "<client>" --prefix <prefix>
```

5. Run it from the target repository and report only the tool-conditional artifacts actually created.
6. Validate project instruction discovery:
   - Claude: `CLAUDE.md` is exactly `@AGENTS.md`.
   - Gemini: `GEMINI.md` is exactly `@AGENTS.md`.
   - Codex, Cursor, and Copilot: use root `AGENTS.md` directly with no compatibility shim.
7. Validate the selected settings and complete skill trees.

A Databricks platform profile selects the permission template; it is not an authentication profile. Never invent or auto-select a Databricks CLI profile.
