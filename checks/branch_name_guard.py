#!/usr/bin/python3
"""Agent PreToolUse guard for literal Git branch creation commands.

No repository mutation, persistent state, command execution or transcript logging.
The exact-name marker is an agent assertion of an explicit user request, not
independent proof of authorization. See rules/40-git.md.
"""
import json
import os
import re
import shlex
import sys

FORBIDDEN = ("codex/", "claude/", "agent/")  # automatic agent-tool prefixes
MARKER = "HARNESS_USER_BRANCH_NAME"
SEPARATORS = {";", "&&", "||", "|", "&", "(", ")", "\n"}


def valid_name(name):
    # Git check-ref-format --branch rules, without executing the supplied command.
    return bool(name and name != "@" and not name.startswith(("-", "/"))
                and not name.endswith(("/", ".")) and ".." not in name
                and "@{" not in name and "//" not in name
                and not re.search(r"[\x00-\x20\x7f~^:?*\[\\]", name)
                and all(not p.startswith(".") and not p.endswith(".lock")
                        for p in name.split("/")))


def check(name, explicit=None):
    if not valid_name(name):
        return "Branch guard: use a complete literal, valid Git branch name before creation."
    if name.startswith(FORBIDDEN) and explicit != name:
        return (f"Branch guard: automatic tool prefix rejected: {name!r}. "
                "Use the user's complete name, otherwise the project rule, otherwise "
                "<feat|fix|refactor|docs|test|chore|ci|build>/<kebab-case>. "
                f"Only for a complete name explicitly requested by the user, prefix this "
                f"one Git command with {MARKER}=<that-exact-name>; never invent an exception.")
    return None


def flag_value(args, shorts, longs):
    for i, a in enumerate(args):
        if a == "--":
            break
        if a in shorts or a in longs:
            return args[i + 1] if i + 1 < len(args) else ""
        for flag in longs:
            if a.startswith(flag + "="):
                return a[len(flag) + 1:]
        for flag in shorts:
            if a.startswith(flag) and len(a) > len(flag):
                return a[len(flag):]
    return None


def created_names(args):
    """Names introduced by branch/switch/checkout/worktree, not lookup targets."""
    if not args:
        return []
    cmd, rest = args[0], args[1:]
    if cmd in ("switch", "checkout"):
        n = flag_value(rest, ("-c", "-C") if cmd == "switch" else ("-b", "-B"),
                       ("--create", "--force-create", "--orphan") if cmd == "switch" else ("--orphan",))
        return [] if n is None else [n]
    if cmd == "worktree" and rest[:1] == ["add"]:
        n = flag_value(rest[1:], ("-b", "-B"), ())
        return [] if n is None else [n]
    if cmd != "branch":
        return []
    # Read-only, deletion and branch configuration do not introduce branch names.
    read = {"--list", "--show-current", "--contains", "--no-contains", "--merged",
            "--no-merged", "--points-at", "--format", "--sort", "--column", "--color",
            "--delete", "--edit-description", "--set-upstream-to", "--unset-upstream",
            "--all", "--remotes", "--verbose"}
    for a in rest:
        if a == "--":
            break
        if a.split("=", 1)[0] in read or re.fullmatch(r"-[aAvvrdDu]+", a):
            return []
    rename = any(a in ("-m", "-M", "-c", "-C", "--move", "--copy") for a in rest)
    operands = []
    after_dash = False
    for a in rest:
        if a == "--":
            after_dash = True
        elif after_dash or not a.startswith("-"):
            operands.append(a)
    if not operands:
        return []
    return [operands[-1] if rename else operands[0]]


def inspect_argv(argv, depth=0):
    if depth > 4 or not argv:
        return None
    args = list(argv)
    explicit = None
    # Only same-command assignments qualify; ambient environment never does.
    if args and os.path.basename(args[0]) == "env":
        args.pop(0)
    while args and re.match(r"^[A-Za-z_][A-Za-z_0-9]*=", args[0]):
        k, v = args.pop(0).split("=", 1)
        if k == MARKER:
            explicit = v
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
                return inspect_shell(args[i + 1], depth + 1)
        return None
    if exe != "git":
        return None
    while args and args[0].startswith("-"):
        opt = args.pop(0)
        if opt in ("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env"):
            if args:
                args.pop(0)
        elif opt == "--":
            break
    for name in created_names(args):
        # Expansion would conceal the complete name from this static hook.
        if any(c in name for c in ("$", "`")):
            return "Branch guard: supply the complete literal branch name instead of shell expansion."
        problem = check(name, explicit)
        if problem:
            return problem
    return None


def inspect_shell(command, depth=0):
    try:
        lex = shlex.shlex(command, posix=True, punctuation_chars=";&|()\n")
        lex.whitespace = " \t\r"
        lex.whitespace_split = True
        tokens = list(lex)
    except ValueError:
        return None  # Not a shell parser/security boundary; do not block unrelated tools.
    current = []
    for token in tokens + [";"]:
        if token and all(c in ";&|()\n" for c in token):
            problem = inspect_argv(current, depth)
            if problem:
                return problem
            current = []
        else:
            current.append(token)
    return None


def inspect_payload(data):
    if data.get("hook_event_name") != "PreToolUse":
        return None
    tool = data.get("tool_name", "").split(".")[-1]
    arg = data.get("tool_input", {})
    if isinstance(arg, str):
        try:
            arg = json.loads(arg)
        except ValueError:
            return None
    if not isinstance(arg, dict):
        return None
    if tool in ("exec_command", "shell", "shell_command", "Bash"):
        command = arg.get("cmd", arg.get("command"))
        if isinstance(command, list):
            return inspect_argv(command)
        if isinstance(command, str):
            return inspect_shell(command)
    return None


def main():
    try:
        problem = inspect_payload(json.load(sys.stdin))
    except (ValueError, TypeError):
        return
    if problem:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": problem}}))


if __name__ == "__main__":
    main()
