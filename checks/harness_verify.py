#!/usr/bin/python3
"""Record truthful verification receipts for a Git worktree.

A receipt can only be created by executing the configured commands here, so it
proves the commands ran against this exact worktree state. It stores command
text, exit status, duration and time only: no logs, diffs, environment values
or personal data. Receipts live inside the per-worktree Git directory and are
never committed.
"""
import hashlib
import json
import os
import subprocess
import sys
import time

SCHEMA = 1
CONFIG_RELATIVE = os.path.join(".harness", "harness.json")
AUTO_SCRIPTS = ("lint", "typecheck", "test", "build")


def git(repo, *args, check=True):
    p = subprocess.run(("git", "-C", repo) + args, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise SystemExit(f"harness verify: git {' '.join(args)} failed: {p.stderr.strip()}")
    return p.stdout


def repo_root(start):
    out = subprocess.run(("git", "-C", start, "rev-parse", "--show-toplevel"),
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit(f"harness verify: not a Git worktree: {start}")
    return out.stdout.strip()


def receipt_path(repo):
    gitdir = git(repo, "rev-parse", "--absolute-git-dir").strip()
    return os.path.join(gitdir, "agent-harness", "verify-receipt.json")


def fingerprint(repo):
    """Identity of the current worktree content: HEAD plus every path that differs from it.

    Hashes file contents rather than a diff, so staging (`git add`) after verifying
    does not change the fingerprint.
    """
    h = hashlib.sha256()
    head = git(repo, "rev-parse", "--verify", "-q", "HEAD", check=False).strip() or "(no-head)"
    h.update(head.encode())
    if head == "(no-head)":
        changed = git(repo, "ls-files", "-z")
    else:
        changed = git(repo, "diff", "HEAD", "--name-only", "--no-renames", "-z")
    changed += git(repo, "ls-files", "--others", "--exclude-standard", "-z")
    for path in sorted({p for p in changed.split("\0") if p}):
        h.update(b"\0" + path.encode() + b"\0")
        full = os.path.join(repo, path)
        try:
            with open(full, "rb") as fh:
                for chunk in iter(lambda: fh.read(1 << 16), b""):
                    h.update(chunk)
        except OSError:
            h.update(b"(unreadable)")
    return h.hexdigest(), head


def load_config(repo):
    path = os.path.join(repo, CONFIG_RELATIVE)
    if not os.path.exists(path):
        return None
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        raise SystemExit(f"harness verify: unreadable {CONFIG_RELATIVE}: {exc}")
    if not isinstance(data, dict):
        raise SystemExit(f"harness verify: {CONFIG_RELATIVE} must be a JSON object")
    return data


def auto_commands(repo):
    try:
        with open(os.path.join(repo, "package.json"), encoding="utf-8") as fh:
            scripts = json.load(fh).get("scripts") or {}
    except (OSError, ValueError):
        return []
    return [f"npm run {name}" for name in AUTO_SCRIPTS if name in scripts]


def resolve_commands(repo, override):
    if override:
        return list(override)
    config = load_config(repo)
    if config and config.get("commands"):
        commands = config["commands"]
        if not all(isinstance(c, str) and c.strip() for c in commands):
            raise SystemExit(f"harness verify: {CONFIG_RELATIVE} commands must be non-empty strings")
        return list(commands)
    return auto_commands(repo)


def read_receipt(repo):
    try:
        with open(receipt_path(repo), encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def status(repo):
    current, head = fingerprint(repo)
    receipt = read_receipt(repo)
    gate = True
    config = load_config(repo)
    if config is not None:
        gate = bool(config.get("gate", True))
    state = "MISSING"
    if receipt:
        if receipt.get("result") != "PASS":
            state = "FAILED"
        elif receipt.get("fingerprint") != current:
            state = "STALE"
        else:
            state = "FRESH"
    return {
        "repository": repo,
        "branch": git(repo, "rev-parse", "--abbrev-ref", "HEAD", check=False).strip(),
        "head": head,
        "fingerprint": current,
        "gate_enabled": gate,
        "configured": config is not None,
        "state": state,
        "receipt": receipt,
    }


def run(repo, override):
    commands = resolve_commands(repo, override)
    if not commands:
        raise SystemExit(
            "harness verify: no verification commands. Create .harness/harness.json with "
            '{"commands": ["npm run lint", "npm run test"]} or pass -- <command>...')
    before, _ = fingerprint(repo)
    records = []
    failed = None
    for command in commands:
        print(f"==> {command}", flush=True)
        started = time.time()
        code = subprocess.run(command, shell=True, cwd=repo).returncode
        records.append({"command": command, "exit_code": code,
                        "duration_s": round(time.time() - started, 2)})
        if code != 0 and failed is None:
            failed = command
            break
    after, head = fingerprint(repo)
    if after != before:
        # A command changed the tree; the receipt would not describe what was verified.
        raise SystemExit("harness verify: the worktree changed while verifying; "
                         "review the change and run harness verify again.")
    receipt = {
        "schema": SCHEMA,
        "result": "PASS" if failed is None else "FAIL",
        "fingerprint": after,
        "head": head,
        "branch": git(repo, "rev-parse", "--abbrev-ref", "HEAD", check=False).strip(),
        "recorded_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "commands": records,
    }
    path = receipt_path(repo)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(receipt, fh, ensure_ascii=False, indent=2)
        fh.write("\n")
    os.replace(tmp, path)
    print(f"\nharness verify: {receipt['result']} recorded for {receipt['fingerprint'][:12]}")
    if failed is not None:
        print(f"harness verify: failed command: {failed}")
        return 1
    return 0


def enroll(repo, apply_changes, commands=None):
    """Write .harness/harness.json so the commit gate applies to this repository."""
    path = os.path.join(repo, CONFIG_RELATIVE)
    if os.path.exists(path):
        print(f"harness verify: {CONFIG_RELATIVE} already exists; edit it by hand.")
        return 1
    commands = list(commands or auto_commands(repo))
    if not commands:
        print("harness verify: no lint/typecheck/test/build script found in package.json. "
              "Pass the project's real commands after `--`.")
        return 1
    body = json.dumps({"gate": True, "commands": commands}, ensure_ascii=False, indent=2) + "\n"
    if not apply_changes:
        print(f"harness verify: would create {path}\n\n{body}"
              "Re-run with --apply to write it. Commit it with the project's own changes.")
        return 0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(body)
    print(f"harness verify: created {path}. Run `harness verify run` before the next commit.")
    return 0


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        print("\nUsage:\n  harness verify run [--repo PATH] [-- <command>...]\n"
              "  harness verify status [--repo PATH] [--json]\n"
              "  harness enroll [--repo PATH] [--apply] [-- <command>...]")
        return 0
    action, rest = argv[0], argv[1:]
    repo_arg = os.getcwd()
    as_json = False
    apply_changes = False
    override = []
    while rest:
        item = rest.pop(0)
        if item == "--repo" and rest:
            repo_arg = rest.pop(0)
        elif item == "--json":
            as_json = True
        elif item == "--apply":
            apply_changes = True
        elif item == "--":
            override = rest
            rest = []
        else:
            raise SystemExit(f"harness verify: unexpected argument {item!r}")
    repo = repo_root(repo_arg)
    if action == "run":
        return run(repo, override)
    if action == "enroll":
        return enroll(repo, apply_changes, override)
    if action == "status":
        info = status(repo)
        if as_json:
            print(json.dumps(info, ensure_ascii=False, indent=2))
        else:
            print(f"{info['state']}  branch={info['branch']} "
                  f"gate={'unenrolled' if not info['configured'] else 'on' if info['gate_enabled'] else 'off'} "
                  f"fingerprint={info['fingerprint'][:12]}")
            if info["receipt"]:
                print(f"last recorded_at={info['receipt'].get('recorded_at')} "
                      f"result={info['receipt'].get('result')}")
        return 0 if info["state"] == "FRESH" else 1
    raise SystemExit(f"harness verify: unknown action {action!r}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
