---
name: smart-pr
description: Prepare and create a pull request with an evidence-based description and explicit completion choices.
---

# Smart PR

1. Inspect branch status, commits, diff, remote, and repository PR conventions.
2. Run relevant validation.
3. Draft title, summary, risks, and test evidence.
4. Preview the target branch and exact provider command.
5. Present auto-complete and source-branch deletion as separate explicit choices; default neither.
6. Ask approval before pushing or creating the PR.
7. Execute only the approved actions and return the PR URL.

Never enable auto-complete or delete a source branch implicitly. Branch cleanup belongs to `branch-cleanup`.
