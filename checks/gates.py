"""Single list of machine-checked gates, shared by the rendered guidance and the turn hook.

`layers` says where a gate is enforced: `agent` (the agent's PreToolUse hook) and/or
`git` (the global Git hooks, enrolled repositories only). An agent without hook support
keeps only the `git` layer, and its guidance says so instead of overstating enforcement.
"""

GATES = (
    ("git commit: 등록 저장소(`.harness/harness.json`)에서는 현재 worktree 지문과 일치하는 "
     "PASS 검증 영수증이 필요하다. 영수증은 harness verify 가 명령을 직접 실행해야 생긴다.",
     ("agent", "git")),
    ("force-push: 차단 (git 층은 등록 저장소의 non-fast-forward push 만 막는다).", ("agent", "git")),
    ("`git commit --no-verify`: 차단.", ("agent",)),
    ("커밋 메시지의 AI 작성 표기(`Co-Authored-By: Claude…`, \"Generated with…\"): 등록 저장소에서 차단.", ("git",)),
    ("`codex/`, `claude/`, `agent/` 자동 브랜치 접두사: 차단.", ("agent",)),
    ("Codex Astra·Sol 이전 세대 모델(`gpt-6-*`, `gpt-6.1-*`)을 모델 인자로 넘기는 명령: 차단.", ("agent",)),
)


def lines(agent_hooks):
    """Gate bullets for an agent; `agent_hooks` is False when it cannot run PreToolUse hooks."""
    out = []
    for text, layers in GATES:
        active = [layer for layer in layers if agent_hooks or layer != "agent"]
        if not active:
            out.append(f"- {text} — 이 에이전트에서는 기계 검사되지 않는다. 지침으로 지킨다.")
        elif active == ["git"]:
            out.append(f"- {text} — 이 에이전트에서는 git hook 으로만 검사된다.")
        else:
            out.append(f"- {text}")
    return out
