#!/usr/bin/env python3
"""Fail when a commit message in the given range is too long.

Commit history gets read by people scanning for "what changed". Rationale beyond a sentence or
two belongs in the PR or the docs. Limits follow outsmartly/actions' check-message-sizes.

    check-commit-messages.py <base>..<head>
"""
import re
import subprocess
import sys

SUMMARY_MAX_CHARS = 72  # first line
BODY_MAX_LINES = 6  # non-empty lines after the first
BODY_MAX_CHARS = 500  # total, after the first line
TRAILER = re.compile(r"^[A-Za-z-]+:\s")  # Co-authored-by: etc. are metadata, not prose
# GitHub's squash merge: "<PR title> (#12)" over the PR's commits, which the
# pull_request run already checked; the title and the joined bodies aren't commits we wrote.
SQUASHED_PR = re.compile(r" \(#\d+\)$")


def main(rev_range: str) -> int:
    shas = subprocess.run(["git", "rev-list", "--no-merges", rev_range], capture_output=True, text=True, check=True).stdout.split()
    problems = []
    for sha in shas:
        author, message = subprocess.run(["git", "log", "-1", "--format=%an%x00%B", sha], capture_output=True, text=True, check=True).stdout.split("\0", 1)
        if author.endswith("[bot]"):  # Dependabot and friends write their own messages
            continue
        summary, *rest = message.strip().split("\n")
        if SQUASHED_PR.search(summary):
            continue
        body = [line for line in rest if line.strip() and not TRAILER.match(line.strip())]
        label = f"{sha[:7]} {summary}"
        if len(summary) > SUMMARY_MAX_CHARS:
            problems.append(f"{label}: summary is {len(summary)} chars (max {SUMMARY_MAX_CHARS})")
        if len(body) > BODY_MAX_LINES:
            problems.append(f"{label}: body is {len(body)} lines (max {BODY_MAX_LINES})")
        if len("\n".join(body)) > BODY_MAX_CHARS:
            problems.append(f"{label}: body is {len(chr(10).join(body))} chars (max {BODY_MAX_CHARS})")
    print("\n".join(problems) or f"{len(shas)} commit message(s) OK")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
