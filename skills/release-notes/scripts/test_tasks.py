#!/usr/bin/env python3
"""Dependency-free tests for release task discovery, planning, and apply."""

from __future__ import annotations

import copy
import json
import subprocess
import sys
import tempfile
from pathlib import Path

from collect_evidence import Conventions, Git, assign_assets, map_tasks
from config import (
    DEFAULT_MERGE_PATTERNS,
    ConfigError,
    asset_rule_problems,
    configure_stdio,
    default_repo_config,
    resolve_run_directory,
)
from manage_tasks import (
    TaskPlanError,
    apply_release,
    build_pair_plan,
    compose_release,
    verify_release_plan,
    write_pair_artifact,
)
from merge_release import STRINGS, load_artifacts, render_md
import providers
from providers import (
    AdoProvider, GitHubProvider, Provider, ProviderError, choose_assignee,
)
from publish_descriptions import assign_items
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


ASSET_RULES = [
    {
        "kind": "Model",
        "pattern": r"^(?P<root>data_solution/(?P<solution>[^/]+))/transformation/models/"
        r"(?:.+/)?(?P<asset>[^/]+)/(?P=asset)\.(?:sql|yml)$",
    },
    {
        "kind": "Source",
        "pattern": r"^(?P<root>data_solution/(?P<solution>[^/]+))/source_configs/"
        r"(?P<asset>[^/]+)\.yaml$",
    },
    {
        "kind": "Source",
        "pattern": r"^(?P<root>data_solution/(?P<solution>[^/]+))/adapters/(?P<asset>[^/]+)\.py$",
    },
    {
        "kind": "Model",
        "pattern": r"^(?P<root>data_solution/(?P<solution>[^/]+))/transformation/tests/.+\.sql$",
        "resolve": "dbt_ref",
    },
]


def commit_all(repository: Path, message: str) -> str:
    subprocess.run(["git", "add", "-A"], cwd=repository, check=True)
    subprocess.run(["git", "commit", "-qm", message], cwd=repository, check=True)
    return git_revision(repository, "HEAD")


def write(repository: Path, relative: str, text: str) -> None:
    path = repository / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def git_as(repository: Path, email: str, *args: str) -> None:
    subprocess.run(
        ["git", "-c", f"user.email={email}", "-c", "user.name=Dev", *args],
        cwd=repository, check=True, capture_output=True,
    )


def change_and_commit(repository: Path, email: str, lines: int, message: str) -> None:
    with (repository / "f.txt").open("a") as handle:
        handle.write("x\n" * lines)
    git_as(repository, email, "commit", "-qam", message)


def merge_branch(repository: Path, email: str, branch: str, lines: int,
                 message: str, into: str = "main") -> None:
    git_as(repository, email, "switch", "-qc", branch, into)
    change_and_commit(repository, email, lines, f"work on {branch}")
    git_as(repository, email, "switch", "-q", into)
    git_as(repository, email, "merge", "-q", "--no-ff", branch, "-m", message)


def test_contributions() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repository = Path(directory)
        subprocess.run(["git", "init", "-q", "-b", "main"], cwd=repository, check=True)
        subprocess.run(["git", "config", "core.autocrlf", "false"], cwd=repository, check=True)
        write(repository, "f.txt", "start\n")
        write(repository, "other.txt", "start\n")
        git_as(repository, "base@x", "add", "-A")
        git_as(repository, "base@x", "commit", "-qm", "base")
        base = git_revision(repository, "HEAD")

        merge_branch(repository, "alice@x", "a", 10, "Merged PR 1: alice")
        merge_branch(repository, "bob@x", "b", 3, "Merge pull request #2 from x/b")
        change_and_commit(repository, "dave@x", 2, "Add thing (#3)")
        change_and_commit(repository, "carol@x", 1, "fix typo")
        write(repository, "other.txt", "unrelated\n")
        git_as(repository, "zed@x", "commit", "-qam", "Merged PR 8: unrelated file")
        # A sync PR that brings dev (holding PR 4) into main credits PR 4, not PR 9.
        git_as(repository, "erin@x", "branch", "dev", "main")
        merge_branch(repository, "erin@x", "e", 4, "Merged PR 4: erin", into="dev")
        git_as(repository, "sync@x", "merge", "-q", "--no-ff", "dev", "-m", "Merged PR 9: sync")
        head = git_revision(repository, "HEAD")

        patterns = [*DEFAULT_MERGE_PATTERNS["ado"], *DEFAULT_MERGE_PATTERNS["github"]]
        git = Git(repository, base, head, Conventions({"merge_commit_patterns": patterns}))
        got = [
            ({k: v for k, v in item.items() if k not in ("sha", "order")}, item["order"])
            for item in git.contributions("f.txt")
        ]
        assert got == [
            ({"pr": "4", "lines": 4}, 0),
            ({"email": "carol@x", "lines": 1}, 1),
            ({"pr": "3", "lines": 2}, 2),
            ({"pr": "2", "lines": 3}, 3),
            ({"pr": "1", "lines": 10}, 4),
        ], got


class IdentityProvider(Provider):
    def __init__(self, authors: dict[str, str | None]) -> None:
        self.authors = authors
        self.lookups = 0

    def fetch_pr(self, pr_id: str) -> dict:
        self.lookups += 1
        if pr_id not in self.authors:
            raise ProviderError(f"PR {pr_id} not found")
        return {"author": self.authors[pr_id]}

    def commit_identity(self, sha: str, email: str) -> str | None:
        return {"c1": "carol"}.get(sha)


def test_choose_assignee() -> None:
    provider = IdentityProvider({"1": "alice", "2": "bob", "3": "alice"})
    cache: dict = {}
    most = [
        {"pr": "1", "lines": 4, "order": 2},
        {"pr": "2", "lines": 7, "order": 1},
        {"pr": "3", "lines": 4, "order": 0},
    ]
    assert choose_assignee(provider, most, cache) == ("alice", "")
    assert provider.lookups == 3
    assert choose_assignee(provider, most, cache) == ("alice", "")
    assert provider.lookups == 3, "identities are looked up once per run"

    tie = [{"pr": "1", "lines": 5, "order": 1}, {"pr": "2", "lines": 5, "order": 0}]
    assert choose_assignee(provider, tie, {}) == ("bob", ""), "a tie goes to the newest"

    direct = [{"sha": "c1", "email": "carol@x", "lines": 1, "order": 0},
              {"pr": "404", "lines": 50, "order": 1}]
    assert choose_assignee(provider, direct, {}) == ("carol", "")

    who, reason = choose_assignee(provider, [{"pr": "404", "lines": 1, "order": 0}], {})
    assert who is None and "PR 404" in reason, reason
    assert choose_assignee(provider, [], {}) == (None, "no contributions")


class AssigningProvider(FakeProvider):
    can_assign = True

    def __init__(self, *args) -> None:
        super().__init__(*args)
        self.assigned: list[tuple[str, str]] = []
        self.checked: list[tuple[str, str]] = []

    def fetch_pr(self, pr_id: str) -> dict:
        if pr_id == self.pr["id"]:
            return super().fetch_pr(pr_id)
        return {"author": {"11": "alice@x", "12": "bob@x"}[pr_id]}

    def validate_child(self, parent_id: str, task: dict) -> None:
        super().validate_child(parent_id, task)
        self.checked.append((task["task_key"], task.get("assignee")))

    def validate_assignee(self, item_id: str, identity: str) -> None:
        self.checked.append((item_id, identity))

    def set_assignee(self, item_id: str, identity: str) -> str:
        self.assigned.append((item_id, identity))
        return "rev 9"

    def create_child(self, parent_id: str, task: dict) -> dict:
        self.assigned.append((task["task_key"], task.get("assignee")))
        return super().create_child(parent_id, task)


def assignment_evidence() -> dict:
    value = evidence()
    value["tasks"]["solution/models/Sales.SemanticModel"]["contributions"] = [
        {"pr": "11", "lines": 2, "order": 1}, {"pr": "12", "lines": 9, "order": 0}]
    value["tasks"]["solution/reports/Sales.Report"]["contributions"] = [
        {"pr": "11", "lines": 5, "order": 0}]
    return value


def test_assignment_plan() -> None:
    provider = AssigningProvider("1", "100", "RepoA")
    pair = build_pair_plan(
        provider, config("RepoA"), "1", "100", assignment_evidence(),
        descriptions(), repository_root(), False,
    )
    actions = {action["task_key"]: action for action in pair["actions"]}
    model = actions["solution/models/Sales.SemanticModel"]
    report = actions["solution/reports/Sales.Report"]
    assert model["operation"] == "create" and model["assignee"] == "bob@x"
    assert report["operation"] == "reuse" and report["assignee"] == "alice@x"
    assert ("1000", "alice@x") in provider.checked
    assert ("solution/models/Sales.SemanticModel", "bob@x") in provider.checked

    release = compose_release("rel-1", [pair])
    with tempfile.TemporaryDirectory() as directory:
        output_root = Path(directory)
        apply_release(
            release, output_root / "result.json",
            lambda _pair: (repository_root(), config("RepoA"), provider),
            lambda slug, plan, tasks: write_pair_artifact(slug, plan, tasks, output_root),
        )
    assert sorted(provider.assigned) == [
        ("1000", "alice@x"), ("solution/models/Sales.SemanticModel", "bob@x"),
    ], provider.assigned
    assert provider.children[-1]["id"] == "1001"

    owned = AssigningProvider("1", "100", "RepoA")
    owned.children[0]["assigned_to"] = "someone@x"
    pair = build_pair_plan(
        owned, config("RepoA"), "1", "100", assignment_evidence(),
        descriptions(), repository_root(), False,
    )
    report = next(a for a in pair["actions"] if a["operation"] == "reuse")
    assert report["assignee"] is None and report["assignee_note"] == "keep assignee"


class PublishProvider(Provider):
    can_assign = True

    def __init__(self) -> None:
        self.current = {"1": "", "2": "owner", "3": ""}
        self.assigned: list[tuple[str, str]] = []

    def fetch_assignees(self, ids: list[str]) -> dict[str, str]:
        return {i: self.current[i] for i in ids}

    def fetch_pr(self, pr_id: str) -> dict:
        return {"author": "alice"}

    def validate_assignee(self, item_id: str, identity: str) -> None:
        pass

    def set_assignee(self, item_id: str, identity: str) -> str:
        self.assigned.append((item_id, identity))
        return "ok"


def test_publish_assigns() -> None:
    contributions = [{"pr": "5", "lines": 3, "order": 0}]
    publish_evidence = {"tasks": {
        "1": {"contributions": contributions},
        "2": {"contributions": contributions},
        "3": {"contributions": []},
    }}
    provider = PublishProvider()
    assign_items(provider, ["1", "2", "3"], publish_evidence, apply=False)
    assert provider.assigned == [], "dry run writes nothing"
    assign_items(provider, ["1", "2", "3"], publish_evidence, apply=True)
    assert provider.assigned == [("1", "alice")], provider.assigned


def test_assignment_payloads() -> None:
    ado = AdoProvider("contoso", "Project")
    task = {"title": "T", "description": "D"}
    paths = [op["path"] for op in ado._child_patch("1", task)]
    assert "/fields/System.AssignedTo" not in paths
    patch = ado._child_patch("1", {**task, "assignee": "alice@x"})
    assert {"op": "add", "path": "/fields/System.AssignedTo", "value": "alice@x"} in patch

    calls: list[tuple[list[str], str | None]] = []

    def fake_run_json(args: list[str], *, stdin: str | None = None) -> dict:
        calls.append((args, stdin))
        return {"assignees": [{"login": "alice"}]}

    original = providers.run_json
    providers.run_json = fake_run_json
    try:
        github = GitHubProvider("acme", "data")
        assert github.set_assignee("42", "alice") == "assigned alice"
        assert github.fetch_assignees(["42"]) == {"42": "alice"}
    finally:
        providers.run_json = original
    args, stdin = calls[0]
    assert "/repos/acme/data/issues/42/assignees" in args and "POST" in args
    assert json.loads(stdin) == {"assignees": ["alice"]}


def test_asset_rule_discovery() -> None:
    with tempfile.TemporaryDirectory() as directory:
        repository = Path(directory)
        subprocess.run(["git", "init", "-q"], cwd=repository, check=True)
        for key, value in (
            ("user.email", "test@example.invalid"),
            ("user.name", "Release Test"),
            ("core.autocrlf", "false"),
        ):
            subprocess.run(["git", "config", key, value], cwd=repository, check=True)
        models = "data_solution/foo/transformation/models"
        write(repository, f"{models}/curated/sales/sales.sql", "select 1 as amount\n")
        write(repository, f"{models}/clean/orders/orders.sql", "select 1 as id\n")
        write(repository, f"{models}/clean/legacy/legacy.sql", "select 1 as id\n")
        write(repository, "data_solution/foo/source_configs/crm.yaml", "type: rest_api\n")
        write(repository, "data_solution/foo/adapters/crm.py", "VALUE = 1\n")
        write(repository, "data_solution/foo/config.yml", "database: foo\n")
        base = commit_all(repository, "test: base")

        write(repository, f"{models}/curated/sales/sales.sql", "select 2 as amount\n")
        (repository / f"{models}/clean/area").mkdir(parents=True)
        subprocess.run(
            ["git", "mv", f"{models}/clean/orders", f"{models}/clean/area/orders"],
            cwd=repository, check=True,
        )
        (repository / f"{models}/clean/legacy/legacy.sql").unlink()
        write(repository, "data_solution/foo/source_configs/crm.yaml", "type: sharepoint\n")
        write(repository, "data_solution/foo/adapters/crm.py", "VALUE = 2\n")
        write(repository, "data_solution/foo/config.yml", "database: bar\n")
        write(
            repository, "data_solution/foo/transformation/tests/assert_sales.sql",
            "select * from {{ ref('sales') }} where amount < 0\n",
        )
        write(
            repository, "data_solution/foo/transformation/tests/assert_join.sql",
            "select * from {{ ref('sales') }} join {{ ref('orders') }} on true\n",
        )
        head = commit_all(repository, "test: release")

        conventions = Conventions({**config("Repo"), "asset_rules": ASSET_RULES})
        git = Git(repository, base, head, conventions)
        assets = assign_assets(git, conventions, git.changed())
        files = {
            key: sorted(path for _, path, _ in asset["files"])
            for key, asset in assets.items()
        }
        assert sorted(files) == [
            "data_solution/foo/model/legacy",
            "data_solution/foo/model/orders",
            "data_solution/foo/model/sales",
            "data_solution/foo/source/crm",
        ], files
        assert assets["data_solution/foo/model/sales"]["title"] == "Model: foo/sales"
        assert files["data_solution/foo/model/sales"] == [
            f"{models}/curated/sales/sales.sql",
            "data_solution/foo/transformation/tests/assert_sales.sql",
        ]
        assert files["data_solution/foo/source/crm"] == [
            "data_solution/foo/adapters/crm.py",
            "data_solution/foo/source_configs/crm.yaml",
        ]
        (status, _, old), = assets["data_solution/foo/model/orders"]["files"]
        assert status.startswith("R") and old == f"{models}/clean/orders/orders.sql"
        assert assets["data_solution/foo/model/legacy"]["files"][0][0] == "D"

        claimed = {path for paths in files.values() for path in paths}
        leftover = sorted(
            path for _, path, _ in git.changed() if path not in claimed
        )
        assert leftover == [
            "data_solution/foo/config.yml",
            "data_solution/foo/transformation/tests/assert_join.sql",
        ], leftover

        titles = {key: asset["title"] for key, asset in assets.items()}
        mapping, problems = map_tasks(
            [{"id": "7", "title": "Model: foo/sales"}], set(assets), conventions, titles
        )
        assert mapping == {"7": "data_solution/foo/model/sales"} and not problems

        # End to end through main(): asset files leave the folder Task, and an
        # asset never borrows another solution's Task by its leaf name.
        subprocess.run(
            ["git", "remote", "add", "origin",
             "https://dev.azure.com/contoso/Project/_git/Repo"],
            cwd=repository, check=True,
        )
        write(repository, ".claude/release-notes.config.json",
              json.dumps({"asset_rules": ASSET_RULES}))
        script = Path(__file__).with_name("collect_evidence.py")

        def collect(tasks: list[dict]) -> subprocess.CompletedProcess:
            (repository / "tasks.json").write_text(json.dumps(tasks))
            return subprocess.run(
                [sys.executable, str(script), "--repo", str(repository),
                 "--base", base, "--head", head, "--config",
                 "--tasks", str(repository / "tasks.json"),
                 "--out", str(repository / "evidence.json")],
                capture_output=True, text=True,
            )

        run = collect([
            {"id": "1", "title": "Source: foo/crm", "type": "Task"},
            {"id": "2", "title": "foo", "type": "Task"},
        ])
        assert run.returncode == 0, run.stdout + run.stderr
        tasks = json.loads((repository / "evidence.json").read_text())["tasks"]
        assert tasks["1"]["folder"] == "data_solution/foo/source/crm"
        assert tasks["1"]["asset"] is True
        assert tasks["2"]["folder"] == "data_solution/foo"
        assert tasks["2"]["asset"] is False
        assert tasks["2"]["paths"] == leftover, tasks["2"]["paths"]

        run = collect([{"id": "3", "title": "Source: bar/crm", "type": "Task"}])
        assert run.returncode == 2, run.stdout + run.stderr
        assert "3 'Source: bar/crm' -> no match" in run.stdout, run.stdout


def test_asset_title_collision() -> None:
    conventions = Conventions({"asset_rules": [{
        "kind": "Model",
        "pattern": r"^(?P<root>[^/]+/dbt)/models/(?P<asset>[^/]+)\.sql$",
    }]})

    class Unused:
        pass

    changed = [
        ("M", "team_a/dbt/models/sales.sql", None),
        ("M", "team_b/dbt/models/sales.sql", None),
    ]
    try:
        assign_assets(Unused(), conventions, changed)
    except SystemExit as exc:
        assert "same title 'Model: dbt/sales'" in str(exc), str(exc)
    else:
        raise AssertionError("expected colliding asset titles to fail")


def test_asset_task_never_reuses_leaf_match() -> None:
    provider = FakeProvider("1", "100", "Repo")
    provider.children[0]["title"] = "Source: bar/crm"
    provider.children[0]["description"] = "<p>bar</p>"
    key = "data_solution/foo/source/crm"
    asset_evidence = {
        "base": "HEAD",
        "head": "HEAD",
        "unclaimed_folders": [],
        "tasks": {key: {"task_key": key, "folder": key,
                        "title": "Source: foo/crm", "asset": True}},
    }
    plan = build_pair_plan(
        provider, config("Repo"), "1", "100", asset_evidence,
        {key: "<p>foo</p>"}, repository_root(), True,
    )
    (action,) = plan["actions"]
    assert action["operation"] == "create", action


def test_asset_rule_validation() -> None:
    assert asset_rule_problems(None) == []
    assert asset_rule_problems(ASSET_RULES) == []
    problems = asset_rule_problems(
        [
            {"kind": "", "pattern": r"^(?P<root>a)/(?P<asset>b)$"},
            {"kind": "Model", "pattern": r"^(?P<asset>b)$"},
            {"kind": "Model", "pattern": "("},
            {"kind": "Model", "pattern": r"^(?P<root>a)$", "resolve": "unknown"},
        ]
    )
    assert len(problems) == 4, problems
    try:
        Conventions({"asset_rules": [{"kind": "Model", "pattern": "("}]})
    except SystemExit as exc:
        assert "invalid asset_rules" in str(exc)
    else:
        raise AssertionError("expected invalid asset_rules to fail")


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
    # Same first call the shipped scripts make: this file reports in prose that
    # is not ASCII, and CI runs it on consoles that are not UTF-8.
    configure_stdio()
    tests = [
        test_unique_titles,
        test_ado_child_payload,
        test_id_free_evidence_discovery,
        test_contributions,
        test_choose_assignee,
        test_assignment_plan,
        test_publish_assigns,
        test_assignment_payloads,
        test_asset_rule_discovery,
        test_asset_rule_validation,
        test_asset_title_collision,
        test_asset_task_never_reuses_leaf_match,
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
