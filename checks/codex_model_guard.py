#!/usr/bin/python3
"""Agent PreToolUse gate: Codex Astra and Sol run only on the gpt-6.2 generation.

The gate list names `gpt-6.2-astra` and `gpt-6.2-sol`. This denies a shell command that
passes an older Astra/Sol model (`gpt-6-*`, `gpt-6.1-*`) as a model argument
(`--model`, `model=` in `-c`, or `-m` in a codex command), whether to codex, orca or another launcher.
Mentioning a model name anywhere else (grep, a commit message) passes.
Read-only; fails open on any payload it cannot read.
"""
import json
import os
import re
import shlex
import sys

ALLOWED = {"astra": "gpt-6.2-astra", "sol": "gpt-6.2-sol"}
NOT_LAUNCHERS = {"grep", "egrep", "fgrep", "rg", "ag", "echo", "printf", "cat", "sed", "awk", "git", "gh"}
OLD_MODEL = re.compile(r"[\"'\\]*(gpt-6(?:\.[01])?-(astra|sol))[\"'\\]*$")


def segments(command):
    """Split a command into argv segments (on ; && || | and newlines outside quotes), or None when it cannot be tokenized."""
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars="();<>|&\n")
        lexer.whitespace = " \t\r"
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        return None
    out, cur = [], []
    for token in tokens:
        if token and set(token) <= set("&|;\n"):
            out.append(cur)
            cur = []
        else:
            cur.append(token)
    return [seg for seg in out + [cur] if seg]


def model_values(seg):
    """Values given as a model argument in one argv segment; `-m` counts only for codex (git's `-m` is a message)."""
    codex = any(os.path.basename(t) == "codex" for t in seg)
    for i, tok in enumerate(seg):
        nxt = seg[i + 1] if i + 1 < len(seg) else ""
        if tok == "--model" or (codex and tok == "-m"):
            yield nxt
        elif tok.startswith("--model="):
            yield tok[8:]
        elif codex and tok.startswith("-m") and not tok.startswith("--"):
            yield tok[2:].lstrip("=")
        elif tok in ("-c", "--config") and re.match(r"model\s*=", nxt):
            yield nxt.split("=", 1)[1]
        elif tok.startswith("--config=model") and tok.count("=") > 1:
            yield tok.split("=", 2)[2]


def problem_in(command):
    # shortcut: argv is joined and scanned as one command, so a prompt that quotes an old --model value is denied; parse launchers per argv only if that false positive shows up in practice
    if isinstance(command, list):
        command = " ".join(str(p) for p in command)
    segs = segments(command)
    # Only whole argument tokens are inspected, so a prompt that merely quotes an old `--model` flag passes.
    for seg in [command.split()] if segs is None else segs:
        if os.path.basename(seg[0]) in NOT_LAUNCHERS:
            continue
        for value in model_values(seg):
            found = OLD_MODEL.match(value)
            if found:
                return (f"Codex model gate: `{found.group(1)}` is an older generation. "
                        f"Use `{ALLOWED[found.group(2)]}` for {found.group(2).capitalize()} (see the gate list).")
    return None


def inspect_payload(data):
    if data.get("hook_event_name") != "PreToolUse":
        return None
    arg = data.get("tool_input", {})
    if isinstance(arg, str):
        try:
            arg = json.loads(arg)
        except ValueError:
            return None
    if not isinstance(arg, dict):
        return None
    command = arg.get("cmd", arg.get("command"))
    return problem_in(command) if isinstance(command, (str, list)) else None


def main():
    try:
        problem = inspect_payload(json.load(sys.stdin))
    except Exception:  # never block a command the gate cannot read
        return
    if problem:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse", "permissionDecision": "deny",
            "permissionDecisionReason": problem}}))


if __name__ == "__main__":
    main()
