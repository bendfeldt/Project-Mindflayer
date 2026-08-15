#!/usr/bin/env python3
"""Plan PR/User Story pairs, compose a release, and apply child Tasks.

Pair planning is non-mutating. Composition creates the only applicable plan
type, so one reviewed release plan is the approval boundary for every pair.

Usage:
  manage_tasks.py plan --pr-id 123 --parent-id 456 --evidence evidence.json \
    --descriptions descriptions.json --out pair-plan.json [--repo .]
  manage_tasks.py compose --release rel_1 --pair-plan pair-a.json \
    --pair-plan pair-b.json --out release-plan.json
  manage_tasks.py apply --plan release-plan.json [--result result.json]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from collect_evidence import Conventions  # noqa: E402
from config import RUNS_DIR, effective_config, repo_root, slugify  # noqa: E402
from providers import Provider, from_config  # noqa: E402


SCHEMA_VERSION = 2
PAIR_PLAN = "release-task-pair-plan"
RELEASE_PLAN = "release-task-release-plan"
RELEASE_RESULT = "release-task-release-result"


class TaskPlanError(SystemExit):
    """Actionable plan, mapping, or drift failure."""


def read_object(path: Path) -> dict:
    try:
        value = json.loads(path.read_text())
    except FileNotFoundError:
        raise TaskPlanError(f"file not found: {path}")
    except json.JSONDecodeError as exc:
        raise TaskPlanError(f"malformed JSON in {path}: {exc}")
    if not isinstance(value, dict):
        raise TaskPlanError(f"expected a JSON object in {path}")
    return value


def write_object(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def content_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def plan_hash(plan: dict) -> str:
    payload = {key: value for key, value in plan.items() if key != "plan_id"}
    encoded = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def git_revision(repo: Path, ref: str) -> str:
    proc = subprocess.run(
        ["git", "rev-parse", "--verify", f"{ref}^{{commit}}"],
        cwd=repo,
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        raise TaskPlanError(f"cannot resolve git ref {ref}: {proc.stderr.strip()}")
    return proc.stdout.strip()


def normalized(value: str | None) -> str:
    return " ".join((value or "").replace("\\", "/").casefold().split())


def normalized_ref(value: str | None) -> str:
    ref = value or ""
    for prefix in ("refs/remotes/origin/", "refs/heads/", "origin/"):
        if ref.startswith(prefix):
            return ref[len(prefix) :]
    return ref


def item_suffix(folder: str, conventions: Conventions) -> str | None:
    return next(
        (suffix for suffix in conventions.item_suffixes if folder.endswith(suffix)),
        None,
    )


def is_legacy_match(child: dict, candidate: dict, conventions: Conventions) -> bool:
    suffix, name = conventions.parse_title(child.get("title") or "")
    candidate_suffix = item_suffix(candidate["folder"], conventions)
    if suffix and suffix != candidate_suffix:
        return False
    leaf = Path(candidate["folder"]).name
    if candidate_suffix:
        leaf = leaf[: -len(candidate_suffix)]
    return normalized(name) == normalized(leaf)


def match_children(
    candidates: list[dict], children: list[dict], conventions: Conventions
) -> dict[str, dict]:
    matches: dict[str, dict] = {}
    used_ids: set[str] = set()
    for candidate in candidates:
        exact = [
            child
            for child in children
            if normalized(child.get("title")) == normalized(candidate["title"])
        ]
        possible = exact or [
            child
            for child in children
            if is_legacy_match(child, candidate, conventions)
        ]
        if len(possible) > 1:
            ids = ", ".join(str(child["id"]) for child in possible)
            raise TaskPlanError(
                f"ambiguous existing Tasks for {candidate['folder']}: {ids}"
            )
        if not possible:
            continue
        child = possible[0]
        child_id = str(child["id"])
        if child_id in used_ids:
            raise TaskPlanError(
                f"Task {child_id} matches more than one deployable folder"
            )
        used_ids.add(child_id)
        matches[candidate["task_key"]] = child
    return matches


def candidates_from_evidence(evidence: dict, descriptions: dict) -> list[dict]:
    raw_tasks = evidence.get("tasks")
    if not isinstance(raw_tasks, dict) or not raw_tasks:
        raise TaskPlanError("evidence contains no task candidates")

    candidates: list[dict] = []
    used_keys: set[str] = set()
    used_description_keys: set[str] = set()
    for evidence_key, task in sorted(raw_tasks.items()):
        if not isinstance(task, dict):
            raise TaskPlanError(f"invalid task evidence for {evidence_key}")
        folder = task.get("folder")
        title = task.get("title")
        task_key = str(task.get("task_key") or folder or evidence_key)
        if not folder or not title:
            raise TaskPlanError(f"task evidence {evidence_key} needs folder and title")
        if task_key in used_keys:
            raise TaskPlanError(f"duplicate task key: {task_key}")
        used_keys.add(task_key)

        description_key = task_key
        description = descriptions.get(description_key)
        if description is None:
            description_key = str(evidence_key)
            description = descriptions.get(description_key)
        if not isinstance(description, str) or not description.strip():
            raise TaskPlanError(f"missing non-empty description for {task_key}")
        used_description_keys.add(description_key)
        candidates.append(
            {
                "task_key": task_key,
                "folder": str(folder),
                "title": str(title),
                "description": description,
            }
        )

    extra_keys = sorted(set(descriptions) - used_description_keys)
    if extra_keys:
        raise TaskPlanError(f"descriptions contain unknown task keys: {extra_keys}")
    return candidates


def validate_parent(parent: dict, allowed_types: list[str]) -> None:
    if allowed_types and parent.get("type") not in allowed_types:
        expected = ", ".join(allowed_types)
        raise TaskPlanError(
            f"parent {parent.get('id')} is {parent.get('type')!r}; expected {expected}"
        )


def validate_evidence_refs(evidence: dict, pull_request: dict) -> None:
    base = evidence.get("base")
    head = evidence.get("head")
    if not base or not head:
        raise TaskPlanError("evidence needs base and head refs")
    if normalized_ref(base) != normalized_ref(pull_request.get("target")):
        raise TaskPlanError(
            f"evidence base {base!r} does not match PR target "
            f"{pull_request.get('target')!r}"
        )
    if normalized_ref(head) != normalized_ref(pull_request.get("source")):
        raise TaskPlanError(
            f"evidence head {head!r} does not match PR source "
            f"{pull_request.get('source')!r}"
        )


def build_pair_plan(
    provider: Provider,
    config: dict,
    pr_id: str,
    parent_id: str,
    evidence: dict,
    descriptions: dict,
    repo: Path,
    overwrite: bool,
) -> dict:
    if not provider.can_create_children:
        raise TaskPlanError(
            f"provider {config['provider']} does not support planned child creation"
        )
    if provider.body_format != "html":
        raise TaskPlanError("Azure DevOps task descriptions must be HTML")

    pull_request = provider.fetch_pr(pr_id)
    validate_evidence_refs(evidence, pull_request)
    parent = provider.fetch_item(parent_id)
    validate_parent(parent, config.get("parent_types") or [])

    conventions = Conventions(config)
    candidates = candidates_from_evidence(evidence, descriptions)
    children = provider.fetch_children([parent_id], config.get("child_types") or [])
    existing = match_children(candidates, children, conventions)

    actions: list[dict] = []
    for candidate in candidates:
        task = {
            **candidate,
            "System.AreaPath": parent.get("System.AreaPath"),
            "System.IterationPath": parent.get("System.IterationPath"),
        }
        child = existing.get(candidate["task_key"])
        if child is None:
            provider.validate_child(parent_id, task)
            actions.append({**task, "operation": "create"})
            continue

        current = child.get("description") or ""
        if current == candidate["description"]:
            description_action = "unchanged"
        elif current and not overwrite:
            description_action = "skip"
        else:
            description_action = "update"
        actions.append(
            {
                **task,
                "operation": "reuse",
                "item_id": str(child["id"]),
                "expected_rev": child.get("rev"),
                "current_description_hash": content_hash(current),
                "description_action": description_action,
            }
        )

    base = evidence["base"]
    head = evidence["head"]
    plan = {
        "schema_version": SCHEMA_VERSION,
        "kind": PAIR_PLAN,
        "provider": config["provider"],
        "target": {
            "org": config["org"],
            "project": config.get("work_item_project"),
            "parent": parent,
        },
        "source": {
            "repo": config["repo"],
            "repo_path": str(repo.resolve()),
            "pull_request": pull_request,
            "base": base,
            "head": head,
            "base_commit": git_revision(repo, base),
            "head_commit": git_revision(repo, head),
        },
        "language": config.get("language", "en"),
        "body_format": provider.body_format,
        "unclaimed_folders": evidence.get("unclaimed_folders", []),
        "overwrite": overwrite,
        "actions": actions,
    }
    plan["plan_id"] = plan_hash(plan)
    return plan


def verify_pair_plan(plan: dict) -> None:
    if plan.get("schema_version") != SCHEMA_VERSION or plan.get("kind") != PAIR_PLAN:
        raise TaskPlanError("expected a supported PR/User Story pair plan")
    if plan.get("plan_id") != plan_hash(plan):
        raise TaskPlanError("pair plan content does not match its plan_id")


def pr_identity(pair: dict) -> tuple[str, ...]:
    pull_request = pair["source"]["pull_request"]
    return (
        pair["provider"],
        pair["target"]["org"],
        str(pull_request.get("project") or ""),
        str(pull_request.get("repository") or pair["source"]["repo"]),
        str(pull_request["id"]),
    )


def parent_identity(pair: dict) -> tuple[str, ...]:
    return (
        pair["provider"],
        pair["target"]["org"],
        str(pair["target"]["parent"]["id"]),
    )


def artifact_name(pair: dict) -> str:
    pull_request = pair["source"]["pull_request"]
    return f"{slugify(pair['source']['repo'])}-pr-{pull_request['id']}.json"


def compose_release(release: str, pair_plans: list[dict]) -> dict:
    if not release.strip():
        raise TaskPlanError("release slug must not be empty")
    if not pair_plans:
        raise TaskPlanError("at least one --pair-plan is required")

    seen_prs: set[tuple[str, ...]] = set()
    seen_parents: set[tuple[str, ...]] = set()
    seen_artifacts: set[str] = set()
    languages: set[str] = set()
    for pair in pair_plans:
        verify_pair_plan(pair)
        pr_key = pr_identity(pair)
        parent_key = parent_identity(pair)
        if pr_key in seen_prs:
            raise TaskPlanError(f"duplicate PR in release: {pr_key}")
        if parent_key in seen_parents:
            raise TaskPlanError(f"duplicate User Story in release: {parent_key}")
        filename = artifact_name(pair)
        if filename in seen_artifacts:
            raise TaskPlanError(f"pair artifact filename collision: {filename}")
        seen_prs.add(pr_key)
        seen_parents.add(parent_key)
        seen_artifacts.add(filename)
        languages.add(pair.get("language", "en"))
    if len(languages) != 1:
        raise TaskPlanError(f"pair plans disagree on language: {sorted(languages)}")

    ordered = sorted(pair_plans, key=pr_identity)
    plan = {
        "schema_version": SCHEMA_VERSION,
        "kind": RELEASE_PLAN,
        "release": release,
        "language": languages.pop(),
        "pairs": ordered,
    }
    plan["plan_id"] = plan_hash(plan)
    return plan


def verify_release_plan(plan: dict) -> None:
    if plan.get("schema_version") != SCHEMA_VERSION or plan.get("kind") != RELEASE_PLAN:
        raise TaskPlanError("apply requires a composed release plan")
    if plan.get("plan_id") != plan_hash(plan):
        raise TaskPlanError("release plan content does not match its plan_id")
    canonical = compose_release(plan.get("release") or "", plan.get("pairs") or [])
    if plan.get("language") != canonical["language"]:
        raise TaskPlanError("release plan language differs from its pair plans")
    if plan.get("pairs") != canonical["pairs"]:
        raise TaskPlanError("release plan pairs are not in canonical order")


def print_pair_plan(plan: dict) -> None:
    pull_request = plan["source"]["pull_request"]
    parent = plan["target"]["parent"]
    print(
        f"pair plan {plan['plan_id']}: PR {pull_request['id']} -> "
        f"{parent['type']} {parent['id']}"
    )
    for action in plan["actions"]:
        if action["operation"] == "create":
            detail = "create"
        else:
            detail = (
                f"reuse {action['item_id']}; {action['description_action']} description"
            )
        print(f"  [{detail}] {action['title']} <- {action['folder']}")
    if pull_request.get("state") not in (None, "active", "OPEN"):
        print(f"warning: PR state is {pull_request['state']}")
    print("pair dry run only; compose a release plan before apply")


def print_release_plan(plan: dict) -> None:
    tasks = sum(len(pair["actions"]) for pair in plan["pairs"])
    repos = {pr_identity(pair)[:-1] for pair in plan["pairs"]}
    print(
        f"release plan {plan['plan_id']}: {len(plan['pairs'])} PR/User Story "
        f"pairs, {len(repos)} repositories, {tasks} Tasks"
    )
    for pair in plan["pairs"]:
        pull_request = pair["source"]["pull_request"]
        parent = pair["target"]["parent"]
        print(
            f"  {pair['source']['repo']}: PR {pull_request['id']} -> "
            f"{parent['type']} {parent['id']}"
        )
    print("dry run: no work-item writes applied")


def result_path_for(plan_path: Path) -> Path:
    return plan_path.with_name(f"{plan_path.stem}.result.json")


def load_result(path: Path, release_plan: dict) -> dict:
    if not path.exists():
        return {
            "schema_version": SCHEMA_VERSION,
            "kind": RELEASE_RESULT,
            "plan_id": release_plan["plan_id"],
            "release": release_plan["release"],
            "pairs": {},
            "artifacts": [],
        }
    result = read_object(path)
    if result.get("kind") != RELEASE_RESULT:
        raise TaskPlanError(f"invalid release result artifact: {path}")
    if result.get("plan_id") != release_plan["plan_id"]:
        raise TaskPlanError(f"result artifact belongs to a different plan: {path}")
    if not isinstance(result.get("pairs"), dict):
        raise TaskPlanError(f"invalid pair results in {path}")
    return result


def runtime_for_pair(pair: dict) -> tuple[Path, dict, Provider]:
    repo = Path(pair["source"]["repo_path"])
    if not repo.is_dir():
        raise TaskPlanError(f"pair repository is unavailable: {repo}")
    config = effective_config(repo)
    provider = from_config(config)
    return repo, config, provider


def assert_pair_context(
    pair: dict, config: dict, provider: Provider, repo: Path
) -> None:
    target = pair["target"]
    if pair["provider"] != config["provider"]:
        raise TaskPlanError("configured provider differs from pair plan")
    if target["org"] != config["org"]:
        raise TaskPlanError("configured organization differs from pair plan")
    if target.get("project") != config.get("work_item_project"):
        raise TaskPlanError("configured work-item project differs from pair plan")
    source = pair["source"]
    if (
        source["repo"] != config["repo"]
        or repo.resolve() != Path(source["repo_path"]).resolve()
    ):
        raise TaskPlanError("current repository differs from pair plan")
    if git_revision(repo, source["base"]) != source["base_commit"]:
        raise TaskPlanError(f"git ref drift detected: {source['base']}")
    if git_revision(repo, source["head"]) != source["head_commit"]:
        raise TaskPlanError(f"git ref drift detected: {source['head']}")

    expected_pr = source["pull_request"]
    current_pr = provider.fetch_pr(str(expected_pr["id"]))
    for field in ("id", "source", "target", "repository", "project"):
        if normalized_ref(str(current_pr.get(field) or "")) != normalized_ref(
            str(expected_pr.get(field) or "")
        ):
            raise TaskPlanError(
                f"PR {expected_pr['id']} changed {field} after pair planning"
            )


def preflight_pair(
    pair: dict,
    pair_result: dict,
    runtime: tuple[Path, dict, Provider] | None = None,
) -> dict:
    verify_pair_plan(pair)
    repo, config, provider = runtime or runtime_for_pair(pair)
    assert_pair_context(pair, config, provider, repo)

    completed = pair_result.get("completed") or {}
    if not isinstance(completed, dict):
        raise TaskPlanError(f"invalid completed actions for pair {pair['plan_id']}")
    expected_parent = pair["target"]["parent"]
    parent_id = str(expected_parent["id"])
    parent = provider.fetch_item(parent_id)
    validate_parent(parent, config.get("parent_types") or [])
    if not completed and parent.get("rev") != expected_parent.get("rev"):
        raise TaskPlanError(f"parent {parent_id} changed after pair planning")
    for field in ("System.AreaPath", "System.IterationPath"):
        if parent.get(field) != expected_parent.get(field):
            raise TaskPlanError(f"parent {parent_id} changed {field} after planning")

    children = provider.fetch_children([parent_id], config.get("child_types") or [])
    children_by_id = {str(child["id"]): child for child in children}
    conventions = Conventions(config)
    for action in pair["actions"]:
        done = completed.get(action["task_key"])
        if done:
            item_id = str(done["item_id"])
            if item_id not in children_by_id:
                raise TaskPlanError(
                    f"completed Task {item_id} is no longer a child of {parent_id}"
                )
            continue
        if action["operation"] == "create":
            conflicts = match_children([action], children, conventions)
            if conflicts:
                conflict = conflicts[action["task_key"]]
                raise TaskPlanError(
                    f"matching Task {conflict['id']} appeared after planning: "
                    f"{action['title']}"
                )
            continue
        item_id = str(action["item_id"])
        child = children_by_id.get(item_id)
        if child is None:
            raise TaskPlanError(f"planned Task {item_id} is no longer a child")
        if child.get("rev") != action.get("expected_rev"):
            raise TaskPlanError(f"planned Task {item_id} changed after planning")
        if (
            content_hash(child.get("description") or "")
            != action["current_description_hash"]
        ):
            raise TaskPlanError(
                f"planned Task {item_id} description changed after planning"
            )

    return {
        "repo": repo,
        "config": config,
        "provider": provider,
        "parent_id": parent_id,
        "children": children,
        "children_by_id": children_by_id,
        "completed": completed,
    }


def apply_pair(
    pair: dict, runtime: dict, result: dict, result_path: Path
) -> list[dict]:
    provider: Provider = runtime["provider"]
    parent_id = runtime["parent_id"]
    children = runtime["children"]
    children_by_id = runtime["children_by_id"]
    completed = runtime["completed"]
    tasks: list[dict] = []

    for action in pair["actions"]:
        task_key = action["task_key"]
        done = completed.get(task_key)
        if done:
            item_id = str(done["item_id"])
        elif action["operation"] == "create":
            created = provider.create_child(parent_id, action)
            item_id = str(created["id"])
            children.append(created)
            children_by_id[item_id] = created
            completed[task_key] = {"item_id": item_id, "operation": "create"}
        else:
            item_id = str(action["item_id"])
            marker = None
            if action["description_action"] == "update":
                marker = provider.set_description(item_id, action["description"])
            completed[task_key] = {
                "item_id": item_id,
                "operation": "reuse",
                "description_action": action["description_action"],
                "marker": marker,
            }

        applied_description = action["description"]
        if action["operation"] == "reuse" and action["description_action"] == "skip":
            applied_description = children_by_id[item_id].get("description") or ""
        tasks.append(
            {
                "id": item_id,
                "title": action["title"],
                "type": "Task",
                "folder": action["folder"],
                "description": applied_description,
                "url": provider.item_url(item_id),
            }
        )
        pair_result = result["pairs"][pair["plan_id"]]
        pair_result["completed"] = completed
        pair_result["tasks"] = tasks
        write_object(result_path, result)
    return tasks


def write_pair_artifact(
    release: str,
    pair: dict,
    tasks: list[dict],
    runs_dir: Path = RUNS_DIR,
) -> Path:
    artifact = {
        "release": release,
        "repo": pair["source"]["repo"],
        "provider": pair["provider"],
        "org": pair["target"]["org"],
        "project": pair["source"]["pull_request"].get("project"),
        "language": pair.get("language", "en"),
        "body_format": pair["body_format"],
        "applied": True,
        "base": pair["source"]["base"],
        "head": pair["source"]["head"],
        "pull_request": pair["source"]["pull_request"],
        "parent": pair["target"]["parent"],
        "unclaimed_folders": pair.get("unclaimed_folders", []),
        "tasks": tasks,
    }
    path = runs_dir / release / artifact_name(pair)
    write_object(path, artifact)
    return path


def apply_release(
    plan: dict,
    result_path: Path,
    runtime_factory=runtime_for_pair,
    artifact_writer=write_pair_artifact,
) -> dict:
    verify_release_plan(plan)
    result = load_result(result_path, plan)

    runtimes: dict[str, dict] = {}
    for pair in plan["pairs"]:
        pair_result = result["pairs"].setdefault(
            pair["plan_id"], {"completed": {}, "tasks": [], "artifact": None}
        )
        runtimes[pair["plan_id"]] = preflight_pair(
            pair, pair_result, runtime_factory(pair)
        )

    artifacts: list[str] = []
    for pair in plan["pairs"]:
        pair_result = result["pairs"][pair["plan_id"]]
        tasks = apply_pair(pair, runtimes[pair["plan_id"]], result, result_path)
        artifact = artifact_writer(plan["release"], pair, tasks)
        pair_result["artifact"] = str(artifact)
        artifacts.append(str(artifact))
        result["artifacts"] = artifacts
        write_object(result_path, result)

    task_count = sum(len(pair["tasks"]) for pair in result["pairs"].values())
    print(
        f"applied release plan {plan['plan_id']}: "
        f"{len(plan['pairs'])} pairs, {task_count} Tasks ready"
    )
    print(f"result: {result_path}")
    return result


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    commands = parser.add_subparsers(dest="command", required=True)

    plan = commands.add_parser("plan", help="generate one PR/User Story pair plan")
    plan.add_argument("--repo", type=Path, default=None)
    plan.add_argument("--pr-id", required=True)
    plan.add_argument("--parent-id", required=True)
    plan.add_argument("--evidence", required=True, type=Path)
    plan.add_argument("--descriptions", required=True, type=Path)
    plan.add_argument("--out", required=True, type=Path)
    plan.add_argument(
        "--overwrite",
        action="store_true",
        help="record replacement of populated matching descriptions",
    )

    compose = commands.add_parser("compose", help="compose the applicable release plan")
    compose.add_argument("--release", required=True)
    compose.add_argument("--pair-plan", required=True, action="append", type=Path)
    compose.add_argument("--out", required=True, type=Path)

    apply = commands.add_parser("apply", help="apply an approved release plan")
    apply.add_argument("--plan", required=True, type=Path)
    apply.add_argument("--result", type=Path, default=None)
    return parser


def main() -> None:
    args = build_parser().parse_args()
    if args.command == "plan":
        repo = repo_root(args.repo)
        config = effective_config(repo)
        provider = from_config(config)
        pair = build_pair_plan(
            provider,
            config,
            args.pr_id,
            args.parent_id,
            read_object(args.evidence),
            read_object(args.descriptions),
            repo,
            args.overwrite,
        )
        write_object(args.out, pair)
        print_pair_plan(pair)
        print(f"pair plan artifact: {args.out}")
        return

    if args.command == "compose":
        release = compose_release(
            args.release, [read_object(path) for path in args.pair_plan]
        )
        write_object(args.out, release)
        print_release_plan(release)
        print(f"release plan artifact: {args.out}")
        return

    plan = read_object(args.plan)
    apply_release(plan, args.result or result_path_for(args.plan))


if __name__ == "__main__":
    main()
