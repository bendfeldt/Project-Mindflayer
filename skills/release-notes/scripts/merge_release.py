#!/usr/bin/env python3
"""Combine per-pair and legacy per-repo artifacts into one test email skeleton.

Applied release plans write one artifact per PR/User Story pair. Legacy
`publish_descriptions.py --run <slug>` artifacts remain supported. This script
combines both shapes into one email with direct Task, PR, and User Story links.

It assembles structure, counts and links — never prose. Every place that needs
judgement is left as a [PLACEHOLDER] for the agent to fill, which is the same
division of labour as the per-task descriptions.

Usage:
    merge_release.py --release rel_1                       # list what it found
    merge_release.py --release rel_1 --format html --out body.html
    merge_release.py --release rel_1 --format md --lang en

Exit codes:
    0  artifacts found and rendered
    2  no artifacts for that release slug
"""
from __future__ import annotations

import argparse
import html
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import RUNS_DIR  # noqa: E402

STRINGS = {
    "da": {
        "subject": "Test af release {release} — frist [FRIST]",
        "opening": ("Release <b>{release}</b> omfatter {n_tasks} opgaver fordelt på "
                    "{n_repos} repositories. [OPSUMMERING: 2-3 linjer om de "
                    "gennemgående temaer i releasen]"),
        "how_to": "Sådan tester du",
        "how_to_steps": [
            "Find din opgave i listen nedenfor og åbn linket.",
            "Test i [MILJØ] og følg testpunkterne i opgavens beskrivelse.",
            "Sæt opgaven til Closed når den er godkendt.",
            "Ved fejl: kommentér på opgaven og sæt den til [STATUS].",
            "Frist: [FRIST].",
        ],
        "changed": "Det er ændret",
        "attention": "Vær særligt opmærksom på",
        "attention_body": "[2-4 reelle risikopunkter: flyttede items, "
                          "ændringer der legitimt ændrer tallene, opgaver der "
                          "næsten ikke kræver test]",
        "no_task": "Ændringer uden selvstændig opgave",
        "links": "Links",
        "signoff": "Spørgsmål? Kontakt [KONTAKT].\n[AFSENDER]",
        "tasks_word": "opgaver",
        "context": "[KONTEKST: 1-3 linjer om denne gruppe]",
    },
    "en": {
        "subject": "Test of release {release} — deadline [DEADLINE]",
        "opening": ("Release <b>{release}</b> covers {n_tasks} tasks across "
                    "{n_repos} repositories. [SUMMARY: 2-3 lines on the "
                    "cross-cutting themes of this release]"),
        "how_to": "How to test",
        "how_to_steps": [
            "Find your task in the list below and open the link.",
            "Test in [ENVIRONMENT] and follow the test points in the task description.",
            "Set the task to Closed once approved.",
            "On failure: comment on the task and set it to [STATUS].",
            "Deadline: [DEADLINE].",
        ],
        "changed": "What changed",
        "attention": "Pay particular attention to",
        "attention_body": "[2-4 genuine risk points: moved items, changes that "
                          "legitimately move the numbers, tasks that need almost "
                          "no testing]",
        "no_task": "Changes with no task of their own",
        "links": "Links",
        "signoff": "Questions? Contact [CONTACT].\n[SENDER]",
        "tasks_word": "tasks",
        "context": "[CONTEXT: 1-3 lines about this group]",
    },
}

OUTLOOK_WRAPPER = ('<div style="font-family:Calibri,Arial,sans-serif;'
                   'font-size:11pt;color:#201F1E;">\n{body}\n</div>')


def load_artifacts(slug: str) -> list[dict]:
    run_dir = RUNS_DIR / slug
    if not run_dir.is_dir():
        raise SystemExit(2)
    artifacts = []
    for path in sorted(run_dir.glob("*.json")):
        try:
            artifacts.append(json.loads(path.read_text()))
        except json.JSONDecodeError as exc:
            print(f"warning: skipping malformed {path}: {exc}", file=sys.stderr)
    return artifacts


def artifact_label(artifact: dict) -> str:
    pull_request = artifact.get("pull_request") or {}
    parent = artifact.get("parent") or {}
    if pull_request and parent:
        return (
            f"{artifact['repo']} — PR {pull_request['id']} → "
            f"{parent.get('type') or 'User Story'} {parent['id']}"
        )
    return artifact["repo"]


def artifact_links(artifact: dict) -> list[tuple[str, str]]:
    links: list[tuple[str, str]] = []
    pull_request = artifact.get("pull_request") or {}
    parent = artifact.get("parent") or {}
    if pull_request.get("url"):
        links.append((f"{artifact['repo']} PR {pull_request['id']}", pull_request["url"]))
    if parent.get("url"):
        links.append(
            (
                f"{artifact['repo']} {parent.get('type') or 'User Story'} "
                f"{parent['id']}",
                parent["url"],
            )
        )
    return links


def repository_count(artifacts: list[dict]) -> int:
    return len({(
        artifact.get("provider"),
        artifact.get("org"),
        artifact.get("project"),
        artifact["repo"],
    ) for artifact in artifacts})


def render_html(slug: str, artifacts: list[dict], s: dict) -> str:
    n_tasks = sum(len(a["tasks"]) for a in artifacts)
    parts = [f"<p>{s['opening'].format(release=html.escape(slug), n_tasks=n_tasks, n_repos=repository_count(artifacts))}</p>"]

    parts.append(f"<p><b>{s['how_to']}</b></p><ol>")
    parts += [f"<li>{html.escape(step)}</li>" for step in s["how_to_steps"]]
    parts.append("</ol>")

    parts.append(f"<p><b>{s['changed']}</b></p>")
    for art in artifacts:
        parts.append(f"<p><i>{html.escape(artifact_label(art))}</i> — "
                     f"{len(art['tasks'])} {s['tasks_word']}. {s['context']}</p><ul>")
        for task in art["tasks"]:
            title = html.escape(task.get("title") or f"#{task['id']}")
            parts.append(f'<li><a href="{html.escape(task["url"])}">'
                         f'{html.escape(task["id"])} — {title}</a></li>')
        parts.append("</ul>")

    unclaimed = [(artifact_label(a), f) for a in artifacts
                 for f in a.get("unclaimed_folders", [])]
    if unclaimed:
        parts.append(f"<p><b>{s['no_task']}</b></p><ul>")
        parts += [f"<li>{html.escape(repo)}: {html.escape(folder)}</li>"
                  for repo, folder in unclaimed]
        parts.append("</ul>")

    parts.append(f"<p><b>{s['attention']}</b></p><p>{s['attention_body']}</p>")
    parts.append(f"<p><b>{s['links']}</b></p><ul>")
    for artifact in artifacts:
        links = artifact_links(artifact)
        if links:
            parts += [
                f'<li><a href="{html.escape(url)}">{html.escape(label)}</a></li>'
                for label, url in links
            ]
        else:
            parts.append(
                f"<li>{html.escape(artifact['repo'])}: "
                f"{html.escape(artifact.get('head') or '[PR]')}</li>"
            )
    parts.append("</ul>")
    parts.append("<p>" + s["signoff"].replace("\n", "<br>") + "</p>")
    return OUTLOOK_WRAPPER.format(body="\n".join(parts))


def render_md(slug: str, artifacts: list[dict], s: dict) -> str:
    n_tasks = sum(len(a["tasks"]) for a in artifacts)
    strip = lambda t: t.replace("<b>", "**").replace("</b>", "**")  # noqa: E731
    out = [strip(s["opening"].format(
        release=slug, n_tasks=n_tasks, n_repos=repository_count(artifacts)
    )), ""]

    out += [f"## {s['how_to']}", ""]
    out += [f"{i}. {step}" for i, step in enumerate(s["how_to_steps"], 1)]
    out += ["", f"## {s['changed']}", ""]
    for art in artifacts:
        out += [f"### {artifact_label(art)} — {len(art['tasks'])} {s['tasks_word']}",
                "", s["context"], ""]
        out += [f"- [{t['id']} — {t.get('title') or t['id']}]({t['url']})"
                for t in art["tasks"]]
        out.append("")

    unclaimed = [(artifact_label(a), f) for a in artifacts
                 for f in a.get("unclaimed_folders", [])]
    if unclaimed:
        out += [f"## {s['no_task']}", ""]
        out += [f"- {repo}: {folder}" for repo, folder in unclaimed]
        out.append("")

    out += [f"## {s['attention']}", "", s["attention_body"], ""]
    out += [f"## {s['links']}", ""]
    for artifact in artifacts:
        links = artifact_links(artifact)
        if links:
            out += [f"- [{label}]({url})" for label, url in links]
        else:
            out.append(f"- {artifact['repo']}: {artifact.get('head') or '[PR]'}")
    out += ["", s["signoff"]]
    return "\n".join(out)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--release", required=True, help="release slug used with --run")
    ap.add_argument("--format", choices=["html", "md", "list"], default="list")
    ap.add_argument("--lang", choices=["da", "en"], default=None,
                    help="default: the language recorded in the artifacts")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--subject-out", type=Path, default=None)
    args = ap.parse_args()

    try:
        artifacts = load_artifacts(args.release)
    except SystemExit:
        print(f"no run artifacts under {RUNS_DIR / args.release}", file=sys.stderr)
        sys.exit(2)
    if not artifacts:
        print(f"no run artifacts under {RUNS_DIR / args.release}", file=sys.stderr)
        sys.exit(2)

    languages = {a.get("language", "en") for a in artifacts}
    if args.lang is None and len(languages) > 1:
        print(f"artifacts disagree on language ({sorted(languages)}) — pass --lang",
              file=sys.stderr)
        sys.exit(2)
    lang = args.lang or languages.pop()
    s = STRINGS[lang]

    n_tasks = sum(len(a["tasks"]) for a in artifacts)
    if args.format == "list":
        print(f"release {args.release}: {repository_count(artifacts)} repos, "
              f"{len(artifacts)} PR/User Story pairs, {n_tasks} tasks, lang {lang}")
        for art in artifacts:
            print(f"  {artifact_label(art):48} {len(art['tasks']):3} tasks  "
                  f"{'applied' if art.get('applied') else 'dry run'}")
        return

    body = render_html(args.release, artifacts, s) if args.format == "html" \
        else render_md(args.release, artifacts, s)
    subject = s["subject"].format(release=args.release)

    if args.out:
        args.out.write_text(body)
        print(f"body written to {args.out} ({n_tasks} task links)", file=sys.stderr)
    else:
        print(body)
    if args.subject_out:
        args.subject_out.write_text(subject)
        print(f"subject written to {args.subject_out}", file=sys.stderr)
    else:
        print(f"\nsubject: {subject}", file=sys.stderr)


if __name__ == "__main__":
    main()
