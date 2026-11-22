#!/usr/bin/python3
"""UserPromptSubmit hook: restate the active contract next to every prompt.

Instructions in AGENTS.md/CLAUDE.md arrive once per session and compete with
everything added after them. In an enrolled repository this hook restates the
gates and the live state: branch, pending changes and whether the worktree has
a fresh verification receipt. Outside an enrolled repository it prints nothing,
so unrelated chats stay free of Git noise.

Reads only; no prompt text, diff, log or personal data is stored or sent. Fails
open: on any error it adds nothing and the turn proceeds unchanged.
"""
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

CONTRACT_RELATIVE = os.path.join(".harness", "contract.md")
CONTRACT_MAX_CHARS = 700


def git(repo, *args):
    out = subprocess.run(("git", "-C", repo) + args, capture_output=True, text=True, timeout=5)
    return out.stdout if out.returncode == 0 else ""


def project_contract(repo):
    path = os.path.join(repo, CONTRACT_RELATIVE)
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read().strip()
    except OSError:
        return None
    if not text:
        return None
    if len(text) > CONTRACT_MAX_CHARS:
        text = text[:CONTRACT_MAX_CHARS].rstrip() + f"\n  (이어지는 내용은 {CONTRACT_RELATIVE} 참조)"
    return text


def build(cwd):
    import gates
    import harness_verify as verify

    repo = verify.repo_root(cwd)
    info = verify.status(repo)
    if not info["configured"]:
        return None
    pending = [line for line in git(repo, "status", "--porcelain=v1").splitlines() if line]
    if not info["gate_enabled"]:
        check = "게이트 해제됨 (.harness/harness.json gate=false)"
    else:
        recorded = (info["receipt"] or {}).get("recorded_at", "-")
        check = {
            "FRESH": "PASS 기록 일치 (commit 가능)",
            "MISSING": "기록 없음 — harness verify run 전까지 commit 차단",
            "STALE": f"기록이 현재 상태와 불일치 (마지막 {recorded}) — 다시 실행 전까지 commit 차단",
            "FAILED": f"마지막 결과 FAIL (마지막 {recorded}) — 수정 후 재실행 전까지 commit 차단",
        }.get(info["state"], info["state"])

    lines = ["활성 하드 게이트(기계 검사, 프롬프트로 우회되지 않음):"]
    lines += gates.lines(agent_hooks=True)
    lines += [
        "",
        f"현재 상태: {os.path.basename(repo)} / branch={info['branch'] or '-'} / "
        f"변경 {len(pending)}건 / 검증={check}",
    ]
    contract = project_contract(repo)
    if contract:
        lines += ["", f"프로젝트 계약({CONTRACT_RELATIVE}):", contract]
    return "<harness-turn-contract>\n" + "\n".join(lines) + "\n</harness-turn-contract>"


def main():
    try:
        payload = json.load(sys.stdin)
    except (ValueError, TypeError):
        return
    if payload.get("hook_event_name") not in (None, "UserPromptSubmit"):
        return
    cwd = payload.get("cwd") or os.getcwd()
    try:
        text = build(cwd)
    except BaseException:
        return  # Fail open: a contract reminder must never block the user's turn.
    if not text:
        return
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit", "additionalContext": text}},
        ensure_ascii=False))


if __name__ == "__main__":
    main()
