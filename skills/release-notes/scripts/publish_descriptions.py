#!/usr/bin/env python3
"""Publish work item descriptions to Azure DevOps or GitHub.

Dry run is the default: nothing is written unless --apply is passed. Items that
already have a description are skipped and reported unless --overwrite is also
passed, so a re-run never silently deletes a tester's own notes.

Usage:
    publish_descriptions.py --descriptions texts.json                 # dry run
    publish_descriptions.py --descriptions texts.json --apply
    publish_descriptions.py --descriptions texts.json --apply \
        --run rel_1 --evidence evidence.json                          # + artifact

Provider, org and project are resolved from the repo's release-notes config;
--org / --project / --provider override that for one-off runs.

texts.json maps item id to body. The body must be HTML for Azure DevOps and
Markdown for GitHub — check `provider.body_format` before generating it.

With --run, a per-repo artifact is written under
~/.ai-toolkit/release-notes/runs/<slug>/ so merge_release.py can later combine
several repos into one test email.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import RUNS_DIR, effective_config, repo_root  # noqa: E402
from providers import AdoProvider, GitHubProvider, from_config  # noqa: E402


def build_provider(args, cfg: dict):
    provider = args.provider or cfg["provider"]
    if args.org or args.project:
        if provider == "ado":
            return AdoProvider(args.org or cfg["org"],
                               args.project or cfg.get("work_item_project"))
        return GitHubProvider(args.org or cfg["org"], args.repo_name or cfg["repo"],
                              cfg.get("host", "github.com"))
    return from_config(cfg)


def write_artifact(slug: str, cfg: dict, provider, texts: dict[str, str],
                   evidence: dict | None, applied: bool) -> Path:
    """Record this repo's contribution to a release, for the merge step."""
    ev_tasks = (evidence or {}).get("tasks", {})
    tasks = []
    for item_id in sorted(texts, key=int):
        task = ev_tasks.get(item_id, {})
        tasks.append({
            "id": item_id,
            "title": task.get("title"),
            "url": task.get("url") or provider.item_url(item_id),
            "folder": task.get("folder"),
            "description": texts[item_id],
        })
    artifact = {
        "release": slug,
        "repo": cfg["repo"],
        "provider": cfg["provider"],
        "language": cfg.get("language", "en"),
        "body_format": provider.body_format,
        "applied": applied,
        "base": (evidence or {}).get("base"),
        "head": (evidence or {}).get("head"),
        "unclaimed_folders": (evidence or {}).get("unclaimed_folders", []),
        "tasks": tasks,
    }
    run_dir = RUNS_DIR / slug
    run_dir.mkdir(parents=True, exist_ok=True)
    path = run_dir / f"{cfg['repo']}.json"
    path.write_text(json.dumps(artifact, ensure_ascii=False, indent=2) + "\n")
    return path


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--descriptions", required=True, type=Path)
    ap.add_argument("--repo", type=Path, default=None, help="repo path for config lookup")
    ap.add_argument("--provider", choices=["ado", "github"], default=None)
    ap.add_argument("--org", default=None, help="override the org / owner")
    ap.add_argument("--project", default=None, help="override the Azure DevOps project")
    ap.add_argument("--repo-name", default=None, help="override the GitHub repository name")
    ap.add_argument("--apply", action="store_true",
                    help="write to the tracker (default: dry run)")
    ap.add_argument("--overwrite", action="store_true",
                    help="also replace descriptions that are already filled in")
    ap.add_argument("--run", default=None,
                    help="release slug; writes a run artifact for merge_release.py")
    ap.add_argument("--evidence", type=Path, default=None,
                    help="evidence.json, used to enrich the run artifact with titles")
    args = ap.parse_args()

    cfg = effective_config(repo_root(args.repo))
    provider = build_provider(args, cfg)

    texts: dict[str, str] = {str(k): v for k, v in
                             json.loads(args.descriptions.read_text()).items()}
    if not texts:
        raise SystemExit(f"no descriptions in {args.descriptions}")
    ids = sorted(texts, key=int)

    current = provider.fetch_descriptions(ids)
    missing = [i for i in ids if i not in current]
    if missing:
        raise SystemExit(f"items not found in {cfg['provider']}: {missing}")

    written, skipped = 0, []
    for item_id in ids:
        body = texts[item_id]
        if current[item_id] and not args.overwrite:
            skipped.append(item_id)
            continue
        action = "overwriting" if current[item_id] else "writing"
        if not args.apply:
            print(f"[dry run] {action} {item_id} ({len(body)} chars)")
            written += 1
            continue
        marker = provider.set_description(item_id, body)
        print(f"OK {item_id} ({marker}, {len(body)} chars)")
        written += 1

    print(f"\n{'written' if args.apply else 'would write'}: {written}")
    if skipped:
        print(f"skipped (already has a description): {skipped}")
        print("pass --overwrite to replace them")
    if not args.apply:
        print("this was a dry run — add --apply to write to the tracker")

    if args.run:
        evidence = json.loads(args.evidence.read_text()) if args.evidence else None
        path = write_artifact(args.run, cfg, provider, texts, evidence, args.apply)
        print(f"run artifact: {path}")


if __name__ == "__main__":
    main()
