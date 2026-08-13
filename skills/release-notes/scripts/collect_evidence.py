#!/usr/bin/env python3
"""Map release tasks to changed folders and extract per-task change evidence.

Read-only: runs git plumbing against a diff range and writes JSON. It never
writes to the work tracker and never formats prose — describing the change is
the agent's job, this only supplies verifiable facts.

Usage:
    collect_evidence.py --base origin/main --head origin/releases/rel_1 \
        --tasks tasks.json --out evidence.json [--repo .] [--mapping-only]

tasks.json is either a list of {"id", "title"} objects (as produced by
providers.py) or a raw Azure DevOps batch response ({"value": [...]}).

Folder conventions — item suffixes, task title prefixes and the merge-commit
subject pattern — come from the repo's release-notes config when --config is
given, and from the built-in defaults otherwise, so the script still runs
standalone.

Exit codes:
    0  every task mapped to exactly one folder
    2  mapping failed (ambiguous or unmatched) — details on stdout
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import (  # noqa: E402
    DEFAULT_ITEM_SUFFIXES, DEFAULT_MERGE_PATTERNS, DEFAULT_TITLE_PREFIXES,
    effective_config,
)


class Conventions:
    """Repo-specific mapping rules, resolved once and passed explicitly."""

    def __init__(self, cfg: dict | None = None) -> None:
        cfg = cfg or {}
        self.item_suffixes = tuple(cfg.get("item_suffixes") or DEFAULT_ITEM_SUFFIXES)
        self.title_prefixes = {
            k.casefold(): v
            for k, v in (cfg.get("title_prefixes") or DEFAULT_TITLE_PREFIXES).items()
        }
        patterns = cfg.get("merge_commit_patterns") or DEFAULT_MERGE_PATTERNS["ado"]
        self.merge_patterns = [re.compile(p) for p in patterns]
        self.child_types = cfg.get("child_types") or []

    def match_merge(self, subject: str) -> tuple[str | None, str]:
        """-> (pr_number, title). Falls back to the raw subject when unmatched."""
        for pattern in self.merge_patterns:
            m = pattern.match(subject)
            if m:
                groups = m.groupdict()
                return groups.get("pr"), (groups.get("title") or subject).strip()
        return None, subject

    def item_folder(self, path: str) -> str | None:
        """Longest prefix of path that names a deployable item folder."""
        parts = path.split("/")
        for i, part in enumerate(parts):
            if part.endswith(self.item_suffixes):
                return "/".join(parts[: i + 1])
        return None

    def group_key(self, path: str) -> str:
        return self.item_folder(path) or "/".join(path.split("/")[:2])

    def parse_title(self, title: str) -> tuple[str | None, str]:
        """'Report: Sales/Attendance' -> ('.Report', 'Attendance')."""
        kind_suffix = None
        rest = title
        if ":" in title:
            kind, tail = title.split(":", 1)
            suffix = self.title_prefixes.get(kind.strip().casefold())
            if suffix:
                kind_suffix, rest = suffix, tail
        return kind_suffix, rest.strip().split("/")[-1].strip()


def repo_root(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit.resolve()
    proc = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit("not inside a git repository — pass --repo <path>")
    return Path(proc.stdout.strip())


class Git:
    def __init__(self, repo: Path, base: str, head: str, conv: Conventions) -> None:
        self.repo = repo
        self.range = f"{base}...{head}"
        self.base = base
        self.head = head
        self.conv = conv

    def run(self, *args: str, allow_fail: bool = False) -> str:
        proc = subprocess.run(
            ["git", "-c", "core.quotepath=false", *args],
            cwd=self.repo, capture_output=True, text=True,
        )
        if proc.returncode != 0:
            if allow_fail:
                return ""
            raise SystemExit(f"git {' '.join(args)} failed: {proc.stderr.strip()}")
        return proc.stdout

    def changed(self, pathspec: str | None = None) -> list[tuple[str, str, str | None]]:
        """(status, path, old_path) for every file changed in the range."""
        args = ["diff", "--name-status", "-M", "-z", self.range]
        if pathspec is not None:
            args += ["--", pathspec]
        tokens = self.run(*args).split("\0")
        out: list[tuple[str, str, str | None]] = []
        i = 0
        while i < len(tokens) and tokens[i]:
            status = tokens[i]
            if status[0] in ("R", "C"):
                out.append((status, tokens[i + 2], tokens[i + 1]))
                i += 3
            else:
                out.append((status, tokens[i + 1], None))
                i += 2
        return out

    def commits(self, folder: str) -> list[dict]:
        out = self.run("log", "--format=%H\x1f%s", f"{self.base}..{self.head}", "--", folder)
        rows = []
        for line in out.splitlines():
            if not line.strip():
                continue
            sha, subject = line.split("\x1f", 1)
            pr, text = self.conv.match_merge(subject)
            rows.append({"sha": sha[:8], "subject": subject, "pr": pr, "text": text})
        return rows

    def diff(self, *paths: str) -> str:
        return self.run("diff", "-M", self.range, "--", *paths)

    def show(self, ref: str, path: str) -> str:
        return self.run("show", f"{ref}:{path}", allow_fail=True)


# --------------------------------------------------------------------- mapping

def load_tasks(path: Path, child_types: list[str]) -> list[dict]:
    """Load child tasks, filtering by tracker item type and deduplicating by id.

    Children merged from several parents can overlap, and an epic's children are
    parents rather than tasks — neither maps to a folder. An empty `child_types`
    keeps every child, which is what GitHub sub-issues need.
    """
    raw = json.loads(path.read_text())
    items = raw["value"] if isinstance(raw, dict) and "value" in raw else raw
    tasks: dict[str, dict] = {}
    dropped: list[str] = []
    for it in items:
        fields = it.get("fields", {})
        item_type = fields.get("System.WorkItemType", it.get("type"))
        if child_types and item_type not in child_types:
            dropped.append(f"{it['id']} ({item_type})")
            continue
        tid = str(it["id"])
        tasks[tid] = {
            "id": tid,
            "title": fields.get("System.Title", it.get("title")),
            "has_description": bool(fields.get("System.Description")
                                    or it.get("description")
                                    or it.get("has_description") or ""),
            "state": fields.get("System.State", it.get("state")),
            "url": it.get("url"),
        }
    if dropped:
        print(f"skipped (type not in {child_types}): {', '.join(dropped)}")
    return sorted(tasks.values(), key=lambda t: int(t["id"]))


def map_tasks(tasks: list[dict], folders: set[str],
              conv: Conventions) -> tuple[dict[str, str], list[str]]:
    mapping: dict[str, str] = {}
    problems: list[str] = []
    for task in tasks:
        suffix, name = conv.parse_title(task["title"])
        cands = []
        for folder in folders:
            base = Path(folder).name
            if suffix:
                if not base.endswith(suffix):
                    continue
                base = base[: -len(suffix)]
            if base.casefold() == name.casefold():
                cands.append(folder)
        if len(cands) == 1:
            mapping[task["id"]] = cands[0]
        else:
            problems.append(
                f"{task['id']} '{task['title']}' -> "
                + (f"{len(cands)} candidates: {sorted(cands)}" if cands else "no match")
            )
    return mapping, problems


# -------------------------------------------------------------------- evidence

def model_evidence(git: Git, folder: str, files) -> dict:
    d = git.diff(folder)
    lines = d.splitlines()
    ev: dict = {}

    def added_removed(pattern: str) -> tuple[list[str], list[str]]:
        add, rem = [], []
        for line in lines:
            m = re.match(pattern, line)
            if m:
                name = m.group(2) or m.group(3)
                (add if m.group(1) == "+" else rem).append(name)
        return sorted(set(add) - set(rem)), sorted(set(rem) - set(add))

    ev["measures_added"], ev["measures_removed"] = added_removed(
        r"^([+-])\s*measure\s+(?:'([^']+)'|(\S+))")
    ev["columns_added"], ev["columns_removed"] = added_removed(
        r"^([+-])\s*column\s+(?:'([^']+)'|(\S+))")

    ref_a, ref_r = [], []
    for line in lines:
        m = re.match(r"^([+-])ref table\s+'?([^'\n]+?)'?$", line)
        if m:
            (ref_a if m.group(1) == "+" else ref_r).append(m.group(2))
    ev["ref_tables_added"] = sorted(set(ref_a) - set(ref_r))
    ev["ref_tables_removed"] = sorted(set(ref_r) - set(ref_a))

    source_lines = [
        line for line in lines
        if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
        and re.search(r"(partition |Sql\.Databases?|Schema=|Item=|mode:|expression |dataSource|Source\s*=)", line)
    ]
    ev["source_lines"] = [line.strip()[:200] for line in source_lines[:80]]

    def scan(sign: str, pattern: str) -> list[str]:
        return sorted({
            m if isinstance(m, str) else ".".join(m)
            for line in source_lines if line.startswith(sign)
            for m in re.findall(pattern, line)
        })

    ev["servers_added"] = scan("+", r'Sql\.Databases?\("([^"]+)"')
    ev["servers_removed"] = scan("-", r'Sql\.Databases?\("([^"]+)"')
    ev["databases_added"] = scan("+", r'Sql\.Database\("[^"]+","?([^",]+)"?')
    ev["databases_removed"] = scan("-", r'Sql\.Database\("[^"]+","?([^",]+)"?')
    ev["schemas_added"] = scan("+", r'Schema="([^"]+)",\s*Item="([^"]+)"')
    ev["schemas_removed"] = scan("-", r'Schema="([^"]+)",\s*Item="([^"]+)"')

    ev["relationships_changed"] = any("relationships.tmdl" in p for _, p, _ in files)
    ev["tables"] = {
        "added": sorted(Path(p).stem for s, p, _ in files if s[0] == "A" and "/tables/" in p),
        "modified": sorted(Path(p).stem for s, p, _ in files if s[0] == "M" and "/tables/" in p),
        "deleted": sorted(Path(p).stem for s, p, _ in files if s[0] == "D" and "/tables/" in p),
        "renamed": sorted([Path(o).stem, Path(p).stem] for s, p, o in files
                          if s[0] == "R" and o and "/tables/" in p),
    }
    return ev


def report_evidence(git: Git, folder: str, files) -> dict:
    pages: dict[str, dict] = defaultdict(lambda: {"status": set(), "visuals": Counter()})
    other: list[str] = []
    for status, path, _old in files:
        m = re.search(r"/definition/pages/([0-9a-f]{8,})/", path)
        if not m:
            other.append(f"{status} {Path(path).name}")
            continue
        page = pages[m.group(1)]
        if path.endswith("/page.json"):
            page["status"].add(status[0])
            page["page_json"] = path
        elif "/visuals/" in path:
            page["visuals"][status[0]] += 1

    resolved = {}
    for guid, page in pages.items():
        page_json = page.get("page_json") or f"{folder}/definition/pages/{guid}/page.json"
        name = None
        for ref in (git.head, git.base):
            raw = git.show(ref, page_json)
            if raw:
                try:
                    name = json.loads(raw).get("displayName")
                except json.JSONDecodeError:
                    name = None
                break
        types = Counter()
        for status, path, _old in files:
            if f"/pages/{guid}/" in path and path.endswith("/visual.json"):
                raw = git.show(git.base if status[0] == "D" else git.head, path)
                if raw:
                    try:
                        vt = (json.loads(raw).get("visual") or {}).get("visualType")
                    except json.JSONDecodeError:
                        vt = None
                    if vt:
                        types[vt] += 1
        resolved[name or f"(unknown page {guid[:8]})"] = {
            "page_status": sorted(page["status"]),
            "visuals": dict(page["visuals"]),
            "visual_types": dict(types.most_common(8)),
        }

    ev = {
        "pages": resolved,
        "other_files": other[:40],
        "theme_changed": any("StaticResources" in p or "theme" in p.lower() for _, p, _ in files),
        "report_json_changed": any(p.endswith("/report.json") for _, p, _ in files),
        "bookmarks_changed": any("/bookmarks/" in p for _, p, _ in files),
    }
    pbirs = [p for _, p, _ in files if p.endswith(".pbir")]
    ev["pbir_files_changed"] = [Path(p).name for p in pbirs]
    if pbirs:
        ev["pbir_diff"] = [
            line.strip()[:220] for line in git.diff(*pbirs).splitlines()
            if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))
        ][:40]
    return ev


def generic_evidence(git: Git, folder: str, files) -> dict:
    return {
        "files_sample": [f"{s} {p}" for s, p, _ in files[:40]],
        "diffstat": git.run("diff", "--stat", git.range, "--", folder).strip().splitlines()[-1:],
    }


# ------------------------------------------------------------------------ main

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=None, type=Path,
                    help="repo path (default: the git repo containing the working directory)")
    ap.add_argument("--base", required=True, help="target ref of the release PR, e.g. origin/main")
    ap.add_argument("--head", required=True, help="source ref of the release PR")
    ap.add_argument("--tasks", required=True, type=Path)
    ap.add_argument("--out", type=Path, help="evidence JSON output path")
    ap.add_argument("--pathspec", default=None,
                    help="limit folder discovery, e.g. 'solution' (default: whole diff)")
    ap.add_argument("--mapping-only", action="store_true",
                    help="print the task -> folder mapping and exit without extracting evidence")
    ap.add_argument("--config", action="store_true",
                    help="load folder conventions from the repo's release-notes config")
    args = ap.parse_args()

    repo = repo_root(args.repo)
    conv = Conventions(effective_config(repo) if args.config else None)
    git = Git(repo, args.base, args.head, conv)
    tasks = load_tasks(args.tasks, conv.child_types)

    all_changed = git.changed(args.pathspec)
    folders = {k for _, p, _ in all_changed if (k := conv.group_key(p))}
    item_folders = {f for f in folders if f.endswith(conv.item_suffixes)}

    mapping, problems = map_tasks(tasks, item_folders or folders, conv)
    claimed = set(mapping.values())
    unclaimed = sorted((item_folders or folders) - claimed)

    print(f"tasks: {len(tasks)}  mapped: {len(mapping)}  changed folders: {len(folders)}")
    for tid, folder in sorted(mapping.items(), key=lambda kv: int(kv[0])):
        title = next(t["title"] for t in tasks if t["id"] == tid)
        print(f"  {tid}  {title}  ->  {folder}")
    if unclaimed:
        print("\nfolders with no task:")
        for folder in unclaimed:
            print(f"  {folder}")
    if problems:
        print("\nMAPPING ERRORS:")
        for p in problems:
            print(f"  {p}")

    if args.mapping_only:
        sys.exit(2 if problems else 0)
    if problems:
        print("\nAborted: fix the mapping (or the task titles) before extracting evidence.")
        sys.exit(2)

    evidence = {}
    for task in tasks:
        folder = mapping[task["id"]]
        files = git.changed(folder)
        ev = {
            **task,
            "folder": folder,
            "file_count": len(files),
            "status_counts": dict(Counter(s[0] for s, _, _ in files)),
            "commits": git.commits(folder),
            "files": [{"status": s, "path": p, "old": o} for s, p, o in files][:400],
        }
        if folder.endswith(".SemanticModel"):
            ev.update(model_evidence(git, folder, files))
        elif folder.endswith(".Report"):
            ev.update(report_evidence(git, folder, files))
        else:
            ev.update(generic_evidence(git, folder, files))
        evidence[task["id"]] = ev

    payload = {
        "base": args.base,
        "head": args.head,
        "unclaimed_folders": unclaimed,
        "tasks": evidence,
    }
    out = args.out or Path("evidence.json")
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=1))
    print(f"\nevidence written to {out} ({len(evidence)} tasks)")


if __name__ == "__main__":
    main()
