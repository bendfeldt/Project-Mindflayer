from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILL_ROOT = ROOT / "skills" / "engineering-auditor"
INVENTORY_SCRIPT = SKILL_ROOT / "scripts" / "repository_inventory.py"
VALIDATOR_SCRIPT = SKILL_ROOT / "scripts" / "validate_audit_report.py"


def write_file(root: Path, relative_path: str, content: str = "") -> Path:
    path = root / relative_path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


def valid_report() -> str:
    return """# Engineering Audit Report

## Executive Assessment

The repository has one material maintainability finding.

## Repository and Technology Overview

Python application with unit tests.

## Engineering Scorecard

Software Engineering: 7/10, supported by AUD-001.

## Prioritized Findings

### AUD-001 — Duplicate validation behavior

**Domains:** Software Engineering, Maintainability and Modularity
**Category:** Reuse and maintainability
**Severity:** Medium
**Confidence:** High
**Priority:** P2
**Location:** `src/first.py:10`; `src/second.py:14`
**Evidence:** Both functions contain the same input normalization and validation sequence.
**Problem:** Equivalent validation behavior is maintained in two separate modules.
**Why it matters:** Corrections must be repeated and the two implementations can diverge.
**Recommendation:** Extract one focused validation function and call it from both existing modules.
**Suggested design:** Add a validation module with one explicit function and no additional wrapper layer.
**Expected benefit:** One tested implementation reduces divergence and duplicated maintenance.
**Implementation effort:** Small

## Remediation Roadmap

Near term: remediate AUD-001.

## Architecture and Modularity Recommendations

No broader structural change is warranted beyond AUD-001.
"""


class RepositoryInventoryTests(unittest.TestCase):
    def run_inventory(self, root: Path, *files: str) -> subprocess.CompletedProcess[str]:
        command = [sys.executable, str(INVENTORY_SCRIPT), "--root", str(root)]
        for file_name in files:
            command.extend(["--file", file_name])
        return subprocess.run(command, check=False, capture_output=True, text=True)

    def test_mixed_repository_detection(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            write_file(root, "src/main.py", "print('safe')\n")
            write_file(root, "src/client.generated.py")
            write_file(root, "models/orders.sql", "select 1\n")
            write_file(root, "tests/test_main.py", "def test_ok(): pass\n")
            write_file(root, "dbt_project.yml")
            write_file(root, "main.tf")
            write_file(root, "Dockerfile")
            write_file(root, ".github/workflows/ci.yml")
            write_file(root, "pyproject.toml")
            write_file(root, "uv.lock")
            write_file(root, "migrations/001.sql")

            result = self.run_inventory(root)

            self.assertEqual(result.returncode, 0, result.stderr)
            inventory = json.loads(result.stdout)
            self.assertEqual(inventory["languages"], ["hcl", "python", "sql"])
            self.assertEqual(inventory["frameworks"], ["dbt"])
            self.assertEqual(inventory["infrastructure"], ["docker", "terraform"])
            self.assertEqual(inventory["ci"], ["github-actions"])
            self.assertEqual(inventory["dependency_managers"], ["uv"])
            self.assertEqual(
                inventory["dependency_manifests"], ["pyproject.toml", "uv.lock"]
            )
            self.assertTrue(inventory["tests"])
            self.assertEqual(inventory["source_directories"], ["models", "src"])
            self.assertEqual(inventory["test_directories"], ["tests"])
            self.assertEqual(inventory["migration_directories"], ["migrations"])
            self.assertEqual(
                inventory["likely_generated_files"], ["src/client.generated.py"]
            )

    def test_unrecognized_repository_is_tolerated(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            write_file(root, "notes.txt", "plain text\n")

            result = self.run_inventory(root)

            self.assertEqual(result.returncode, 0, result.stderr)
            inventory = json.loads(result.stdout)
            self.assertEqual(inventory["files_scanned"], 1)
            self.assertEqual(inventory["languages"], [])
            self.assertEqual(inventory["frameworks"], [])
            self.assertFalse(inventory["tests"])

    def test_nested_source_and_sql_are_detected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            write_file(root, "services/orders/src/handler.py")
            write_file(root, "warehouse/staging/orders.sql")

            result = self.run_inventory(root)

            self.assertEqual(result.returncode, 0, result.stderr)
            inventory = json.loads(result.stdout)
            self.assertEqual(inventory["languages"], ["python", "sql"])
            self.assertEqual(inventory["source_directories"], ["services/orders/src"])

    def test_scoped_files_are_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            write_file(root, "src/a.py")
            write_file(root, "sql/b.sql")
            write_file(root, "main.tf")

            first = self.run_inventory(root, "sql/b.sql", "src/a.py")
            second = self.run_inventory(root, "src/a.py", "sql/b.sql")

            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(first.stdout, second.stdout)
            inventory = json.loads(first.stdout)
            self.assertEqual(inventory["scope"], "files")
            self.assertEqual(inventory["files_scanned"], 2)
            self.assertEqual(inventory["languages"], ["python", "sql"])

    def test_file_outside_root_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            base = Path(temporary_directory)
            root = base / "repository"
            root.mkdir()
            outside = write_file(base, "outside.py")

            result = self.run_inventory(root, str(outside))

            self.assertEqual(result.returncode, 2)
            self.assertIn("outside inventory root", result.stderr)

    def test_generated_directories_are_not_scanned(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            write_file(root, "src/main.py")
            write_file(root, "node_modules/package/index.js")
            write_file(root, ".git/config")

            result = self.run_inventory(root)

            self.assertEqual(result.returncode, 0, result.stderr)
            inventory = json.loads(result.stdout)
            self.assertEqual(inventory["files_scanned"], 1)
            self.assertEqual(
                inventory["likely_generated_directories"], [".git", "node_modules"]
            )


class AuditReportValidatorTests(unittest.TestCase):
    def run_validator(self, report: str) -> subprocess.CompletedProcess[str]:
        with tempfile.TemporaryDirectory() as temporary_directory:
            report_path = write_file(Path(temporary_directory), "audit.md", report)
            return subprocess.run(
                [sys.executable, str(VALIDATOR_SCRIPT), str(report_path)],
                check=False,
                capture_output=True,
                text=True,
            )

    def test_valid_report(self) -> None:
        result = self.run_validator(valid_report())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1 material finding", result.stdout)

    def test_valid_no_findings_report(self) -> None:
        report = """# Engineering Audit Report

## Executive Assessment
No material concerns were identified in the reviewed scope.
## Repository and Technology Overview
Small Python library.
## Engineering Scorecard
Software Engineering: 9/10.
## Prioritized Findings
No material findings identified.
## Remediation Roadmap
No remediation is required from this audit.
## Architecture and Modularity Recommendations
No structural change is warranted.
"""
        result = self.run_validator(report)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0 material finding", result.stdout)

    def test_empty_report_is_rejected(self) -> None:
        result = self.run_validator("")
        self.assertEqual(result.returncode, 1)
        self.assertIn("report is empty", result.stderr)

    def test_missing_evidence_is_rejected(self) -> None:
        report = valid_report().replace(
            "**Evidence:** Both functions contain the same input normalization and validation sequence.\n",
            "",
        )
        result = self.run_validator(report)
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing field: Evidence", result.stderr)

    def test_missing_recommendation_is_rejected(self) -> None:
        report = valid_report().replace(
            "**Recommendation:** Extract one focused validation function and call it from both existing modules.\n",
            "",
        )
        result = self.run_validator(report)
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing field: Recommendation", result.stderr)

    def test_missing_severity_is_rejected(self) -> None:
        report = valid_report().replace("**Severity:** Medium\n", "")
        result = self.run_validator(report)
        self.assertEqual(result.returncode, 1)
        self.assertIn("missing field: Severity", result.stderr)

    def test_incomplete_finding_is_rejected(self) -> None:
        report = valid_report().replace(
            "**Expected benefit:** One tested implementation reduces divergence and duplicated maintenance.\n",
            "**Expected benefit:** Better.\n",
        )
        result = self.run_validator(report)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Expected benefit is too short", result.stderr)

    def test_duplicate_finding_identifier_is_rejected(self) -> None:
        finding_start = valid_report().index("### AUD-001")
        finding_end = valid_report().index("## Remediation Roadmap")
        finding = valid_report()[finding_start:finding_end]
        report = valid_report().replace("## Remediation Roadmap", finding + "## Remediation Roadmap")
        result = self.run_validator(report)
        self.assertEqual(result.returncode, 1)
        self.assertIn("duplicate finding identifier", result.stderr)

    def test_vague_finding_evidence_is_rejected(self) -> None:
        report = valid_report().replace(
            "Both functions contain the same input normalization and validation sequence.",
            "This function could be improved.",
        )
        result = self.run_validator(report)
        self.assertEqual(result.returncode, 1)
        self.assertIn("vague value in field: Evidence", result.stderr)


if __name__ == "__main__":
    unittest.main()
