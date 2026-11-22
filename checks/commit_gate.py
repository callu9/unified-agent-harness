#!/usr/bin/python3
"""Agent PreToolUse gate for literal Git publish commands.

Denies `git commit` while the worktree has no fresh PASS verification receipt,
and denies force-push and `--no-verify`. The gate is opt-in per repository: it
applies only where `.harness/harness.json` exists and does not set `gate: false`.
Read-only; it never mutates the repository and never logs prompts or diffs.

The receipt is produced by `harness verify run`, which executes the
configured commands itself, so it records real exit codes for this exact
worktree state. An override marker is an agent assertion of an explicit user
request, not independent proof of authorization.
"""
import json
import os
import re
import shlex
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

MARKER = "HARNESS_VERIFY_OVERRIDE"
DENY_COMMIT_FLAGS = {"--no-verify", "-n"}
FORCE_PUSH_FLAGS = {"--force", "-f"}


def verify_status(cwd):
    try:
        import harness_verify

        return harness_verify.status(harness_verify.repo_root(cwd))
    except BaseException:
        return None  # Fail open: never block a command the gate cannot evaluate.


def gate_problem(cwd):
    info = verify_status(cwd)
    if info is None or not info.get("configured") or not info.get("gate_enabled"):
        return None  # Not enrolled: behave exactly as before.
    state = info.get("state")
    if state == "FRESH":
        return None
    detail = {
        "MISSING": "no verification receipt exists for this worktree",
        "STALE": "the receipt was recorded for a different worktree state",
        "FAILED": "the last recorded verification result is FAIL",
    }.get(state, f"receipt state is {state}")
    return (f"Commit gate: {detail}. Run `harness verify run` in "
            f"{os.path.basename(info.get('repository') or cwd)} and report its actual "
            "result before committing. Only when the user explicitly authorized an "
            f"unverified commit, prefix that one Git command with {MARKER}=<their reason>; "
            "never invent an exception.")


def short_flag(flags, letter):
    """True when `letter` appears in a short-flag cluster, as in `-nm` or `-fu`."""
    return any(re.fullmatch(r"-[A-Za-z]*" + letter + r"[A-Za-z]*", f) for f in flags)


def operand_flags(args):
    flags = []
    for a in args:
        if a == "--":
            break
        if a.startswith("-"):
            flags.append(a)
    return flags


def inspect_git(args, cwd, override):
    repo = cwd
    while args and args[0].startswith("-"):
        opt = args.pop(0)
        if opt == "-C" and args:
            candidate = args.pop(0)
            repo = candidate if os.path.isabs(candidate) else os.path.join(cwd, candidate)
        elif opt in ("-c", "--git-dir", "--work-tree", "--namespace", "--config-env"):
            if args:
                args.pop(0)
        elif opt == "--":
            break
    if not args or override:
        # An override marker asserts an explicit user instruction for this one command.
        return None
    sub, rest = args[0], args[1:]
    flags = operand_flags(rest)
    if sub == "push" and (any(f.startswith("--force") for f in flags)
                          or short_flag(flags, "f")):
        return ("Commit gate: force-push is not allowed. Published history must not be "
                "rewritten. Push the new commits, or ask the user how to proceed. Only "
                f"when the user explicitly authorized rewriting it, prefix that one Git "
                f"command with {MARKER}=<their reason>; never invent an exception.")
    if sub != "commit":
        return None
    if "--no-verify" in flags or short_flag(flags, "n"):
        return ("Commit gate: `git commit --no-verify` is not allowed; it skips the "
                "repository's own hooks. Fix what the hook reports instead.")
    return gate_problem(repo)


def inspect_argv(argv, cwd, depth=0):
    if depth > 4 or not argv:
        return None
    args = list(argv)
    override = None
    if os.path.basename(args[0]) == "env":
        args.pop(0)
    while args and re.match(r"^[A-Za-z_][A-Za-z_0-9]*=", args[0]):
        key, value = args.pop(0).split("=", 1)
        if key == MARKER and value.strip():
            override = value
    while args and args[0] in ("command", "exec", "builtin"):
        args.pop(0)
        if args[:1] == ["--"]:
            args.pop(0)
    if not args:
        return None
    exe = os.path.basename(args.pop(0))
    if exe in ("sh", "bash", "zsh"):
        for i, a in enumerate(args):
            if a.startswith("-") and "c" in a and i + 1 < len(args):
                return inspect_shell(args[i + 1], cwd, depth + 1)
        return None
    if exe != "git":
        return None
    return inspect_git(args, cwd, override)


def inspect_shell(command, cwd, depth=0):
    try:
        lex = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
        lex.whitespace = " \t\r"
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        return None  # Not a shell parser; never block unrelated tools on a parse error.
    current = []
    for token in tokens + [";"]:
        if token and all(c in ";&|()\n" for c in token):
            problem = inspect_argv(current, cwd, depth)
            if problem:
                return problem
            current = []
        else:
            current.append(token)
    return None


def inspect_payload(data):
    if data.get("hook_event_name") != "PreToolUse":
        return None
    cwd = data.get("cwd") or os.getcwd()
    tool = str(data.get("tool_name", "")).split(".")[-1]
    arg = data.get("tool_input", {})
    if isinstance(arg, str):
        try:
            arg = json.loads(arg)
        except ValueError:
            return None
    if not isinstance(arg, dict):
        return None
    if tool not in ("exec_command", "shell", "shell_command", "Bash"):
        return None
    workdir = arg.get("workdir") or arg.get("cwd")
    if isinstance(workdir, str) and workdir:
        cwd = workdir if os.path.isabs(workdir) else os.path.join(cwd, workdir)
    command = arg.get("cmd", arg.get("command"))
    if isinstance(command, list):
        return inspect_argv(command, cwd)
    if isinstance(command, str):
        return inspect_shell(command, cwd)
    return None


def main():
    try:
        problem = inspect_payload(json.load(sys.stdin))
    except (ValueError, TypeError):
        return
    if problem:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": problem}}, ensure_ascii=False))


if __name__ == "__main__":
    main()
