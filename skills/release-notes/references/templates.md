# Templates — release-notes

Two things vary and must be settled before writing a single description:

- **Body format** comes from the provider, not from preference. Azure DevOps
  stores `System.Description` as HTML; GitHub issue bodies are Markdown. Check
  `provider.body_format` and use the matching block below.
- **Language** comes from the run (`language` in the repo config, overridable
  with `--lang`). Keep one language throughout, including section headings.

## Section headings by language

| Key | Danish | English |
|---|---|---|
| Changes | `Ændringer` | `Changes` |
| Test | `Test` | `Test` |
| Source | `Kilde` | `Source` |
| Files changed | `filer ændret` | `files changed` |
| Changes with no task | `Ændringer uden selvstændig opgave` | `Changes with no task of their own` |

---

## Task description — HTML (Azure DevOps `System.Description`)

When planning missing child Tasks, store each rendered HTML body in `descriptions.json` under the corresponding evidence `task_key` (the deployable folder path).

```html
<b>Ændringer</b>
<ul>
  <li>…</li>
</ul>
<b>Test</b>
<ul>
  <li>…</li>
</ul>
<p><i>Kilde: PR 1234, PR 1230 &middot; 9 filer ændret &middot; solution/&lt;area&gt;/models/&lt;Model Name&gt;.SemanticModel</i></p>
```

Escape `<` and `>` in DAX/M snippets (`&lt;`, `&gt;`), and use `<i>` for object names.

## Task description — Markdown (GitHub issue body)

```markdown
**Changes**

- …

**Test**

- …

*Source: PR #1234, PR #1230 · 9 files changed · solution/<area>/models/<Model Name>.SemanticModel*
```

Fence DAX/M snippets in backticks instead of escaping them.

## Rules, both formats

- 2-5 bullets per section. More than that and nobody reads it.
- Every bullet traces to the diff. Name the object that changed (measure, table,
  page, partition, binding), not the file path.
- A change with no user-visible effect is described as exactly that. Example:
  *"Only a correction to the description text (a redundant space) in the measure
  documentation. No changes to partitions, data sources, columns or measure
  expressions."*
- The source line always carries PR numbers, file count and folder — that is what
  makes a description auditable against the diff.

### Deriving test points from the change type

| Change in the diff | Test bullet to write |
|---|---|
| Partition filter / schema / database swap | Refresh runs clean; row counts and period coverage match the source |
| New or changed measure | The value shows up where expected and respects the login/tenant filter |
| Removed column | No visual breaks on the removed field |
| Dimension switched table ↔ view | Same member values and counts as before the switch |
| New report page | The page loads, shows data, and navigation/bookmarks reach it |
| Deleted report page | Nothing navigates to the deleted page any more |
| Model binding (`definition*.pbir`) changed | Report binds to the intended semantic model in the target workspace |
| Item moved or renamed | Data source bindings survive deployment and figures match the pre-move numbers |
| Metadata / whitespace only | Quick check that it still deploys and figures are unchanged |

---

## Parent item summary

HTML:

```html
<p>Release <b>{name}</b> — PR <a href="{pr_url}">{pr_id}</a> ({source} → {target}).
{n_files} changed files across {n_models} semantic models and {n_reports} reports,
each with a child task carrying its own description and test points.</p>
<b>Ændringer uden selvstændig opgave</b>
<ul><li>…</li></ul>
<b>Test</b>
<ul><li>…</li></ul>
```

The "no task of their own" list comes from `unclaimed_folders` in the evidence
file — typically CI pipelines, automation code and orchestration items.

---

## Test email

`merge_release.py` assembles the skeleton — counts, per-repo grouping, one link
per task, and `[PLACEHOLDER]` markers. You fill the placeholders; the script
never writes prose.

Structure, in order:

1. **Subject** — `Test af release {name} — frist [FRIST]` /
   `Test of release {name} — deadline [DEADLINE]`
2. **Opening** — 3-4 lines: scope in numbers (models, reports, repos), and the two
   or three cross-cutting themes of the release.
3. **How to test** — numbered: find your task, test in `[ENVIRONMENT]`, set to
   Closed when approved, comment and set to `[STATUS]` on failure, deadline `[DEADLINE]`.
4. **What changed** — grouped by repo, then by theme. Each group: 1-3 lines of
   context, then one bullet per task as a direct link, with a short parenthesis
   only where the task deviates from the group's headline (*"new report"*,
   *"text fix only"*, *"four new expense pages"*).
5. **Pay particular attention to** — 2-4 genuine risk points: moved items,
   behaviour that legitimately changes the numbers, and tasks needing almost no testing.
6. **Links** — every PR and its paired User Story; do not collapse multiple pairs from the same repository.
7. **Sign-off** — `[CONTACT]` and `[SENDER]`.

Placeholders are written in `[CAPITALS IN BRACKETS]` so they are impossible to
miss before sending. Never invent a deadline, environment, sender or contact.

### HTML body for Outlook

Wrap in a single `<div style="font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#201F1E;">`,
use `<p>`, `<ul>`, `<b>`, `<a href>` only — no CSS classes, no external assets.
Outlook renders that reliably and it survives copy-paste into a reply.
