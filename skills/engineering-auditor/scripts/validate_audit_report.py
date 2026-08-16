#!/usr/bin/env python3
"""Validate the structure and minimum evidence quality of an audit report."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path
from typing import Sequence


REQUIRED_SECTIONS = (
    "Executive Assessment",
    "Repository Technology Overview",
    "Engineering Scorecard",
    "Prioritized Findings",
    "Remediation Roadmap",
    "Architecture and Modularity Recommendations",
)

REQUIRED_FIELDS = (
    "Domains",
    "Category",
    "Severity",
    "Confidence",
    "Priority",
    "Location",
    "Evidence",
    "Problem",
    "Why it matters",
    "Recommendation",
    "Suggested design",
    "Expected benefit",
    "Implementation effort",
)

ALLOWED_VALUES = {
    "Severity": frozenset({"Critical", "High", "Medium", "Low", "Informational"}),
    "Confidence": frozenset({"High", "Medium", "Low"}),
    "Priority": frozenset({"P0", "P1", "P2", "P3", "P4"}),
    "Implementation effort": frozenset({"Small", "Medium", "Large"}),
}

MINIMUM_LENGTHS = {
    "Location": 3,
    "Evidence": 20,
    "Problem": 15,
    "Why it matters": 15,
    "Recommendation": 20,
    "Suggested design": 15,
    "Expected benefit": 15,
}

FINDING_PATTERN = re.compile(
    r"^###\s+(AUD-\d{3})\s+(?:—|-)\s+(.+?)\s*$", re.MULTILINE
)
PLACEHOLDER_PATTERN = re.compile(r"\b(?:TODO|TBD|PLACEHOLDER)\b", re.IGNORECASE)
VAGUE_FINDING_PATTERN = re.compile(
    r"^(?:(?:this|the)\s+(?:function|code|query|pipeline|implementation)\s+"
    r"could\s+(?:be\s+)?improved|optimi[sz]e\s+(?:this|the\s+)?"
    r"(?:code|query|pipeline))\.?$",
    re.IGNORECASE,
)
NO_FINDINGS_TEXT = "No material findings identified."


def extract_field(block: str, field: str) -> str | None:
    """Extract a same-line or multi-line bold Markdown field."""
    pattern = re.compile(
        rf"^\*\*{re.escape(field)}:\*\*\s*(.*?)(?=^\*\*[^\n]+:\*\*|^##\s|\Z)",
        re.MULTILINE | re.DOTALL,
    )
    match = pattern.search(block)
    if not match:
        return None
    return " ".join(line.strip(" -\t") for line in match.group(1).splitlines()).strip()


def finding_blocks(report: str) -> list[tuple[str, str]]:
    """Split a report into finding identifiers and blocks."""
    matches = list(FINDING_PATTERN.finditer(report))
    blocks: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(report)
        blocks.append((match.group(1), report[match.start() : end]))
    return blocks


def section_content(report: str, section: str) -> str:
    """Return content beneath an H2 section, excluding the next H2."""
    match = re.search(
        rf"^##\s+{re.escape(section)}\s*$\n?(.*?)(?=^##\s|\Z)",
        report,
        re.MULTILINE | re.DOTALL,
    )
    return match.group(1) if match else ""


def validate_report(report: str) -> list[str]:
    """Return deterministic validation errors for an audit report."""
    errors: list[str] = []
    if not report.strip():
        return ["report is empty"]

    for section in REQUIRED_SECTIONS:
        if not re.search(rf"^##\s+{re.escape(section)}\s*$", report, re.MULTILINE):
            errors.append(f"missing section: {section}")

    prioritized_findings = section_content(report, "Prioritized Findings")
    blocks = finding_blocks(prioritized_findings)
    if not blocks:
        if NO_FINDINGS_TEXT not in prioritized_findings:
            errors.append(
                f"report has no findings; use exact statement: {NO_FINDINGS_TEXT}"
            )
        return errors

    if NO_FINDINGS_TEXT in prioritized_findings:
        errors.append("report cannot contain findings and the no-findings statement")

    seen_identifiers: set[str] = set()
    for identifier, block in blocks:
        if identifier in seen_identifiers:
            errors.append(f"duplicate finding identifier: {identifier}")
        seen_identifiers.add(identifier)

        values: dict[str, str] = {}
        for field in REQUIRED_FIELDS:
            value = extract_field(block, field)
            if value is None:
                errors.append(f"{identifier}: missing field: {field}")
                continue
            if not value:
                errors.append(f"{identifier}: empty field: {field}")
                continue
            if PLACEHOLDER_PATTERN.search(value):
                errors.append(f"{identifier}: placeholder value in field: {field}")
            if VAGUE_FINDING_PATTERN.fullmatch(value):
                errors.append(f"{identifier}: vague value in field: {field}")
            values[field] = value

        for field, allowed in ALLOWED_VALUES.items():
            value = values.get(field)
            if value is not None and value not in allowed:
                errors.append(
                    f"{identifier}: invalid {field}: {value}; expected one of: "
                    + ", ".join(sorted(allowed))
                )

        for field, minimum_length in MINIMUM_LENGTHS.items():
            value = values.get(field)
            if value is not None and len(value) < minimum_length:
                errors.append(
                    f"{identifier}: {field} is too short to be actionable "
                    f"(minimum {minimum_length} characters)"
                )

    return errors


def parse_args(arguments: Sequence[str]) -> argparse.Namespace:
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(description="Validate an engineering audit report.")
    parser.add_argument("report", type=Path, help="Markdown audit report")
    return parser.parse_args(arguments)


def main(arguments: Sequence[str] | None = None) -> int:
    """Run the report validator CLI."""
    parsed = parse_args(arguments if arguments is not None else sys.argv[1:])
    try:
        report = parsed.report.read_text(encoding="utf-8")
    except OSError as error:
        print(f"error: cannot read report: {error}", file=sys.stderr)
        return 2

    errors = validate_report(report)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        return 1

    finding_count = len(finding_blocks(report))
    print(f"valid audit report: {finding_count} material finding(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
