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

### HTML body for Outlook and `.eml` drafts

Wrap in a single `<div style="font-family:Calibri,Arial,sans-serif;font-size:11pt;color:#201F1E;">`,
use `<p>`, `<ul>`, `<b>`, `<a href>` only — no CSS classes, no external assets.
Outlook renders that reliably and it survives copy-paste into a reply.

### Draft creation by platform

Invoke the generator with `python3` on Linux and macOS and with `python` on
native Windows.

- **macOS (`email.tool: outlook-macos`, the default):** first run
  `python3 make_outlook_draft.py <subject.txt> <body.html>` as a dry run; it
  checks that `osascript` and Outlook are present without contacting Outlook.
  After explicit approval, repeat with `--write`. The wrapper runs
  `make_outlook_draft.applescript`, which launches Outlook, waits up to two
  minutes, and opens an unsent draft with no recipients. When Outlook is not
  installed, or the engagement records `email.tool: eml`, use the `.eml` route
  below instead — the generator is installed on macOS as well.
  If the wrapper fails, relay its explanation verbatim and offer the `.eml`
  route; never retry or switch routes without asking. Common causes:
  - `-1743` — the app running the agent lost permission to control Outlook,
    typically after a macOS upgrade. Re-enable it in System Settings → Privacy
    & Security → Automation, or `tccutil reset AppleEvents <app bundle id>`.
  - `-1708`, `-10000`, `-2741` — New Outlook does not accept the scripting
    command; switch to Legacy Outlook.
  - `-1712` — Outlook was still starting; finish its first-launch screens and
    retry.
  - `-600`, `-10814` — Outlook could not be found or launched.
- **`.eml` route (`email.tool: eml`; the default on Linux and Windows):** first
  run `python3 make_email_draft.py <subject.txt> <body.html> --out <draft.eml>`
  as a non-writing dry run. After the user approves the completed subject and
  body, repeat with `--write`. Existing files are preserved unless replacement is
  separately approved and `--overwrite` is added.
- **Other platforms (`email.tool: none`):** produce the subject and HTML files
  only; do not choose another mail client implicitly.

`config.py` reconciles a recorded `email.tool` with the platform actually running
it, so an engagement bootstrapped on macOS falls back to `eml` on Linux or
Windows instead of selecting Outlook there. `--validate` reports that fall-back;
report it to the user rather than treating it as the configured choice.

The `.eml` generator uses only the Python standard library, emits SMTP CRLF
line endings, an RFC-encoded UTF-8 subject and HTML content, sets `X-Unsent: 1`,
and omits `To`, `Cc`, and `Bcc`. It never opens a mail client or sends mail.
Every artifact the skill writes — subject, HTML body, evidence, plans, run
results — is UTF-8 with LF endings on every platform, so a release can be
prepared on one machine and drafted on another.
