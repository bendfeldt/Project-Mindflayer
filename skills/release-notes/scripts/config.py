#!/usr/bin/env python3
"""Resolve release-notes configuration: git remote, engagement roster, repo conventions.

Configuration is split in two, by what is machine-specific:

    ~/.ai-toolkit/release-notes/engagements/<engagement>.json
        Local paths and topology — engagement root, repo roster, default
        work-item project. Never committed; it only makes sense on this machine.

    <repo>/.claude/release-notes.config.json
        Team conventions — language, title prefixes, item suffixes. Committed
        so the whole team shares one mapping.

Usage:
    config.py --detect [--repo PATH]        parse this repo's remote
    config.py --bootstrap --root PATH       discover repos, propose an engagement
    config.py --show [--repo PATH]          effective merged config for a repo
    config.py --validate [--repo PATH]      check config and provider CLI auth

--bootstrap prints the proposed engagement JSON; it only writes with --write, so
the agent can show the roster and let the user deselect repos first.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

TOOLKIT_HOME = Path.home() / ".ai-toolkit" / "release-notes"
ENGAGEMENTS_DIR = TOOLKIT_HOME / "engagements"
RUNS_DIR = TOOLKIT_HOME / "runs"

REPO_CONFIG_NAME = ".claude/release-notes.config.json"

CONFIG_VERSION = 1

# Item folder suffixes for Fabric / Power BI repos. Paths that match none of
# these fall back to a two-level directory grouping, so the mapping still works
# in repos that deploy something else entirely.
DEFAULT_ITEM_SUFFIXES = [
    ".SemanticModel", ".Report", ".DataPipeline", ".Dataflow",
    ".Notebook", ".Lakehouse", ".Warehouse", ".Environment", ".pbip",
]

# Task title prefix -> required folder suffix. Matched case-insensitively.
DEFAULT_TITLE_PREFIXES = {
    "model": ".SemanticModel",
    "semantic model": ".SemanticModel",
    "report": ".Report",
    "pipeline": ".DataPipeline",
    "dataflow": ".Dataflow",
    "notebook": ".Notebook",
}

# Canonical title prefix used when the skill creates a missing child task.
# Parsing remains more permissive through DEFAULT_TITLE_PREFIXES.
DEFAULT_TASK_TITLE_PREFIXES = {
    ".SemanticModel": "Model",
    ".Report": "Report",
    ".DataPipeline": "Pipeline",
    ".Dataflow": "Dataflow",
    ".Notebook": "Notebook",
    ".Lakehouse": "Lakehouse",
    ".Warehouse": "Warehouse",
    ".Environment": "Environment",
    ".pbip": "Report",
}

DEFAULT_PARENT_TYPES = {"ado": ["User Story"], "github": []}

# Subject lines of merge commits, per provider. Named groups `pr` and `title`
# keep the contract identical across providers even where the squash form puts
# the number last.
DEFAULT_MERGE_PATTERNS = {
    "ado": [r"Merged PR (?P<pr>\d+): (?P<title>.*)"],
    "github": [
        r"Merge pull request #(?P<pr>\d+) from \S+\s*(?P<title>.*)",
        r"(?P<title>.*) \(#(?P<pr>\d+)\)$",
    ],
}

# Which children of a parent item count as testable tasks. Azure DevOps types
# them; GitHub sub-issues have no type, so every child qualifies.
DEFAULT_CHILD_TYPES = {"ado": ["Task"], "github": []}


class ConfigError(SystemExit):
    """Raised with an actionable message; never a bare stack trace."""


# ------------------------------------------------------------------ remote URL

SCP_LIKE = re.compile(r"^(?:(?P<user>[^/@]+)@)?(?P<host>[^/:]+):(?!//)(?P<path>.+)$")


def _segments(path: str) -> list[str]:
    """Split a URL path and percent-decode each segment individually."""
    return [unquote(p) for p in path.strip("/").split("/") if p]


def parse_remote(url: str) -> dict:
    """Parse a git remote URL into {provider, org, project, repo}.

    Handles Azure DevOps (HTTPS, SSH v3, legacy visualstudio.com) and GitHub
    (HTTPS, SSH, Enterprise hosts). `project` is None for GitHub, which has no
    layer between owner and repository.
    """
    url = url.strip()
    if not url:
        raise ConfigError("empty git remote URL")

    scp = SCP_LIKE.match(url)
    if scp:
        host, path = scp.group("host"), scp.group("path")
    else:
        parts = urlsplit(url)
        if not parts.netloc:
            raise ConfigError(f"cannot parse git remote: {url}")
        host = parts.netloc.rsplit("@", 1)[-1].split(":")[0]
        path = parts.path

    host = host.lower()
    segs = _segments(path)
    if segs and segs[-1].endswith(".git"):
        segs[-1] = segs[-1][: -len(".git")]
    if not segs:
        raise ConfigError(f"cannot parse git remote: {url}")

    if host in ("dev.azure.com", "ssh.dev.azure.com"):
        return _parse_ado(segs, url)
    if host.endswith("visualstudio.com"):
        # Either <org>.visualstudio.com/... or vs-ssh.visualstudio.com:v3/<org>/...
        subdomain = host.split(".")[0]
        if subdomain not in ("vs-ssh", "ssh"):
            segs = [subdomain] + [s for s in segs if s.lower() != "defaultcollection"]
        return _parse_ado(segs, url)
    return _parse_github(host, segs, url)


def _parse_ado(segs: list[str], url: str) -> dict:
    segs = [s for s in segs if s.lower() not in ("v3", "_git")]
    if len(segs) < 3:
        raise ConfigError(
            f"expected <org>/<project>/<repo> in Azure DevOps remote, got {segs}: {url}")
    org, project, repo = segs[0], segs[1], segs[-1]
    return {"provider": "ado", "org": org, "project": project, "repo": repo}


def _parse_github(host: str, segs: list[str], url: str) -> dict:
    if len(segs) < 2:
        raise ConfigError(f"expected <owner>/<repo> in remote, got {segs}: {url}")
    return {"provider": "github", "org": segs[-2], "project": None,
            "repo": segs[-1], "host": host}


def git_remote(repo: Path, name: str = "origin") -> str:
    proc = subprocess.run(["git", "remote", "get-url", name],
                          cwd=repo, capture_output=True, text=True)
    if proc.returncode != 0:
        raise ConfigError(f"no git remote '{name}' in {repo}: {proc.stderr.strip()}")
    return proc.stdout.strip()


def repo_root(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit.resolve()
    proc = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise ConfigError(
            "not inside a git repository — pass --repo <path>")
    return Path(proc.stdout.strip())


def detect(repo: Path) -> dict:
    remote = parse_remote(git_remote(repo))
    remote["path"] = str(repo)
    remote["name"] = repo.name
    return remote


# ----------------------------------------------------------------- engagements

def slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-") or "engagement"


def discover_repos(root: Path) -> tuple[list[dict], list[str]]:
    """Scan one level below `root` for git repos and parse each remote.

    Returns (repos, skipped). Directories that are not repos, or whose remote
    cannot be parsed, are reported rather than silently dropped.
    """
    repos: list[dict] = []
    skipped: list[str] = []
    for child in sorted(p for p in root.iterdir() if p.is_dir()):
        if not (child / ".git").exists():
            continue
        try:
            info = parse_remote(git_remote(child))
        except SystemExit as exc:
            skipped.append(f"{child.name}: {exc}")
            continue
        repos.append({
            "name": child.name,
            "path": child.name,
            "provider": info["provider"],
            "org": info["org"],
            "project": info["project"],
            "remote_repo": info["repo"],
        })
    return repos, skipped


def bootstrap(root: Path, engagement: str | None = None) -> dict:
    """Build a proposed engagement config from the repos found under `root`."""
    root = root.resolve()
    if not root.is_dir():
        raise ConfigError(f"root is not a directory: {root}")
    repos, skipped = discover_repos(root)
    if not repos:
        raise ConfigError(f"no git repositories found one level below {root}")

    providers = {r["provider"] for r in repos}
    if len(providers) > 1:
        print(f"note: mixed providers under {root}: {sorted(providers)}", file=sys.stderr)
    provider = repos[0]["provider"]
    orgs = sorted({r["org"] for r in repos if r["provider"] == provider})
    projects = sorted({r["project"] for r in repos if r["project"]})

    config = {
        "version": CONFIG_VERSION,
        "engagement": engagement or slugify(root.name),
        "root": str(root),
        "provider": provider,
        provider: {"org": orgs[0]} if len(orgs) == 1 else {"orgs": orgs},
        "work_items": {"project": projects[0] if len(projects) == 1 else None},
        "repos": repos,
        "email": {"tool": "outlook-macos" if sys.platform == "darwin" else "none"},
    }
    if skipped:
        config["_skipped"] = skipped
    if len(projects) > 1:
        config["_projects_seen"] = projects
    return config


def engagement_path(name: str) -> Path:
    return ENGAGEMENTS_DIR / f"{slugify(name)}.json"


def save_engagement(config: dict) -> Path:
    ENGAGEMENTS_DIR.mkdir(parents=True, exist_ok=True)
    path = engagement_path(config["engagement"])
    clean = {k: v for k, v in config.items() if not k.startswith("_")}
    path.write_text(json.dumps(clean, ensure_ascii=False, indent=2) + "\n")
    return path


def load_engagement_for(remote: dict) -> dict | None:
    """Find the engagement whose org matches this repo's remote.

    Matching on org means the user is never asked which engagement they are in —
    the git remote already answers it.
    """
    if not ENGAGEMENTS_DIR.is_dir():
        return None
    for path in sorted(ENGAGEMENTS_DIR.glob("*.json")):
        try:
            data = json.loads(path.read_text())
        except json.JSONDecodeError as exc:
            print(f"warning: skipping malformed {path}: {exc}", file=sys.stderr)
            continue
        block = data.get(remote["provider"], {})
        orgs = block.get("orgs") or ([block["org"]] if block.get("org") else [])
        if remote["org"] in orgs:
            data["_path"] = str(path)
            return data
    return None


# --------------------------------------------------------------- repo settings

def load_repo_config(repo: Path) -> dict:
    path = repo / REPO_CONFIG_NAME
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError as exc:
        raise ConfigError(f"malformed {path}: {exc}")


def default_repo_config(provider: str, project: str | None, language: str = "en") -> dict:
    return {
        "version": CONFIG_VERSION,
        "language": language,
        "work_item_project": project,
        "item_suffixes": list(DEFAULT_ITEM_SUFFIXES),
        "title_prefixes": dict(DEFAULT_TITLE_PREFIXES),
        "task_title_prefixes": dict(DEFAULT_TASK_TITLE_PREFIXES),
        "merge_commit_patterns": list(DEFAULT_MERGE_PATTERNS[provider]),
        "child_types": list(DEFAULT_CHILD_TYPES[provider]),
        "parent_types": list(DEFAULT_PARENT_TYPES[provider]),
    }


def effective_config(repo: Path) -> dict:
    """Merge remote detection, engagement roster and repo conventions.

    Precedence, lowest first: provider defaults, engagement file, repo config.
    Everything the other scripts need is resolved here so they never have to
    know which of the two files a value came from.
    """
    remote = detect(repo)
    engagement = load_engagement_for(remote)
    repo_cfg = load_repo_config(repo)

    provider = remote["provider"]
    project = (repo_cfg.get("work_item_project")
               or (engagement or {}).get("work_items", {}).get("project")
               or remote.get("project"))

    merged = default_repo_config(provider, project, repo_cfg.get("language", "en"))
    for key, value in repo_cfg.items():
        if value is not None:
            merged[key] = value
    merged["work_item_project"] = project

    merged["provider"] = provider
    merged["org"] = remote["org"]
    merged["repo"] = remote["repo"]
    merged["repo_path"] = str(repo)
    if remote.get("host"):
        merged["host"] = remote["host"]
    merged["engagement"] = (engagement or {}).get("engagement")
    merged["engagement_path"] = (engagement or {}).get("_path")
    merged["email"] = (engagement or {}).get("email", {"tool": "none"})
    merged["has_repo_config"] = bool(repo_cfg)
    return merged


# -------------------------------------------------------------------- validate

def check_cli(provider: str) -> list[str]:
    """Verify the provider CLI is present and authenticated. Read-only."""
    problems: list[str] = []
    if provider == "ado":
        probe = ["az", "account", "show", "-o", "none"]
        hint = "run: az login"
    else:
        probe = ["gh", "auth", "status"]
        hint = "run: gh auth login"
    try:
        proc = subprocess.run(probe, capture_output=True, text=True)
    except FileNotFoundError:
        return [f"{probe[0]} not installed"]
    if proc.returncode != 0:
        problems.append(f"{probe[0]} not authenticated — {hint}")
    return problems


def validate(repo: Path) -> int:
    cfg = effective_config(repo)
    problems: list[str] = []

    if not cfg["has_repo_config"]:
        problems.append(
            f"no {REPO_CONFIG_NAME} — run the skill's bootstrap step to create it")
    if not cfg["engagement"]:
        problems.append(
            f"no engagement roster matches org '{cfg['org']}' in {ENGAGEMENTS_DIR}")
    if cfg["provider"] == "ado" and not cfg["work_item_project"]:
        problems.append("work_item_project is unset and could not be derived")
    problems += check_cli(cfg["provider"])

    print(json.dumps(cfg, ensure_ascii=False, indent=2))
    if problems:
        print("\nproblems:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1
    print("\nconfiguration OK", file=sys.stderr)
    return 0


# ------------------------------------------------------------------------ main

def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--detect", action="store_true",
                      help="parse the repo's git remote and print the result")
    mode.add_argument("--bootstrap", action="store_true",
                      help="discover repos under --root and propose an engagement config")
    mode.add_argument("--show", action="store_true",
                      help="print the effective merged config for the repo")
    mode.add_argument("--validate", action="store_true",
                      help="check config completeness and provider CLI auth")
    ap.add_argument("--repo", type=Path, default=None,
                    help="repo path (default: the git repo containing the working directory)")
    ap.add_argument("--root", type=Path, default=None,
                    help="engagement root to scan (--bootstrap)")
    ap.add_argument("--engagement", default=None, help="engagement name (--bootstrap)")
    ap.add_argument("--write", action="store_true",
                    help="write the engagement file instead of printing it (--bootstrap)")
    args = ap.parse_args()

    if args.bootstrap:
        if args.root is None:
            raise ConfigError("--bootstrap requires --root <path>")
        config = bootstrap(args.root, args.engagement)
        if args.write:
            path = save_engagement(config)
            print(f"wrote {path}", file=sys.stderr)
        print(json.dumps(config, ensure_ascii=False, indent=2))
        return

    repo = repo_root(args.repo)
    if args.detect:
        print(json.dumps(detect(repo), ensure_ascii=False, indent=2))
    elif args.show:
        print(json.dumps(effective_config(repo), ensure_ascii=False, indent=2))
    else:
        sys.exit(validate(repo))


if __name__ == "__main__":
    main()
