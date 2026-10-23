# Providers — Azure DevOps and GitHub

Commands use Bash line continuation in examples. On native Windows, run the
same CLI arguments from PowerShell using backtick continuation and invoke Python
scripts with `python` instead of `python3`.

`scripts/providers.py` hides these differences behind one interface. This file is
the reference for when you need to go around it — debugging an API response,
checking auth, or reading a work item by hand.

## Auth

| Provider | Check | Fix |
|---|---|---|
| Azure DevOps | `az account show` | `az login` |
| GitHub | `gh auth status` | `gh auth login` |

Never guess an account, org or tenant. If the check fails, stop and tell the user
which command to run — `config.py --validate` reports both in one go.

The scripts locate both CLIs through `PATH` rather than assuming a file name.
This matters on Windows, where the Azure CLI is installed as `az.cmd`: a command
shim cannot be launched directly and is run through the command processor, so
arguments must not contain `& | < > ^ "` or line breaks. Nothing free-form is
passed on the command line — work-item bodies always travel in a request-body
file — and both CLIs are read as UTF-8 regardless of the console code page, so
non-ASCII titles survive on every platform.

The Azure DevOps REST resource id is `499b84ac-1321-427f-aa17-267ca6975798`.
`az rest --resource <id>` handles the token exchange; there is no PAT to manage.

## Concept mapping

| Concept | Azure DevOps | GitHub |
|---|---|---|
| Parent | User Story / Feature | Issue |
| Child | Task (typed) | Sub-issue (untyped) |
| Hierarchy link | `System.LinkTypes.Hierarchy-Forward` | `/issues/{n}/sub_issues` |
| Description field | `System.Description` | `body` |
| Description format | **HTML** | **Markdown** |
| Item URL | `{org}/{project}/_workitems/edit/{id}` | `{host}/{owner}/{repo}/issues/{n}` |

The typing difference matters. An Azure DevOps parent's hierarchy can hold Tasks,
User Stories and Features, and only Tasks are testable units — hence
`child_types: ["Task"]`. GitHub sub-issues carry no type, so `child_types: []`
keeps every child.

## Commands

### Pull request → diff range

```bash
# Azure DevOps
az repos pr show --id <PR> --org https://dev.azure.com/<org> -o json
# -> sourceRefName / targetRefName, prefixed refs/heads/

# GitHub
gh pr view <PR> --repo <owner>/<repo> \
    --json number,title,state,headRefName,baseRefName,url
```

The range is always three-dot: `origin/<target>...origin/<source>`. Fetch both
refs first. Warn if the PR is completed or abandoned, but continue — describing a
just-merged release is normal.

### Parent → children

```bash
# Azure DevOps: relations first, then one batch call
az rest --resource 499b84ac-1321-427f-aa17-267ca6975798 \
    --url "https://dev.azure.com/<org>/<project>/_apis/wit/workitems/<ID>?api-version=7.0&\$expand=all"
az rest --resource 499b84ac-1321-427f-aa17-267ca6975798 \
    --url "https://dev.azure.com/<org>/<project>/_apis/wit/workitems?ids=<ids>&api-version=7.0&\$expand=all"

# GitHub
gh api -H "X-GitHub-Api-Version: 2026-03-10" --paginate \
    "/repos/<owner>/<repo>/issues/<ID>/sub_issues?per_page=100"
```

The Azure DevOps batch endpoint caps at 200 ids per call; `providers.py` chunks
at 190.

**GitHub repos not using sub-issues.** Some teams track children as task-list
checkboxes in the parent body instead. `providers.py` does not parse those — if
`fetch_children` returns nothing for a parent that visibly has children, this is
why. Say so plainly rather than guessing at the list.

### Planning and creating child Tasks

Child items are Tasks on Azure DevOps and sub-issues on GitHub. Discover candidates without existing IDs, then create a saved dry-run plan:

```bash
python3 "$SKILL_DIR/scripts/collect_evidence.py" \
  --base origin/main --head origin/releases/rel_1 \
  --config --out evidence.json

python3 "$SKILL_DIR/scripts/manage_tasks.py" plan \
  --pr-id <PR_ID> --parent-id <USER_STORY_ID> \
  --evidence evidence.json --descriptions descriptions.json \
  --out pair-plan.json
```

`descriptions.json` maps each evidence `task_key` to a description in the provider's body format: HTML for Azure DevOps, Markdown for GitHub. Pair planning fetches the PR and parent state, verifies the evidence refs, reuses one unambiguous child match, and validates every missing child. Azure DevOps uses its create endpoint with `validateOnly=true`. GitHub has no validate-only create, so it checks the title, the parent, and the assignee. Planning writes no work items.

**Release source.**
- **A PR:** pass `--pr-id`. The evidence refs must match the PR's target and source branches.
- **No PR:** pass `--compare` instead. The plan pins the evidence's `base` and `head` commits, apply refuses to run if either ref has moved, and the release is identified by `base..head`.

**Parent.**
- **Named parent:** `--parent-id` puts every Task under that User Story or Issue.
- **Original parents:** `--original-parents` puts each Task under the User Story linked to its PRs.
  - **Links:** Azure DevOps uses `az repos pr work-item list`; GitHub uses the PR's `closingIssuesReferences`.
  - **Which links count:** a PR counts only when it links exactly one item of an allowed `parent_types`.
  - **Choosing the parent:** each Task goes to the parent holding most of its PR lines, and a tie goes to the newest merge. This matches the assignee rule.
  - **No usable link:** planning stops and lists Tasks whose PRs link no parent (or several) until `--fallback-parent-id <id>` places them.
  - **Output:** the plan file then holds a list with one pair per parent.

Compose every plan file into the only applicable plan type:

```bash
python3 "$SKILL_DIR/scripts/manage_tasks.py" compose \
  --release rel_1 \
  --pair-plan repo-a-pr-123.json \
  --pair-plan repo-b-pr-456.json \
  --out release-plan.json
```

**Composition rules:**
- A User Story takes Tasks from one source only.
- A source may feed several User Stories, which is how `--original-parents` works.
- A Task key appears once per source.
- Pairs may come from different repositories. If two PRs change the same deployable folder, each paired User Story keeps its own child Task.

**Summary table.** Before anything changes, the compose dry run prints one row per Task. Show it to the user together with every unresolved item:

| Task | Operation | Parent | PR(s) | Assignee |
| --- | --- | --- | --- | --- |
| Model: foo/sales | create | User Story 812 | #12, #11 | bob@contoso.com |
| Report: Sales | reuse 1000 (skip description) | User Story 812 | #11, direct commit | none (keep assignee) |

After the user reviews the table and explicitly approves it:

```bash
python3 "$SKILL_DIR/scripts/manage_tasks.py" apply --plan release-plan.json
```

Apply rejects pair plans. It verifies the composed plan and every embedded pair, preflights all repositories, PRs, parents, and child items before the first write, then applies pairs sequentially with resumable result state. New Azure DevOps Tasks inherit the parent Area Path and Iteration Path, and the Azure DevOps process defaults set their state. The assignee follows the rule under [Assignee](#assignee).

Each applied pair writes `<repo>-<pr-id or base..head>-<parent>.json` under the release run directory. `merge_release.py` groups these artifacts by pair and links both the PR (when there is one) and the parent.

**Create calls:**
- **Azure DevOps:** REST 7.1 JSON Patch with `System.Title`, `System.Description`, `System.AreaPath`, `System.IterationPath`, the optional `System.AssignedTo`, and a `System.LinkTypes.Hierarchy-Reverse` parent relation.
- **GitHub:**
  1. `POST /repos/{owner}/{repo}/issues` with the title, body and optional assignee.
  2. `POST /repos/{owner}/{repo}/issues/{parent}/sub_issues` with the new issue's `id`.

  If the second call fails, the error names the created issue. Link it by hand before re-running, so the rerun reuses it instead of creating a duplicate.

The default allowed parent type is `User Story`. Teams using another Azure DevOps process must set `parent_types` explicitly in repository config. Override generated title labels with the suffix-to-prefix `task_title_prefixes` mapping; parsing of existing titles continues to use `title_prefixes`.

#### Asset-level tasks

When one deployable folder holds many independently testable assets (dbt models, ingestion sources), add `asset_rules` to the repository config. Each rule has a `kind` and a regex `pattern` with named groups `root` and `asset` (optionally `solution`); the first rule matching a file's new path, or its old path for a move or delete, sends that file to the Task `<kind>: <solution>/<asset>` with key `<root>/<kind lowercased>/<asset>`. A rule with `"resolve": "dbt_ref"` needs only `root` and attaches the file to the single model its `ref()` names. Files no rule claims stay with their folder-level Task. An existing Task is reused for an asset only when its title matches exactly, never by its last name segment, because asset names repeat across solutions. Two assets that would get the same title stop the run; add a `solution` group to tell them apart. Without `asset_rules`, grouping is unchanged.

```json
"asset_rules": [
  {"kind": "Model", "pattern": "^(?P<root>data_solution/(?P<solution>[^/]+))/transformation/models/(?:.+/)?(?P<asset>[^/]+)/(?P=asset)\\.(?:sql|yml)$"},
  {"kind": "Model", "pattern": "^(?P<root>data_solution/(?P<solution>[^/]+))/transformation/tests/.+\\.sql$", "resolve": "dbt_ref"}
]
```

`config.py --validate` reports malformed rules.

#### Assignee

Each Task or sub-issue goes to the developer who changed the most lines (added plus deleted) in its files during the release range. `collect_evidence.py` records each item's `contributions`:

- **Credit for PRs:** a PR merge or squash commit on the first-parent history counts its whole diff for the PR author.
- **Branch syncs:** a merge that brings in other PR merges, such as a dev-to-release sync, is opened up, so the inner PRs get the credit instead.
- **Direct commits:** a commit without a PR counts for its commit author.
- **Ties:** a tie goes to the developer whose change merged last.

Items that already have an assignee keep it. Assignment never replaces one.

| | Azure DevOps | GitHub |
| --- | --- | --- |
| PR author | `createdBy.uniqueName` | `author.login` |
| Direct commit | commit email | the login linked to the commit, if any |
| Check | `validateOnly` patch on `System.AssignedTo` | `GET /repos/{owner}/{repo}/assignees/{login}`; the login must be assignable |
| Write | patch `System.AssignedTo` | `POST /repos/{owner}/{repo}/issues/{n}/assignees` |

- **Azure DevOps:** `manage_tasks.py` plans the assignee for new Tasks and for unassigned reused Tasks, and shows it in the dry run.
- **Both providers:** for existing items, `publish_descriptions.py --evidence evidence.json` shows the assignee in its dry run and sets it with `--apply`.
- **No assignee:** if no contributor can be resolved, the item stays unassigned and the dry run says why.

### Writing a description

```bash
# Azure DevOps — json-patch, Content-Type matters
az rest --method patch --resource 499b84ac-1321-427f-aa17-267ca6975798 \
    --url "https://dev.azure.com/<org>/<project>/_apis/wit/workitems/<ID>?api-version=7.0" \
    --headers "Content-Type=application/json-patch+json" --body @patch.json

# GitHub — JSON body on stdin avoids escaping multi-line Markdown
echo '{"body":"…"}' | gh api -X PATCH "/repos/<owner>/<repo>/issues/<ID>" --input -
```

Always go through `publish_descriptions.py` in normal use: it dry-runs by
default and refuses to overwrite a non-empty description without `--overwrite`.

## Merge-commit subjects

Used to recover PR numbers from `git log`. Configured per provider, named groups
`pr` and `title`:

| Provider | Pattern | Matches |
|---|---|---|
| Azure DevOps | `Merged PR (?P<pr>\d+): (?P<title>.*)` | `Merged PR 1234: Add measure` |
| GitHub, merge commit | `Merge pull request #(?P<pr>\d+) from \S+\s*(?P<title>.*)` | `Merge pull request #77 from acme/feature` |
| GitHub, squash | `(?P<title>.*) \(#(?P<pr>\d+)\)$` | `Add measure (#77)` |

Override with `merge_commit_patterns` in the repo config when a team uses a
custom merge template. A subject that matches nothing keeps `pr: null` and the
raw subject as its text — it is never dropped.
