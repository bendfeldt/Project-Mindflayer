#!/usr/bin/env python3
"""Create an unsent RFC-formatted draft from subject and HTML files.

The command is a dry run unless ``--write`` is supplied. Recipient headers are
intentionally omitted so the resulting draft cannot address anyone by default.

``--out`` writes a .eml file. ``--open`` (macOS) pops the draft up in Outlook
from a temporary .emltpl, the documented Outlook for Mac template format, and
deletes it.

Usage:
  make_email_draft.py <subject.txt> <body.html> --out <draft.eml> [--write]
  make_email_draft.py <subject.txt> <body.html> --open [--write]
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
import time
from email.message import EmailMessage
from email.policy import SMTP
from pathlib import Path
from typing import Sequence


# Outlook reads the file after `open` returns; keep it that long.
OPEN_GRACE_SECONDS = 5


class DraftError(ValueError):
    """Raised when draft input or output is unsafe or invalid."""


def read_subject(path: Path) -> str:
    """Read one non-empty UTF-8 subject line."""
    try:
        subject = path.read_text(encoding="utf-8").rstrip("\r\n")
    except OSError as exc:
        raise DraftError(f"cannot read subject file {path}: {exc}") from exc
    if not subject:
        raise DraftError("subject must not be empty")
    if "\r" in subject or "\n" in subject:
        raise DraftError("subject must contain exactly one line")
    return subject


def read_html_body(path: Path) -> str:
    """Read a non-empty UTF-8 HTML body."""
    try:
        body = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise DraftError(f"cannot read HTML body file {path}: {exc}") from exc
    if not body:
        raise DraftError("HTML body must not be empty")
    return body


def build_draft(subject: str, html_body: str) -> bytes:
    """Build a recipient-free HTML draft serialized with SMTP CRLF lines."""
    message = EmailMessage(policy=SMTP)
    message["X-Unsent"] = "1"
    # The policy encodes and folds it; a pre-folded header fails on 3.13+.
    message["Subject"] = subject
    message.set_content(
        html_body,
        subtype="html",
        charset="utf-8",
        cte="quoted-printable",
    )
    return message.as_bytes(policy=SMTP)


def write_draft(path: Path, content: bytes, *, overwrite: bool) -> None:
    """Write the draft without replacing an existing file by default."""
    mode = "wb" if overwrite else "xb"
    try:
        with path.open(mode) as draft_file:
            draft_file.write(content)
    except FileExistsError as exc:
        raise DraftError(
            f"output already exists: {path}; pass --overwrite with --write to replace it"
        ) from exc
    except OSError as exc:
        raise DraftError(f"cannot write draft {path}: {exc}") from exc


def open_in_outlook(content: bytes) -> None:
    """Pop the draft up in Outlook for Mac, then delete the temporary copy."""
    if sys.platform != "darwin":
        raise DraftError("--open is supported on macOS only; use --out")
    directory = Path(tempfile.mkdtemp(prefix="release-notes-"))
    try:
        path = directory / "release-notes-draft.emltpl"
        path.write_bytes(content)
        subprocess.run(
            ["open", "-a", "Microsoft Outlook", str(path)],
            check=True,
            capture_output=True,
        )
        time.sleep(OPEN_GRACE_SECONDS)
    except (OSError, subprocess.CalledProcessError) as exc:
        raise DraftError(f"cannot open the draft in Outlook: {exc}") from exc
    finally:
        shutil.rmtree(directory, ignore_errors=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("subject_file", type=Path)
    parser.add_argument("body_file", type=Path)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--out", type=Path, help="output .eml path")
    target.add_argument(
        "--open", action="store_true", help="pop the draft up in Outlook (macOS)"
    )
    parser.add_argument(
        "--write",
        action="store_true",
        help="create or open the draft (default: validate and print the plan only)",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="replace an existing output; valid only together with --write",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.overwrite and not args.write:
        parser.error("--overwrite requires --write")

    try:
        subject = read_subject(args.subject_file)
        content = build_draft(subject, read_html_body(args.body_file))
        target = "Outlook" if args.open else args.out
        if not args.write:
            print(
                f"dry run: would create a recipient-free draft in {target} "
                f"({len(content)} bytes)"
            )
            return 0
        if args.open:
            open_in_outlook(content)
        else:
            write_draft(args.out, content, overwrite=args.overwrite)
    except DraftError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    print(f"draft created in {target} (recipients: none)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
