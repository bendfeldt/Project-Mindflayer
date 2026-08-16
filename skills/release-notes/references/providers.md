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

### Planning and creating Azure DevOps child Tasks

Discover candidates without existing IDs, then create a saved dry-run plan:

```bash
python3 "$SKILL_DIR/scripts/collect_evidence.py" \
  --base origin/main --head origin/releases/rel_1 \
  --config --out evidence.json

python3 "$SKILL_DIR/scripts/manage_tasks.py" plan \
  --pr-id <PR_ID> --parent-id <USER_STORY_ID> \
  --evidence evidence.json --descriptions descriptions.json \
  --out pair-plan.json
```

`descriptions.json` maps each evidence `task_key` to an HTML description. Pair planning fetches PR and User Story state, verifies the evidence refs, reuses one unambiguous child match, and calls the Azure DevOps create endpoint with `validateOnly=true` for every missing Task. It writes no work items.

Run those commands separately for every PR/User Story pair, then compose the only applicable plan type:

```bash
python3 "$SKILL_DIR/scripts/manage_tasks.py" compose \
  --release rel_1 \
  --pair-plan repo-a-pr-123.json \
  --pair-plan repo-b-pr-456.json \
  --out release-plan.json
```

Composition enforces a strict contextual 1:1 relationship: a PR and a User Story may each appear only once. Pairs may come from different repositories. If two PRs change the same deployable folder, each paired User Story keeps its own child Task.

After the user reviews the printed actions and explicitly approves them:

```bash
python3 "$SKILL_DIR/scripts/manage_tasks.py" apply --plan release-plan.json
```

Apply rejects pair plans. It verifies the composed plan and every embedded pair, preflights all repositories, PRs, User Stories, and child Tasks before the first write, then applies pairs sequentially with resumable result state. New Tasks inherit the parent Area Path and Iteration Path; Azure DevOps process defaults set state and assignee.

Each applied pair writes `<repo>-pr-<id>.json` under the release run directory. `merge_release.py` groups these artifacts by pair and links both the PR and User Story, including when several PRs belong to one repository.

The create call uses Azure DevOps REST 7.1 JSON Patch with `System.Title`, `System.Description`, `System.AreaPath`, `System.IterationPath`, and a `System.LinkTypes.Hierarchy-Reverse` parent relation. GitHub child creation is not implemented; existing GitHub description behavior is unchanged.

The default allowed parent type is `User Story`. Teams using another Azure DevOps process must set `parent_types` explicitly in repository config. Override generated title labels with the suffix-to-prefix `task_title_prefixes` mapping; parsing of existing titles continues to use `title_prefixes`.

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
