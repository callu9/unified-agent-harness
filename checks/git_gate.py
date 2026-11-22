#!/usr/bin/python3
"""Git-layer gates for enrolled repositories, run by githooks/_dispatch.

This is the agent-independent floor: it applies to any agent, with or without
hook support, and to commits typed by hand. Unenrolled repositories pass
untouched. `HARNESS_VERIFY_OVERRIDE` set on the same command skips the commit
check, as in the agent hook.

Usage: git_gate.py pre-commit
       git_gate.py commit-msg <message file>
       git_gate.py pre-push <remote> <url>   (ref lines on stdin, as Git supplies)
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))
import harness_verify as verify  # noqa: E402


def enrolled_status():
    try:
        info = verify.status(verify.repo_root(os.getcwd()))
    except BaseException:
        return None  # Fail open, like the agent hooks: never block what cannot be evaluated.
    if not info["configured"] or not info["gate_enabled"]:
        return None
    return info


def pre_commit():
    info = enrolled_status()
    if info is None or info["state"] == "FRESH" or os.environ.get("HARNESS_VERIFY_OVERRIDE", "").strip():
        return None
    return (f"agent-harness: commit blocked, verification receipt is {info['state']}. "
            "Run `harness verify run` first.")


# AI authorship notes that rules/40-git.md keeps out of commit messages. Both are matched only at
# the start of a line, so a body that describes the rule itself still commits.
# A trailer counts only in known tool/bot forms: a noreply/bot address at anthropic.com or openai.com, or a
# GitHub bot address whose name is an AI tool (`<id>+claude[bot]@users.noreply.github.com`, literal `[bot]`), or the
# Copilot account by address, whatever its display name (`<id>+Copilot@users.noreply.github.com`, which has no `[bot]`). A human's GitHub
# private email (`12345+cmartin@users.noreply.github.com`) or a human named Claude still commits.
AI_NAMES = "claude|codex|chatgpt|copilot|gemini|openai"
ATTRIBUTION = re.compile(r"^co-authored-by:.*<[^>]*(noreply|bot)[^>]*@(anthropic|openai)\.com>"
                         rf"|^co-authored-by:.*<(\d+\+)?([^>@]*[-_])?({AI_NAMES})([-_][^>@]*)?\[bot\]@users\.noreply\.github\.com>"
                         r"|^co-authored-by:.*<\d+\+copilot@users\.noreply\.github\.com>"
                         r"|^\W*generated (with|by)\b.*\b(claude|codex|chatgpt|copilot|gemini|ai)\b", re.I)


def enrolled_gate_on():
    """Cheap enrollment check for commit-msg: no worktree fingerprint, only the config file."""
    try:
        with open(os.path.join(verify.repo_root(os.getcwd()), verify.CONFIG_RELATIVE), encoding="utf-8") as fh:
            config = json.load(fh)
    except BaseException:
        return False  # Fail open, like enrolled_status.
    return isinstance(config, dict) and bool(config.get("gate", True))


def commit_msg(path):
    if not enrolled_gate_on():
        return None
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = [line.strip() for line in fh if not line.startswith("#")]
    except OSError:
        return None
    hits = [line for line in lines if ATTRIBUTION.search(line)]
    if not hits:
        return None
    return ("agent-harness: commit blocked, the message carries AI attribution: "
            f"{hits[0]!r}. Remove it and commit again.")


def is_ancestor(old, new):
    return subprocess.run(("git", "merge-base", "--is-ancestor", old, new),
                          capture_output=True).returncode == 0


def pre_push(lines):
    if enrolled_status() is None:
        return None
    for line in lines:
        parts = line.split()
        if len(parts) != 4:
            continue
        _local_ref, local_sha, remote_ref, remote_sha = parts
        if local_sha.strip("0") == "" or remote_sha.strip("0") == "":
            continue  # Branch deletion or a new remote branch is not a history rewrite.
        if not is_ancestor(remote_sha, local_sha):
            # Also reached when the remote tip was never fetched; a plain push would be rejected then too.
            return (f"agent-harness: non-fast-forward push to {remote_ref} blocked. "
                    "Fetch and integrate instead of rewriting published history.")
    return None


def main(argv):
    hook = argv[0] if argv else ""
    if hook == "pre-commit":
        problem = pre_commit()
    elif hook == "commit-msg" and len(argv) > 1:
        problem = commit_msg(argv[1])
    elif hook == "pre-push":
        problem = pre_push(sys.stdin.read().splitlines())
    else:
        return 0
    if problem:
        print(problem, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
