#!/usr/bin/env python3
"""Plan source/User Story pairs, compose a release, and apply child Tasks.

A release source is a PR (--pr-id) or a plain comparison of the evidence's
base and head (--compare). Tasks go under one named parent (--parent-id) or
under the User Story linked to each Task's top-contributing PR
(--original-parents), which yields one pair per parent.

Pair planning is non-mutating. Composition creates the only applicable plan
type, so one reviewed release plan is the approval boundary for every pair.

Usage:
  manage_tasks.py plan (--pr-id 123 | --compare) \
    (--parent-id 456 | --original-parents [--fallback-parent-id 789]) \
    --evidence evidence.json --descriptions descriptions.json \
    --out pair-plan.json [--repo .]
  manage_tasks.py compose --release rel_1 --pair-plan pair-a.json \
    --pair-plan pair-b.json --out release-plan.json
  manage_tasks.py apply --plan release-plan.json [--result result.json]
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from collect_evidence import Conventions  # noqa: E402
from config import (  # noqa: E402
    RUNS_DIR,
    ConfigError,
    configure_stdio,
    effective_config,
    read_json,
    repo_root,
    resolve_run_directory,
    run_capture,
    slugify,
    write_json,
)
from providers import (  # noqa: E402
    Provider, choose_assignee, from_config, top_contributor,
)


SCHEMA_VERSION = 2
PAIR_PLAN = "release-task-pair-plan"
RELEASE_PLAN = "release-task-release-plan"
RELEASE_RESULT = "release-task-release-result"


class TaskPlanError(SystemExit):
    """Actionable plan, mapping, or drift failure."""


def read_value(path: Path) -> dict | list:
    try:
        return read_json(path)
    except FileNotFoundError:
        raise TaskPlanError(f"file not found: {path}")
    except json.JSONDecodeError as exc:
        raise TaskPlanError(f"malformed JSON in {path}: {exc}")


def read_object(path: Path) -> dict:
    value = read_value(path)
    if not isinstance(value, dict):
        raise TaskPlanError(f"expected a JSON object in {path}")
    return value


def read_pair_plans(path: Path) -> list[dict]:
    """A plan file holds one pair, or a list of pairs from --original-parents."""
    value = read_value(path)
    pairs = value if isinstance(value, list) else [value]
    if not all(isinstance(pair, dict) for pair in pairs):
        raise TaskPlanError(f"expected pair plan objects in {path}")
    return pairs


def write_object(path: Path, value: dict | list) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    write_json(path, value)


def content_hash(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def plan_hash(plan: dict) -> str:
    payload = {key: value for key, value in plan.items() if key != "plan_id"}
    encoded = json.dumps(
        payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def git_revision(repo: Path, ref: str) -> str:
    proc = run_capture(
        ["git", "rev-parse", "--verify", f"{ref}^{{commit}}"], cwd=repo
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
        # Asset Tasks match by exact title only; their leaf names repeat across solutions.
        possible = exact or [
            child
            for child in children
            if not candidate.get("asset")
            and is_legacy_match(child, candidate, conventions)
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
        contributions = sorted(task.get("contributions") or [],
                               key=lambda item: item.get("order", 0))
        prs = list(dict.fromkeys(str(c["pr"]) for c in contributions if c.get("pr")))
        candidates.append(
            {
                "task_key": task_key,
                "folder": str(folder),
                "title": str(title),
                "asset": bool(task.get("asset")),
                "contributions": contributions,
                "prs": prs,
                "direct_commits": any(not c.get("pr") for c in contributions),
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


def original_parent(
    provider: Provider, config: dict, contributions: list[dict], cache: dict
) -> str | None:
    """The User Story holding most of a Task's PR lines; a tie goes to the newest.

    A PR counts only when it links exactly one allowed parent; direct commits
    and PRs with no (or several) linked parents are left for the fallback.
    """
    allowed = config.get("parent_types") or []
    entries = []
    for item in contributions:
        if not item.get("pr"):
            continue
        pr = str(item["pr"])
        if pr not in cache:
            linked = [
                parent_id for parent_id in provider.fetch_pr_parents(pr)
                if not allowed or provider.fetch_item(parent_id).get("type") in allowed
            ]
            cache[pr] = linked[0] if len(linked) == 1 else None
        if cache[pr]:
            entries.append((cache[pr], int(item["lines"]), int(item["order"])))
    return top_contributor(entries)


def plan_release_pairs(
    provider: Provider,
    config: dict,
    pr_id: str | None,
    evidence: dict,
    descriptions: dict,
    repo: Path,
    overwrite: bool,
    parent_id: str | None = None,
    fallback_parent_id: str | None = None,
) -> list[dict]:
    """One pair for a named parent, or one pair per original User Story."""
    if parent_id:
        return [build_pair_plan(provider, config, pr_id, parent_id, evidence,
                                descriptions, repo, overwrite)]
    groups: dict[str, set[str]] = {}
    unresolved: list[str] = []
    cache: dict = {}
    for candidate in candidates_from_evidence(evidence, descriptions):
        parent = original_parent(provider, config, candidate["contributions"], cache)
        parent = parent or fallback_parent_id
        if parent is None:
            unresolved.append(candidate["title"])
            continue
        groups.setdefault(parent, set()).add(candidate["task_key"])
    if unresolved:
        raise TaskPlanError(
            "no linked User Story for: " + "; ".join(unresolved)
            + " — pass --fallback-parent-id <id> to place them"
        )
    return [
        build_pair_plan(provider, config, pr_id, parent, evidence, descriptions,
                        repo, overwrite, only=keys)
        for parent, keys in sorted(groups.items())
    ]


def build_pair_plan(
    provider: Provider,
    config: dict,
    pr_id: str | None,
    parent_id: str,
    evidence: dict,
    descriptions: dict,
    repo: Path,
    overwrite: bool,
    only: set[str] | None = None,
) -> dict:
    if not provider.can_create_children:
        raise TaskPlanError(
            f"provider {config['provider']} does not support planned child creation"
        )

    pull_request = provider.fetch_pr(pr_id) if pr_id else None
    if pull_request:
        validate_evidence_refs(evidence, pull_request)
    elif not evidence.get("base") or not evidence.get("head"):
        raise TaskPlanError("evidence needs base and head refs")
    parent = provider.fetch_item(parent_id)
    validate_parent(parent, config.get("parent_types") or [])

    conventions = Conventions(config)
    candidates = [
        candidate for candidate in candidates_from_evidence(evidence, descriptions)
        if only is None or candidate["task_key"] in only
    ]
    children = provider.fetch_children([parent_id], config.get("child_types") or [])
    existing = match_children(candidates, children, conventions)

    actions: list[dict] = []
    identities: dict = {}
    for candidate in candidates:
        contributions = candidate.pop("contributions")
        child = existing.get(candidate["task_key"])
        assignee, reason = None, "assignment not supported"
        if provider.can_assign and child and child.get("assigned_to"):
            reason = "keep assignee"
        elif provider.can_assign:
            assignee, reason = choose_assignee(provider, contributions, identities)
        task = {
            **candidate,
            "assignee": assignee,
            "assignee_note": reason,
            "System.AreaPath": parent.get("System.AreaPath"),
            "System.IterationPath": parent.get("System.IterationPath"),
        }
        if child is None:
            provider.validate_child(parent_id, task)
            actions.append({**task, "operation": "create"})
            continue

        if assignee:
            provider.validate_assignee(str(child["id"]), assignee)
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


def source_identity(pair: dict) -> tuple[str, ...]:
    """The release source: a PR, or the pinned commits of a comparison."""
    source = pair["source"]
    pull_request = source["pull_request"] or {}
    return (
        pair["provider"],
        pair["target"]["org"],
        str(pull_request.get("project") or ""),
        str(pull_request.get("repository") or source["repo"]),
        f"pr {pull_request['id']}" if pull_request
        else f"{source['base_commit']}..{source['head_commit']}",
    )


def source_label(pair: dict) -> str:
    source = pair["source"]
    if source["pull_request"]:
        return f"PR {source['pull_request']['id']}"
    return f"{source['base']}..{source['head']}"


def parent_identity(pair: dict) -> tuple[str, ...]:
    return (
        pair["provider"],
        pair["target"]["org"],
        str(pair["target"]["parent"]["id"]),
    )


def artifact_name(pair: dict) -> str:
    source = pair["source"]
    label = (
        f"pr-{source['pull_request']['id']}" if source["pull_request"]
        else slugify(f"{source['base']}..{source['head']}")
    )
    parent = pair["target"]["parent"]["id"]
    return f"{slugify(source['repo'])}-{label}-{parent}.json"


def compose_release(release: str, pair_plans: list[dict]) -> dict:
    try:
        resolve_run_directory(release)
    except ConfigError as exc:
        raise TaskPlanError(str(exc)) from None
    if not pair_plans:
        raise TaskPlanError("at least one --pair-plan is required")

    # A source may feed several User Stories (--original-parents), but each
    # User Story takes one source, and each Task key appears once per source.
    seen_pairs: set[tuple] = set()
    seen_parents: set[tuple[str, ...]] = set()
    seen_tasks: set[tuple] = set()
    seen_artifacts: set[str] = set()
    languages: set[str] = set()
    for pair in pair_plans:
        verify_pair_plan(pair)
        source_key = source_identity(pair)
        parent_key = parent_identity(pair)
        if (source_key, parent_key) in seen_pairs:
            raise TaskPlanError(f"duplicate PR/User Story pair in release: {source_key}")
        if parent_key in seen_parents:
            raise TaskPlanError(f"duplicate User Story in release: {parent_key}")
        for action in pair["actions"]:
            task = (source_key, action["task_key"])
            if task in seen_tasks:
                raise TaskPlanError(f"Task {action['task_key']} planned twice for {source_key}")
            seen_tasks.add(task)
        filename = artifact_name(pair)
        if filename in seen_artifacts:
            raise TaskPlanError(f"pair artifact filename collision: {filename}")
        seen_pairs.add((source_key, parent_key))
        seen_parents.add(parent_key)
        seen_artifacts.add(filename)
        languages.add(pair.get("language", "en"))
    if len(languages) != 1:
        raise TaskPlanError(f"pair plans disagree on language: {sorted(languages)}")

    ordered = sorted(pair_plans, key=lambda pair: (source_identity(pair), parent_identity(pair)))
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


def summary_rows(pairs: list[dict]) -> list[list[str]]:
    """Task | Operation | Parent | PR(s) | Assignee, one row per planned action."""
    rows = []
    for pair in pairs:
        parent = pair["target"]["parent"]
        for action in pair["actions"]:
            if action["operation"] == "create":
                operation = "create"
            else:
                operation = (f"reuse {action['item_id']} "
                             f"({action['description_action']} description)")
            prs = [f"#{pr}" for pr in action.get("prs") or []]
            if action.get("direct_commits"):
                prs.append("direct commit")
            who = action.get("assignee")
            rows.append([
                action["title"],
                operation,
                f"{parent.get('type') or 'parent'} {parent['id']}",
                ", ".join(prs) or "—",
                who or f"none ({action.get('assignee_note') or 'no contributions'})",
            ])
    return rows


def print_summary(pairs: list[dict]) -> None:
    header = ["Task", "Operation", "Parent", "PR(s)", "Assignee"]
    print("| " + " | ".join(header) + " |")
    print("|" + "---|" * len(header))
    for row in summary_rows(pairs):
        print("| " + " | ".join(cell.replace("|", "\\|") for cell in row) + " |")


def print_pair_plan(plan: dict) -> None:
    pull_request = plan["source"]["pull_request"] or {}
    parent = plan["target"]["parent"]
    print(
        f"pair plan {plan['plan_id']}: {source_label(plan)} -> "
        f"{parent['type']} {parent['id']}\n"
    )
    print_summary([plan])
    if pull_request.get("state") not in (None, "active", "OPEN"):
        print(f"warning: PR state is {pull_request['state']}")
    print("\npair dry run only; compose a release plan before apply")


def print_release_plan(plan: dict) -> None:
    tasks = sum(len(pair["actions"]) for pair in plan["pairs"])
    repos = {source_identity(pair)[:-1] for pair in plan["pairs"]}
    print(
        f"release plan {plan['plan_id']}: {len(plan['pairs'])} source/User Story "
        f"pairs, {len(repos)} repositories, {tasks} Tasks"
    )
    for pair in plan["pairs"]:
        parent = pair["target"]["parent"]
        print(
            f"  {pair['source']['repo']}: {source_label(pair)} -> "
            f"{parent['type']} {parent['id']}"
        )
    print()
    print_summary(plan["pairs"])
    print("\ndry run: no work-item writes applied")


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
    if not expected_pr:
        return
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
            if action.get("assignee"):
                provider.set_assignee(item_id, action["assignee"])
            completed[task_key] = {
                "item_id": item_id,
                "operation": "reuse",
                "description_action": action["description_action"],
                "marker": marker,
                "assigned": action.get("assignee"),
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
        "project": (pair["source"]["pull_request"] or {}).get("project")
        or pair["target"].get("project"),
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
    try:
        run_dir = resolve_run_directory(release, runs_dir)
    except ConfigError as exc:
        raise TaskPlanError(str(exc)) from None
    path = run_dir / artifact_name(pair)
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

    plan = commands.add_parser("plan", help="generate source/User Story pair plans")
    plan.add_argument("--repo", type=Path, default=None)
    source = plan.add_mutually_exclusive_group(required=True)
    source.add_argument("--pr-id", help="the PR the release notes cover")
    source.add_argument("--compare", action="store_true",
                        help="no PR: cover the evidence's base..head comparison")
    parent = plan.add_mutually_exclusive_group(required=True)
    parent.add_argument("--parent-id", help="put every Task under this User Story")
    parent.add_argument("--original-parents", action="store_true",
                        help="put each Task under the User Story linked to its top PR")
    plan.add_argument("--fallback-parent-id",
                      help="with --original-parents: parent for Tasks with no linked one")
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
    configure_stdio()
    if args.command == "plan":
        repo = repo_root(args.repo)
        config = effective_config(repo)
        provider = from_config(config)
        if args.fallback_parent_id and not args.original_parents:
            raise TaskPlanError("--fallback-parent-id needs --original-parents")
        pairs = plan_release_pairs(
            provider,
            config,
            args.pr_id,
            read_object(args.evidence),
            read_object(args.descriptions),
            repo,
            args.overwrite,
            parent_id=args.parent_id,
            fallback_parent_id=args.fallback_parent_id,
        )
        write_object(args.out, pairs if args.original_parents else pairs[0])
        for pair in pairs:
            print_pair_plan(pair)
        print(f"pair plan artifact: {args.out}")
        return

    if args.command == "compose":
        release = compose_release(
            args.release,
            [pair for path in args.pair_plan for pair in read_pair_plans(path)],
        )
        write_object(args.out, release)
        print_release_plan(release)
        print(f"release plan artifact: {args.out}")
        return

    plan = read_object(args.plan)
    apply_release(plan, args.result or result_path_for(args.plan))


if __name__ == "__main__":
    main()
