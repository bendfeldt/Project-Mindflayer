#!/usr/bin/env python3
"""Dependency-free tests for release task discovery, planning, and apply."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from collect_evidence import Conventions
from config import ConfigError, default_repo_config, resolve_run_directory
from manage_tasks import (
    TaskPlanError,
    apply_release,
    build_pair_plan,
    compose_release,
    verify_release_plan,
    write_pair_artifact,
)
from merge_release import STRINGS, load_artifacts, render_md
from providers import AdoProvider, Provider
from publish_descriptions import write_artifact as write_description_artifact


class FakeProvider(Provider):
    body_format = "html"
    can_create_children = True

    def __init__(self, pr_id: str, parent_id: str, repository: str) -> None:
        self.pr = {
            "id": pr_id,
            "title": f"Release {repository}",
            "state": "active",
            "source": "HEAD",
            "target": "HEAD",
            "repository": repository,
            "project": "Project",
            "url": f"https://example.invalid/{repository}/pullrequest/{pr_id}",
        }
        self.parent = {
            "id": parent_id,
            "rev": 7,
            "title": f"User Story {parent_id}",
            "type": "User Story",
            "state": "Active",
            "System.AreaPath": "Project\\Delivery",
            "System.IterationPath": "Project\\Sprint 1",
            "url": f"https://example.invalid/workitems/{parent_id}",
        }
        self.children = [
            {
                "id": f"{parent_id}0",
                "rev": 3,
                "title": "Report: Sales",
                "type": "Task",
                "state": "New",
                "description": "",
                "url": f"https://example.invalid/workitems/{parent_id}0",
            }
        ]
        self.validated: list[str] = []
        self.created: list[str] = []
        self.updated: list[str] = []

    def fetch_pr(self, pr_id: str) -> dict:
        assert pr_id == self.pr["id"]
        return copy.deepcopy(self.pr)

    def fetch_item(self, item_id: str) -> dict:
        assert item_id == self.parent["id"]
        return copy.deepcopy(self.parent)

    def fetch_children(
        self, parent_ids: list[str], child_types: list[str]
    ) -> list[dict]:
        assert parent_ids == [self.parent["id"]]
        assert child_types == ["Task"]
        return copy.deepcopy(self.children)

    def validate_child(self, parent_id: str, task: dict) -> None:
        assert parent_id == self.parent["id"]
        self.validated.append(task["task_key"])

    def create_child(self, parent_id: str, task: dict) -> dict:
        assert parent_id == self.parent["id"]
        item_id = f"{parent_id}1"
        item = {
            "id": item_id,
            "rev": 1,
            "title": task["title"],
            "type": "Task",
            "state": "New",
            "description": task["description"],
            "url": self.item_url(item_id),
        }
        self.children.append(item)
        self.created.append(task["task_key"])
        return copy.deepcopy(item)

    def set_description(self, item_id: str, body: str) -> str:
        self.updated.append(item_id)
        for child in self.children:
            if child["id"] == item_id:
                child["description"] = body
                child["rev"] += 1
        return "rev 4"

    def item_url(self, item_id: str) -> str:
        return f"https://example.invalid/workitems/{item_id}"


def repository_root() -> Path:
    proc = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    )
    return Path(proc.stdout.strip())


def config(repository: str) -> dict:
    value = default_repo_config("ado", "Project")
    value.update(
        {
            "provider": "ado",
            "org": "contoso",
            "repo": repository,
            "repo_path": str(repository_root()),
        }
    )
    return value


def evidence() -> dict:
    return {
        "base": "HEAD",
        "head": "HEAD",
        "unclaimed_folders": ["automation/release.yml"],
        "tasks": {
            "solution/models/Sales.SemanticModel": {
                "task_key": "solution/models/Sales.SemanticModel",
                "folder": "solution/models/Sales.SemanticModel",
                "title": "Model: Sales",
            },
            "solution/reports/Sales.Report": {
                "task_key": "solution/reports/Sales.Report",
                "folder": "solution/reports/Sales.Report",
                "title": "Report: Sales",
            },
        },
    }


def descriptions() -> dict:
    return {
        "solution/models/Sales.SemanticModel": "<b>Changes</b><p>Model</p>",
        "solution/reports/Sales.Report": "<b>Changes</b><p>Report</p>",
    }


def pair_plan(provider: FakeProvider, repository: str) -> dict:
    return build_pair_plan(
        provider,
        config(repository),
        provider.pr["id"],
        provider.parent["id"],
        evidence(),
        descriptions(),
        repository_root(),
        False,
    )


def assert_raises(function, expected_text: str) -> None:
    try:
        function()
    except TaskPlanError as exc:
        assert expected_text in str(exc), str(exc)
        return
    raise AssertionError(f"expected TaskPlanError containing {expected_text!r}")


def test_unique_titles() -> None:
    conventions = Conventions(config("Repo"))
    folders = {
        "solution/a/Sales.SemanticModel",
        "solution/b/Sales.SemanticModel",
        "solution/reports/Sales.Report",
    }
    titles = conventions.task_titles(folders)
    assert titles["solution/a/Sales.SemanticModel"] == "Model: a/Sales"
    assert titles["solution/b/Sales.SemanticModel"] == "Model: b/Sales"
    assert titles["solution/reports/Sales.Report"] == "Report: Sales"


def test_ado_child_payload() -> None:
    provider = AdoProvider("contoso", "Project Name")
    patch = provider._child_patch(
        "100",
        {
            "title": "Model: Sales",
            "description": "<b>Changes</b>",
            "System.AreaPath": "Project\\Delivery",
            "System.IterationPath": "Project\\Sprint 1",
        },
    )
    paths = {operation["path"] for operation in patch}
    assert "/fields/System.Title" in paths
    assert "/fields/System.Description" in paths
    assert "/fields/System.AreaPath" in paths
    assert "/fields/System.IterationPath" in paths
    relation = patch[-1]["value"]
    assert relation["rel"] == "System.LinkTypes.Hierarchy-Reverse"
    assert relation["url"].endswith("/workItems/100")


def git_revision(repository: Path, ref: str) -> str:
    proc = subprocess.run(
        ["git", "rev-parse", ref],
        cwd=repository,
        capture_output=True,
        text=True,
        check=True,
    )
    return proc.stdout.strip()


def test_id_free_evidence_discovery() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repository = Path(directory)
        subprocess.run(["git", "init", "-q"], cwd=repository, check=True)
        for key, value in (
            ("user.email", "test@example.invalid"),
            ("user.name", "Release Test"),
            ("core.autocrlf", "false"),
        ):
            subprocess.run(["git", "config", key, value], cwd=repository, check=True)
        model_file = (
            repository
            / "solution/models/Sales.SemanticModel/definition/tables/Sales.tmdl"
        )
        model_file.parent.mkdir(parents=True)
        model_file.write_text("measure Revenue = 1\n")
        subprocess.run(["git", "add", "."], cwd=repository, check=True)
        subprocess.run(
            ["git", "commit", "-qm", "test: base"], cwd=repository, check=True
        )
        base = git_revision(repository, "HEAD")

        model_file.write_text("measure Revenue = 2\n")
        automation = repository / "automation/release.yml"
        automation.parent.mkdir()
        automation.write_text("trigger: none\n")
        subprocess.run(["git", "add", "."], cwd=repository, check=True)
        subprocess.run(
            ["git", "commit", "-qm", "test: release"], cwd=repository, check=True
        )
        head = git_revision(repository, "HEAD")
        output = repository / "evidence.json"
        script = Path(__file__).with_name("collect_evidence.py")
        subprocess.run(
            [
                sys.executable,
                str(script),
                "--repo",
                str(repository),
                "--base",
                base,
                "--head",
                head,
                "--out",
                str(output),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        discovered = json.loads(output.read_text())
        task = discovered["tasks"]["solution/models/Sales.SemanticModel"]
        assert task["title"] == "Model: Sales"
        assert "automation/release.yml" in discovered["unclaimed_folders"]


def test_multi_pair_release_and_merge() -> None:
    provider_a = FakeProvider("1", "100", "RepoA")
    provider_b = FakeProvider("2", "200", "RepoB")
    provider_c = FakeProvider("3", "300", "RepoA")
    pair_a = pair_plan(provider_a, "RepoA")
    pair_b = pair_plan(provider_b, "RepoB")
    pair_c = pair_plan(provider_c, "RepoA")
    assert provider_a.validated == ["solution/models/Sales.SemanticModel"]
    assert provider_b.validated == ["solution/models/Sales.SemanticModel"]
    assert provider_c.validated == ["solution/models/Sales.SemanticModel"]

    release = compose_release("rel-1", [pair_b, pair_c, pair_a])
    verify_release_plan(release)
    assert [pair["source"]["repo"] for pair in release["pairs"]] == [
        "RepoA",
        "RepoA",
        "RepoB",
    ]

    root = repository_root()
    runtimes = {
        pair_a["plan_id"]: (root, config("RepoA"), provider_a),
        pair_b["plan_id"]: (root, config("RepoB"), provider_b),
        pair_c["plan_id"]: (root, config("RepoA"), provider_c),
    }
    with tempfile.TemporaryDirectory() as directory:
        output_root = Path(directory)
        result_path = output_root / "release-result.json"

        def writer(slug, pair, tasks):
            return write_pair_artifact(slug, pair, tasks, output_root)

        def runtime_factory(pair):
            return runtimes[pair["plan_id"]]

        result = apply_release(release, result_path, runtime_factory, writer)
        assert provider_a.created == ["solution/models/Sales.SemanticModel"]
        assert provider_b.created == ["solution/models/Sales.SemanticModel"]
        assert provider_c.created == ["solution/models/Sales.SemanticModel"]
        assert provider_a.updated == ["1000"]
        assert provider_b.updated == ["2000"]
        assert provider_c.updated == ["3000"]
        assert len(result["artifacts"]) == 3
        assert {Path(path).name for path in result["artifacts"]} == {
            "repoa-pr-1.json",
            "repoa-pr-3.json",
            "repob-pr-2.json",
        }

        apply_release(release, result_path, runtime_factory, writer)
        assert provider_a.created == ["solution/models/Sales.SemanticModel"]
        assert provider_b.created == ["solution/models/Sales.SemanticModel"]
        assert provider_c.created == ["solution/models/Sales.SemanticModel"]
        assert provider_a.updated == ["1000"]
        assert provider_b.updated == ["2000"]
        assert provider_c.updated == ["3000"]

        artifacts = [json.loads(Path(path).read_text()) for path in result["artifacts"]]
        markdown = render_md("rel-1", artifacts, STRINGS["en"])
        assert "RepoA — PR 1 → User Story 100" in markdown
        assert "RepoB — PR 2 → User Story 200" in markdown
        assert "RepoA — PR 3 → User Story 300" in markdown
        assert "[RepoA PR 1](https://example.invalid/RepoA/pullrequest/1)" in markdown
        assert (
            "[RepoA User Story 100](https://example.invalid/workitems/100)" in markdown
        )


def test_all_pairs_preflight_before_write() -> None:
    provider_a = FakeProvider("1", "100", "RepoA")
    provider_b = FakeProvider("2", "200", "RepoB")
    pair_a = pair_plan(provider_a, "RepoA")
    pair_b = pair_plan(provider_b, "RepoB")
    release = compose_release("rel-1", [pair_a, pair_b])
    provider_b.parent["rev"] += 1
    root = repository_root()
    runtimes = {
        pair_a["plan_id"]: (root, config("RepoA"), provider_a),
        pair_b["plan_id"]: (root, config("RepoB"), provider_b),
    }
    with tempfile.TemporaryDirectory() as directory:
        assert_raises(
            lambda: apply_release(
                release,
                Path(directory) / "result.json",
                lambda pair: runtimes[pair["plan_id"]],
                lambda *_: Path(directory) / "unused.json",
            ),
            "changed after pair planning",
        )
    assert provider_a.created == []
    assert provider_a.updated == []


def test_populated_description_is_preserved() -> None:
    provider = FakeProvider("1", "100", "RepoA")
    provider.children[0]["description"] = "<p>Tester notes</p>"
    pair = pair_plan(provider, "RepoA")
    report = next(
        action
        for action in pair["actions"]
        if action["task_key"] == "solution/reports/Sales.Report"
    )
    assert report["description_action"] == "skip"
    release = compose_release("rel-1", [pair])
    runtime = (repository_root(), config("RepoA"), provider)
    with tempfile.TemporaryDirectory() as directory:
        output_root = Path(directory)

        def writer(slug, pair_plan, tasks):
            return write_pair_artifact(slug, pair_plan, tasks, output_root)

        result = apply_release(
            release,
            output_root / "result.json",
            lambda _pair: runtime,
            writer,
        )
        artifact = json.loads(Path(result["artifacts"][0]).read_text())
        report_task = next(task for task in artifact["tasks"] if task["id"] == "1000")
        assert report_task["description"] == "<p>Tester notes</p>"
        assert provider.updated == []


def test_cardinality_ref_and_integrity_failures() -> None:
    provider_a = FakeProvider("1", "100", "RepoA")
    pair_a = pair_plan(provider_a, "RepoA")
    assert_raises(lambda: compose_release("rel-1", [pair_a, pair_a]), "duplicate PR")

    provider_same_parent = FakeProvider("3", "100", "RepoC")
    pair_same_parent = pair_plan(provider_same_parent, "RepoC")
    assert_raises(
        lambda: compose_release("rel-1", [pair_a, pair_same_parent]),
        "duplicate User Story",
    )

    release = compose_release("rel-1", [pair_a])
    tampered = copy.deepcopy(release)
    tampered["release"] = "changed"
    assert_raises(lambda: verify_release_plan(tampered), "plan_id")
    with tempfile.TemporaryDirectory() as directory:
        assert_raises(
            lambda: apply_release(pair_a, Path(directory) / "result.json"),
            "composed release plan",
        )

    mismatch = FakeProvider("4", "400", "RepoD")
    mismatch.pr["target"] = "main"
    assert_raises(lambda: pair_plan(mismatch, "RepoD"), "does not match PR target")


def test_release_slug_validation_and_containment() -> None:
    with tempfile.TemporaryDirectory() as directory:
        runs_dir = Path(directory) / "runs"
        assert resolve_run_directory("R.1_test-2", runs_dir) == (
            runs_dir / "R.1_test-2"
        ).resolve()

        invalid_slugs = [
            "",
            "_release",
            "../release",
            "release/child",
            "release\\child",
            "rélease",
            "a" * 129,
        ]
        for slug in invalid_slugs:
            try:
                resolve_run_directory(slug, runs_dir)
            except ConfigError:
                pass
            else:
                raise AssertionError(f"expected invalid release slug: {slug!r}")

        runs_dir.mkdir()
        outside = Path(directory) / "outside"
        outside.mkdir()
        try:
            (runs_dir / "release").symlink_to(outside, target_is_directory=True)
        except OSError:
            return
        try:
            resolve_run_directory("release", runs_dir)
        except ConfigError as exc:
            assert "outside configured root" in str(exc)
        else:
            raise AssertionError("expected an escaping run-directory symlink to fail")


def test_compose_rejects_unsafe_release_slug() -> None:
    assert_raises(lambda: compose_release("../release", []), "release slug must be")


def test_publish_and_merge_reject_unsafe_release_slug() -> None:
    provider = FakeProvider("1", "100", "RepoA")
    operations = [
        lambda: load_artifacts("../release"),
        lambda: write_description_artifact(
            "../release", config("RepoA"), provider, {}, None, False
        ),
    ]
    for operation in operations:
        try:
            operation()
        except ConfigError:
            pass
        else:
            raise AssertionError("expected unsafe release slug to fail")


def main() -> int:
    tests = [
        test_unique_titles,
        test_ado_child_payload,
        test_id_free_evidence_discovery,
        test_multi_pair_release_and_merge,
        test_all_pairs_preflight_before_write,
        test_populated_description_is_preserved,
        test_cardinality_ref_and_integrity_failures,
        test_release_slug_validation_and_containment,
        test_compose_rejects_unsafe_release_slug,
        test_publish_and_merge_reject_unsafe_release_slug,
    ]
    for test in tests:
        test()
    print(f"ok — {len(tests)} release task planning tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
