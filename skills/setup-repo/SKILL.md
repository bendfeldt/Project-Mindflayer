---
name: setup-repo
description: Configure a client repository with Project-Mindflayer after collecting its platform, client identity, prefix, and selected assistant tools.
---

# Set Up Repository

Delegate installation behavior to the toolkit `install.sh`; do not recreate it.

1. Confirm the target is not the Project-Mindflayer distribution repository.
2. Detect available assistants, then ask which explicit tool list to configure.
3. Ask for platform (`terraform`, `databricks`, or `fabric`), client name, and resource prefix.
4. Preview and obtain approval for:

```bash
bash /path/to/Project-Mindflayer/install.sh --project \
  --tools <comma-separated-tools> --profile <platform> \
  --client "<client>" --prefix <prefix> --local
```

5. Run it and report only tool-conditional artifacts actually created.
6. Validate the generated instructions and selected settings.

A Databricks platform profile selects a permission template; it is not an authentication profile. Never invent or auto-select a Databricks CLI profile.
