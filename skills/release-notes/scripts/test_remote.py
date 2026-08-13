#!/usr/bin/env python3
"""Assertions for git remote parsing and merge-commit patterns.

Dependency-free — run it with plain python3:

    python3 scripts/test_remote.py

Remote parsing is the fragile part of this skill: Azure DevOps percent-encodes
project names, offers three URL shapes, and the SSH form omits the `_git`
segment that the HTTPS form requires. Every shape below has been seen in the
wild. Test vectors are deliberately fictional.
"""
from __future__ import annotations

import re
import sys

from config import DEFAULT_MERGE_PATTERNS, parse_remote

# (url, provider, org, project, repo)
CASES = [
    # --- Azure DevOps, HTTPS ---
    ("https://dev.azure.com/contoso/Team%20Project/_git/Analytics",
     "ado", "contoso", "Team Project", "Analytics"),
    ("https://contoso@dev.azure.com/contoso/Team%20Project/_git/Analytics",
     "ado", "contoso", "Team Project", "Analytics"),
    ("https://dev.azure.com/contoso/Team%20Project/_git/Analytics.git",
     "ado", "contoso", "Team Project", "Analytics"),
    # Non-ASCII project names arrive percent-encoded and must round-trip.
    ("https://contoso@dev.azure.com/contoso/Team%20Projekt%20%C3%86/_git/Data%20Platform",
     "ado", "contoso", "Team Projekt Æ", "Data Platform"),
    # --- Azure DevOps, SSH v3: no _git segment ---
    ("git@ssh.dev.azure.com:v3/contoso/Team%20Project/On-Premise",
     "ado", "contoso", "Team Project", "On-Premise"),
    ("git@ssh.dev.azure.com:v3/contoso/Team%20Projekt%20%C3%86/On-Premise",
     "ado", "contoso", "Team Projekt Æ", "On-Premise"),
    # --- Azure DevOps, legacy visualstudio.com ---
    ("https://contoso.visualstudio.com/Team%20Project/_git/Analytics",
     "ado", "contoso", "Team Project", "Analytics"),
    ("https://contoso.visualstudio.com/DefaultCollection/Team%20Project/_git/Analytics",
     "ado", "contoso", "Team Project", "Analytics"),
    ("contoso@vs-ssh.visualstudio.com:v3/contoso/Team%20Project/Analytics",
     "ado", "contoso", "Team Project", "Analytics"),
    # --- GitHub ---
    ("https://github.com/acme/widget.git", "github", "acme", None, "widget"),
    ("https://github.com/acme/widget", "github", "acme", None, "widget"),
    ("git@github.com:acme/widget.git", "github", "acme", None, "widget"),
    ("ssh://git@github.com/acme/widget.git", "github", "acme", None, "widget"),
    # GitHub Enterprise on a custom host.
    ("git@git.acme.internal:platform/widget.git",
     "github", "platform", None, "widget"),
]

MERGE_CASES = [
    ("ado", "Merged PR 1234: Add revenue measure", "1234", "Add revenue measure"),
    ("github", "Merge pull request #77 from acme/feature Add revenue measure",
     "77", "Add revenue measure"),
    ("github", "Add revenue measure (#77)", "77", "Add revenue measure"),
]


def match_merge(provider: str, subject: str):
    for pattern in DEFAULT_MERGE_PATTERNS[provider]:
        m = re.match(pattern, subject)
        if m:
            return m.group("pr"), m.group("title").strip()
    return None


def main() -> int:
    failures: list[str] = []

    for url, provider, org, project, repo in CASES:
        try:
            got = parse_remote(url)
        except SystemExit as exc:
            failures.append(f"{url}\n    raised: {exc}")
            continue
        want = {"provider": provider, "org": org, "project": project, "repo": repo}
        actual = {k: got.get(k) for k in want}
        if actual != want:
            failures.append(f"{url}\n    want {want}\n    got  {actual}")

    for provider, subject, pr, title in MERGE_CASES:
        got = match_merge(provider, subject)
        if got != (pr, title):
            failures.append(f"[{provider}] {subject!r}\n    want {(pr, title)}\n    got  {got}")

    # A merge-commit pattern that matches nothing must return None rather than
    # silently reporting a PR number of None downstream.
    if match_merge("ado", "chore: bump provider version") is not None:
        failures.append("non-merge subject should not match the ADO pattern")

    total = len(CASES) + len(MERGE_CASES) + 1
    if failures:
        print(f"FAILED {len(failures)}/{total}\n")
        for f in failures:
            print(f"  {f}\n")
        return 1
    print(f"ok — {total} assertions passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
