---
name: release-notes
description: Prepare testable release notes from pull-request diffs for Azure DevOps or GitHub, including evidence mapping, dry-run-gated Azure DevOps child Task creation, description updates, release summaries, and tester email drafts. Use when turning a release PR into work-item documentation and test instructions.
---

# Release Notes

Resolve all scripts relative to this skill directory, never the current working directory.

1. Read [provider behavior](references/providers.md) and [templates](references/templates.md).
2. Resolve configuration precedence: explicit CLI values, repository config, then documented defaults. Reject ambiguous project or work-item mappings.
3. Run `scripts/collect_evidence.py` using an absolute path derived from the skill directory. Omit `--tasks` when missing Azure DevOps child Tasks must be planned; this produces folder-keyed task candidates.
4. Prepare provider-formatted descriptions keyed by each evidence `task_key`.
5. For each Azure DevOps PR/User Story pair, run `scripts/manage_tasks.py plan --pr-id <PR> --parent-id <US>`. Each PR and User Story must appear in exactly one pair.
6. Run `scripts/manage_tasks.py compose` with every pair plan, including a single pair. Review the complete composed dry run. Pair plans are never directly applicable.
7. Ask for explicit approval, then run `scripts/manage_tasks.py apply --plan <release-plan>`. Apply must consume the reviewed release plan, preflight every pair before writing, and stop on integrity, git, PR, parent, or child drift.
8. Run `scripts/merge_release.py` using an absolute path derived from the skill directory; verify every PR and User Story link is present.
9. Keep `publish_descriptions.py` for description-only updates to existing items. It dry-runs by default and refuses overwrite unless explicitly authorized.
10. Ask before any remote write or Outlook draft creation.
11. Report evidence gaps, pair conflicts, created/reused Tasks, and generated local artifacts.

Use installed helpers from `~/.ai-toolkit/skills/release-notes/scripts/` for global installs or the installed project skill root for project installs.
