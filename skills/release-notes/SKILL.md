---
name: release-notes
description: Prepare testable release notes from pull-request diffs for Azure DevOps or GitHub, including evidence mapping, dry-run-gated child Task or sub-issue creation, description updates, release summaries, and tester email drafts. Use when turning a release PR into work-item documentation and test instructions.
---

# Release Notes

Resolve all scripts relative to this skill directory, never the current working directory.
Invoke them with `python3` on Linux and macOS, and with `python` on native Windows.

1. Read [provider behavior](references/providers.md) and [templates](references/templates.md).
2. Resolve configuration precedence: explicit CLI values, repository config, then documented defaults. Reject ambiguous project or work-item mappings.
3. Ask which PR the release notes should cover. Take `--base` and `--head` from that PR's target and source branches. If there is no PR, ask which two branches or commits to compare, and plan with `--compare` instead of `--pr-id`.
4. Ask where the release Tasks go: one User Story or Issue the user names (`--parent-id`), or the original User Stories linked to the PRs that brought the code (`--original-parents`). Never pick a parent yourself.
5. Run `scripts/collect_evidence.py` using an absolute path derived from the skill directory. Omit `--tasks` when missing child Tasks must be planned; this produces folder-keyed task candidates, or asset-keyed ones where the repository config defines `asset_rules`.
6. Prepare provider-formatted descriptions keyed by each evidence `task_key`: HTML for Azure DevOps, Markdown for GitHub.
7. Run `scripts/manage_tasks.py plan` with the source (`--pr-id <PR>` or `--compare`) and the parent choice (`--parent-id <US>` or `--original-parents`). If planning lists Tasks with no linked User Story, ask the user for one and plan again with `--fallback-parent-id <US>`.
8. Run `scripts/manage_tasks.py compose` with every pair plan file. Before changing anything, show the user the composed summary table (Task, operation, parent, PR(s) it came in with, assignee) and every unresolved item. Pair plans are never directly applicable.
9. Ask for explicit approval, then run `scripts/manage_tasks.py apply --plan <release-plan>`. Apply must consume the reviewed release plan, preflight every pair before writing, and stop on integrity, git, PR, parent, or child drift.
10. Run `scripts/merge_release.py` using an absolute path derived from the skill directory; verify every PR and User Story link is present.
11. Keep `publish_descriptions.py` for description-only updates to existing items. It dry-runs by default and refuses overwrite unless explicitly authorized. With `--evidence`, it also assigns unassigned items to their top contributor; both dry runs show the planned assignee (see [provider behavior](references/providers.md#assignee)).
12. Resolve `email.tool` from the effective config, which reconciles the
    recorded tool with the platform running it: `outlook-macos` on macOS, `eml`
    on Linux, native Windows, and on macOS without Outlook; no draft mechanism
    on other platforms. Report any platform fall-back the config reports.
    Review the completed subject and HTML first. Ask before opening Outlook or
    writing a `.eml`, then add `--write` to `make_email_draft.py --open`
    (`outlook-macos`) or `--out <draft.eml>` (`eml`); its default is a
    non-writing dry run and replacement additionally requires `--overwrite`.
13. Ask before any remote write or local draft creation. A draft must have no
    recipients and must never be sent automatically.
14. Report evidence gaps, pair conflicts, created/reused Tasks, and generated local artifacts.

Use installed helpers from `~/.ai-toolkit/skills/release-notes/scripts/` for global installs or the installed project skill root for project installs.
