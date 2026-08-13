#!/usr/bin/env python3
"""Work-tracker access for release-notes: Azure DevOps and GitHub behind one interface.

Everything that differs between the two trackers lives here, so the rest of the
skill can treat "a parent item with testable children" as a single concept.

The two important asymmetries:

  * Body format. Azure DevOps stores `System.Description` as HTML; GitHub issue
    bodies are Markdown. Callers must render according to `body_format`.
  * Child typing. Azure DevOps types its children, so a parent's hierarchy can
    hold Tasks, User Stories and Features and only Tasks are testable units.
    GitHub sub-issues carry no type, so every child qualifies.

Reads are unrestricted; the single write path is `set_description`.
"""
from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import quote

ADO_RESOURCE = "499b84ac-1321-427f-aa17-267ca6975798"


class ProviderError(SystemExit):
    """Actionable failure — a missing CLI, a failed login, an unknown item."""


def run_json(args: list[str], *, stdin: str | None = None) -> dict | list:
    try:
        proc = subprocess.run(args, capture_output=True, text=True, input=stdin)
    except FileNotFoundError:
        raise ProviderError(f"{args[0]} is not installed")
    if proc.returncode != 0:
        raise ProviderError(f"{' '.join(args[:3])} failed: {proc.stderr.strip()[:500]}")
    if not proc.stdout.strip():
        return {}
    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise ProviderError(f"{args[0]} returned non-JSON output: {exc}")


def strip_ref(ref: str) -> str:
    """'refs/heads/releases/rel_1' -> 'releases/rel_1'."""
    return ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref


class Provider:
    """Interface. Both implementations return the same shapes."""

    body_format = "markdown"

    def fetch_pr(self, pr_id: str) -> dict:
        """-> {id, title, state, source, target, url} with refs already stripped."""
        raise NotImplementedError

    def fetch_children(self, parent_ids: list[str], child_types: list[str]) -> list[dict]:
        """-> [{id, title, type, state, description, url}] deduplicated by id.

        `child_types` filters by tracker item type; an empty list keeps everything.
        """
        raise NotImplementedError

    def fetch_descriptions(self, ids: list[str]) -> dict[str, str]:
        raise NotImplementedError

    def set_description(self, item_id: str, body: str) -> str:
        """Write the description. Returns a revision marker for the log."""
        raise NotImplementedError

    def item_url(self, item_id: str) -> str:
        raise NotImplementedError


# ----------------------------------------------------------------- Azure DevOps

class AdoProvider(Provider):
    body_format = "html"

    def __init__(self, org: str, project: str) -> None:
        if not project:
            raise ProviderError("Azure DevOps needs a project — set work_item_project")
        self.org = org
        self.project = project
        self.org_url = org if org.startswith("http") else f"https://dev.azure.com/{org}"

    @property
    def _wit(self) -> str:
        return f"{self.org_url}/{quote(self.project)}/_apis/wit"

    def _rest(self, url: str, method: str | None = None,
              body_file: str | None = None, content_type: str | None = None) -> dict:
        args = ["az", "rest", "--resource", ADO_RESOURCE, "--url", url, "-o", "json"]
        if method:
            args += ["--method", method]
        if content_type:
            args += ["--headers", f"Content-Type={content_type}"]
        if body_file:
            args += ["--body", f"@{body_file}"]
        return run_json(args)

    def fetch_pr(self, pr_id: str) -> dict:
        data = run_json([
            "az", "repos", "pr", "show", "--id", str(pr_id),
            "--org", self.org_url, "-o", "json",
        ])
        return {
            "id": str(pr_id),
            "title": data.get("title"),
            "state": data.get("status"),
            "source": strip_ref(data.get("sourceRefName") or ""),
            "target": strip_ref(data.get("targetRefName") or ""),
            "url": f"{self.org_url}/{quote(self.project)}/_git/"
                   f"{quote(str((data.get('repository') or {}).get('name') or ''))}"
                   f"/pullrequest/{pr_id}",
        }

    def _child_ids(self, parent_id: str) -> list[str]:
        data = self._rest(f"{self._wit}/workitems/{parent_id}?api-version=7.0&$expand=all")
        ids = []
        for rel in data.get("relations") or []:
            if rel.get("rel") == "System.LinkTypes.Hierarchy-Forward":
                ids.append(rel["url"].rstrip("/").rsplit("/", 1)[-1])
        return ids

    def _batch(self, ids: list[str], fields: str | None = None) -> list[dict]:
        out: list[dict] = []
        # The batch endpoint caps at 200 ids per call.
        for i in range(0, len(ids), 190):
            chunk = ",".join(str(x) for x in ids[i:i + 190])
            url = f"{self._wit}/workitems?ids={chunk}&api-version=7.0"
            url += f"&fields={fields}" if fields else "&$expand=all"
            out += self._rest(url).get("value", [])
        return out

    def fetch_children(self, parent_ids: list[str], child_types: list[str]) -> list[dict]:
        ids: list[str] = []
        for parent in parent_ids:
            ids += self._child_ids(parent)
        if not ids:
            return []
        seen: dict[str, dict] = {}
        for item in self._batch(sorted(set(ids), key=int)):
            f = item.get("fields", {})
            item_type = f.get("System.WorkItemType")
            if child_types and item_type not in child_types:
                continue
            wid = str(item["id"])
            seen[wid] = {
                "id": wid,
                "title": f.get("System.Title"),
                "type": item_type,
                "state": f.get("System.State"),
                "description": (f.get("System.Description") or "").strip(),
                "url": self.item_url(wid),
            }
        return sorted(seen.values(), key=lambda t: int(t["id"]))

    def fetch_descriptions(self, ids: list[str]) -> dict[str, str]:
        fields = "System.Id,System.Title,System.Description"
        return {
            str(item["id"]): (item["fields"].get("System.Description") or "").strip()
            for item in self._batch(list(ids), fields=fields)
        }

    def set_description(self, item_id: str, body: str) -> str:
        patch = [{"op": "add", "path": "/fields/System.Description", "value": body}]
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False,
                                         encoding="utf-8") as fh:
            json.dump(patch, fh, ensure_ascii=False)
            tmp = fh.name
        try:
            result = self._rest(
                f"{self._wit}/workitems/{item_id}?api-version=7.0",
                method="patch", body_file=tmp,
                content_type="application/json-patch+json",
            )
            return f"rev {result.get('rev', '?')}"
        finally:
            Path(tmp).unlink(missing_ok=True)

    def item_url(self, item_id: str) -> str:
        return f"{self.org_url}/{quote(self.project)}/_workitems/edit/{item_id}"


# ------------------------------------------------------------------------ GitHub

class GitHubProvider(Provider):
    body_format = "markdown"

    # Sub-issues were still versioned at the time of writing; pin the header so
    # a future default cannot change the response shape underneath us.
    API_VERSION = "2026-03-10"

    def __init__(self, owner: str, repo: str, host: str = "github.com") -> None:
        self.owner = owner
        self.repo = repo
        self.host = host
        self.slug = f"{owner}/{repo}"

    def _api(self, path: str, method: str | None = None,
             payload: dict | None = None, paginate: bool = False) -> dict | list:
        args = ["gh", "api", "-H", f"X-GitHub-Api-Version: {self.API_VERSION}"]
        if self.host != "github.com":
            args = ["gh", "api", "--hostname", self.host,
                    "-H", f"X-GitHub-Api-Version: {self.API_VERSION}"]
        if method:
            args += ["-X", method]
        if paginate:
            args.append("--paginate")
        args.append(path)
        stdin = None
        if payload is not None:
            # --input - takes a JSON body on stdin, which sidesteps -f escaping
            # for multi-line Markdown bodies.
            args += ["--input", "-"]
            stdin = json.dumps(payload, ensure_ascii=False)
        return run_json(args, stdin=stdin)

    def fetch_pr(self, pr_id: str) -> dict:
        data = run_json([
            "gh", "pr", "view", str(pr_id), "--repo", self.slug,
            "--json", "number,title,state,headRefName,baseRefName,url",
        ])
        return {
            "id": str(data.get("number", pr_id)),
            "title": data.get("title"),
            "state": data.get("state"),
            "source": data.get("headRefName"),
            "target": data.get("baseRefName"),
            "url": data.get("url"),
        }

    def fetch_children(self, parent_ids: list[str], child_types: list[str]) -> list[dict]:
        seen: dict[str, dict] = {}
        for parent in parent_ids:
            children = self._api(
                f"/repos/{self.slug}/issues/{parent}/sub_issues?per_page=100",
                paginate=True)
            for issue in children or []:
                num = str(issue["number"])
                seen[num] = {
                    "id": num,
                    "title": issue.get("title"),
                    # Sub-issues have no work-item type; report a stable label
                    # so downstream logging reads the same for both providers.
                    "type": "sub-issue",
                    "state": issue.get("state"),
                    "description": (issue.get("body") or "").strip(),
                    "url": issue.get("html_url") or self.item_url(num),
                }
        return sorted(seen.values(), key=lambda t: int(t["id"]))

    def fetch_descriptions(self, ids: list[str]) -> dict[str, str]:
        out: dict[str, str] = {}
        for num in ids:
            issue = self._api(f"/repos/{self.slug}/issues/{num}")
            out[str(num)] = (issue.get("body") or "").strip()
        return out

    def set_description(self, item_id: str, body: str) -> str:
        issue = self._api(f"/repos/{self.slug}/issues/{item_id}",
                          method="PATCH", payload={"body": body})
        return f"updated {issue.get('updated_at', '?')}"

    def item_url(self, item_id: str) -> str:
        return f"https://{self.host}/{self.slug}/issues/{item_id}"


def from_config(cfg: dict) -> Provider:
    """Build the provider described by an effective config from config.py."""
    if cfg["provider"] == "ado":
        return AdoProvider(cfg["org"], cfg.get("work_item_project"))
    return GitHubProvider(cfg["org"], cfg["repo"], cfg.get("host", "github.com"))
