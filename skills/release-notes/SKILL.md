---
name: release-notes
description: >
  Turn a release pull request into a testable release: map every child task of one or
  more parent work items to what actually changed, write "what changed / what to test"
  descriptions onto the tasks in Azure DevOps or GitHub, summarise the rest on the
  parent, and draft the test email to testers and stakeholders. Use when the user says
  "release notes", "/release-notes", "describe the release tasks", "prepare the test
  round", "testmail for the release", or points at a release PR and a work item full of
  empty tasks.
version: 2.0.0
updated: 2026-08-13
---

# Release Notes

A release PR lands with hundreds of changed files and a parent work item full of child
tasks with empty descriptions. Testers cannot see what changed in their model or report,
so they either test everything or nothing.

This skill closes that gap: it reads the actual diff, maps each task to the item it
covers, and produces per-task descriptions with concrete test points — then the parent
summary and the test email that gets people started.

Works against **Azure DevOps** and **GitHub**. One repo per run; several runs merge into
one email.

## Configuration

Settings live in two files, split by what is machine-specific. `scripts/config.py`
resolves both and hands the rest of the skill one merged view.

| File | Holds | Committed? |
|---|---|---|
| `~/.ai-toolkit/release-notes/engagements/<name>.json` | engagement root, repo roster, local paths, default work-item project | No — machine-specific |
| `<repo>/.claude/release-notes.config.json` | language, task title prefixes, item suffixes, merge-commit patterns | Yes — team-wide convention |

### First run in an engagement

Run `python3 scripts/config.py --validate`. If it reports a missing roster or repo
config, bootstrap before doing anything else:

1. **Discover the repos.** `python3 scripts/config.py --bootstrap --root <engagement root>`
   scans one level down, parses every git remote, and prints a proposed engagement file.
   Show the roster to the user and let them deselect repos. Add `--write` to save it.
2. **Ask only what cannot be derived.** Provider, org, project and repo all come from
   the git remote — never prompt for them, confirm them. One `AskUserQuestion` round for
   the rest: language, task title prefixes, work-item project (when the roster found more
   than one), and whether to draft mail in Outlook.
3. **Write the repo config** to `<repo>/.claude/release-notes.config.json` and tell the
   user to commit it, so their team inherits the same mapping.

Config lives outside `.claude/skills/` on purpose — `tools/sync-skills.sh` overwrites
that directory when refreshing skills and would destroy it.

### Per-run inputs

| Input | How to get it |
|---|---|
| Release PR | Ask. The PR that merges the release branch into main/prod |
| Parent work items | Ask. **Accept several** (`1234` or `1234,1235`) — children are merged across all of them |
| Release slug | Ask when the release spans repos; it groups the run artifacts |
| Language | From config; confirm each run |
| Environment, deadline, contact | Ask in the email step only. Anything unanswered stays a `[PLACEHOLDER]` |

Use `AskUserQuestion` for these, one round, before doing any work.

## Process

### 1. Context

```bash
python3 scripts/config.py --validate
```

This prints the effective config and checks the provider CLI is authenticated
(`az account show` / `gh auth status`). If auth fails, stop and tell the user which
command to run — never guess an account or org.

### 2. PR to diff range

See `references/providers.md` for the exact command per provider. The range is always
three-dot: `origin/<target>...origin/<source>`. Fetch both refs first. Warn if the PR is
already completed or abandoned, but continue — describing a just-merged release is normal.

### 3. Collect the tasks

Fetch the parents' children through the provider layer and save the result as
`tasks.json`. Children merged from several parents can overlap; the loader deduplicates
by id and applies the configured `child_types` filter, so overlapping parents and an
epic's non-task children are handled without extra work. Note which tasks already have a
description — those are protected in step 7.

### 4. Map tasks to changed folders

```bash
python3 scripts/collect_evidence.py --config --base origin/<target> --head origin/<source> \
    --tasks tasks.json --mapping-only
```

The mapping is by title prefix (`Model:` → `*.SemanticModel`, `Report:` → `*.Report`,
also pipeline/dataflow/notebook — all configurable) plus an exact match on the item name.
The script exits non-zero on any ambiguity or miss. It resolves the repo from the working
directory; pass `--repo <path>` when running from elsewhere.

**Show the user the mapping and both leftover lists** — tasks without a folder, and
changed folders without a task — and get it confirmed before anything is written.
Folders with no task are expected for CI, automation and orchestration; they belong in
the parent summary in step 8.

### 5. Extract evidence

```bash
python3 scripts/collect_evidence.py --config --base origin/<target> --head origin/<source> \
    --tasks tasks.json --out evidence.json
```

Per task it yields: file status counts, the commits that touched the folder with their
PR numbers, and — depending on item type — measures/columns/tables/partitions/data
sources for semantic models, or pages (resolved to display names), visual counts and
types, theme, bookmark and binding changes for reports. Unknown item types fall back to
a file and commit summary.

Read the evidence. Where it is thin or ambiguous (a table modified with no column change,
a partition line you cannot interpret), go back to `git diff` for that one folder rather
than guessing. Filtering out `lineageTag`, `annotation`, `summarizeBy` and `formatString`
lines makes TMDL diffs readable.

### 6. Write the descriptions

**You write the prose — never the script.** Follow `references/templates.md`: a Changes
section, a Test section, and a source line with PR numbers, file count and folder. The
table in that file maps change types to the test point they deserve.

Check the body format first: **HTML for Azure DevOps, Markdown for GitHub**. Both
renderings are in the templates file.

Two rules that matter more than style:

- Every bullet traces to something in the diff.
- A change with no user-visible effect says so plainly. Do not dress up a whitespace fix
  as a feature.

### 7. Preview, then publish

Show two representative descriptions (one model, one report) in full. Then:

```bash
python3 scripts/publish_descriptions.py --descriptions texts.json            # dry run
python3 scripts/publish_descriptions.py --descriptions texts.json --apply \
    --run <release-slug> --evidence evidence.json                            # after confirmation
```

Dry run is the default. Tasks that already have a description are skipped and listed;
only add `--overwrite` when the user explicitly asks — a filled-in description may be a
tester's own notes.

`--run` writes a per-repo artifact under `~/.ai-toolkit/release-notes/runs/<slug>/` for
the merge step. Pass it whenever the release touches more than one repo.

Verify by reading back: every task non-empty, containing both section headings and the
source line.

### 8. Summarise on the parent

Give each parent a description covering the release scope in numbers and, crucially,
the changes that have no task of their own (from `unclaimed_folders`): CI pipelines,
automation code, orchestration items. Same publish path as step 7.

### 9. Repeat per repo, then merge

For a release spanning several repos, run steps 2-8 in each repo with the same
`--run <release-slug>`. Then:

```bash
python3 scripts/merge_release.py --release <slug>                      # what was found
python3 scripts/merge_release.py --release <slug> --format html \
    --out body.html --subject-out subject.txt
```

The script assembles counts, per-repo grouping and one direct link per task, leaving
`[PLACEHOLDER]` markers for everything that needs judgement. Fill those in yourself,
following `references/templates.md`.

Verify before showing it: the number of task links equals the number of tasks, all
unique, titles matching the tracker verbatim, and all placeholders still intact.

### 10. Outlook draft (macOS)

```bash
osascript scripts/make_outlook_draft.applescript subject.txt body.html
```

Creates an unsent draft with no recipients. Confirm it exists by counting Outlook's
outgoing messages before and after and matching on the subject — AppleScript reports
success even when the window never opened.

Outside macOS, or without Outlook, skip this step and hand over the Markdown file.

## Rules

- **Never send the email.** Create a draft, no recipients, and let the user finish it.
- **Never overwrite a non-empty description** without `--overwrite` and explicit consent.
- **Never invent a change.** If the diff does not support a claim, leave it out.
- **Never invent a deadline, environment, sender or contact.** They stay placeholders.
- **Confirm the mapping before writing to the tracker.** A wrong mapping puts the wrong
  test instructions on someone's task, which is worse than no instructions.
- **Never guess an org, project or account.** They come from the git remote or the config.
- Language is the user's choice per run — but keep one language throughout, including
  the section headings.

## Reruns

The skill is safe to run again on the same release: the mapping is deterministic, and
the publish step skips tasks that already have descriptions. Re-running after new commits
land on the release branch picks them up — regenerate the evidence rather than editing
the old descriptions by hand.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `not inside a git repository` | Run from the repo, or pass `--repo <path>` |
| `no engagement roster matches org …` | Bootstrap has not run for this engagement |
| Mapping finds no candidates | Task title prefix is not in `title_prefixes`, or the item folder suffix is not in `item_suffixes` |
| All commits show `pr: null` | The team uses a custom merge template — set `merge_commit_patterns` |
| GitHub parent returns no children | The repo tracks children as task-list checkboxes, which is not supported. Say so; do not guess the list |
| Non-ASCII project name in URLs | Expected — remotes percent-encode it and `config.py` decodes it |

---

**Promoted from:** a client engagement's `.claude/skills/release-notes/`, generalized for
Azure DevOps and GitHub across multiple repos and projects.
