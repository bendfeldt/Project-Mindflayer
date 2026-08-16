#!/usr/bin/env python3
"""Create an unsent RFC-formatted .eml draft from subject and HTML files.

The command is a dry run unless ``--write`` is supplied. Recipient headers are
intentionally omitted so the resulting draft cannot address anyone by default.

Usage:
  make_email_draft.py <subject.txt> <body.html> --out <draft.eml>
  make_email_draft.py <subject.txt> <body.html> --out <draft.eml> --write
"""
from __future__ import annotations

import argparse
import sys
from email.header import Header
from email.message import EmailMessage
from email.policy import SMTP
from pathlib import Path
from typing import Sequence


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
    message["Subject"] = Header(subject, charset="utf-8").encode()
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


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("subject_file", type=Path)
    parser.add_argument("body_file", type=Path)
    parser.add_argument("--out", type=Path, required=True, help="output .eml path")
    parser.add_argument(
        "--write",
        action="store_true",
        help="create the local draft (default: validate and print the plan only)",
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
        html_body = read_html_body(args.body_file)
        content = build_draft(subject, html_body)
        if not args.write:
            print(
                f"dry run: would write recipient-free draft to {args.out} "
                f"({len(content)} bytes)"
            )
            return 0
        write_draft(args.out, content, overwrite=args.overwrite)
    except DraftError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    print(f"draft written: {args.out} (recipients: none)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
