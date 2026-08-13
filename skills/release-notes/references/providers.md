# Providers — Azure DevOps and GitHub

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
