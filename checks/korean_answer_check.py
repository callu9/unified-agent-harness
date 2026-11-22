#!/usr/bin/python3
"""Stop/SubagentStop hook: ask once for a Korean rewrite when the answer is mostly English.

rules/30-language.md requires every user-visible line in Korean, yet long runs of
English tool output pull answers into English. Code blocks, inline code, URLs and
paths are ignored when measuring, so code-heavy Korean answers pass.

Reads only the final answer; nothing is stored or sent. Fails open, and blocks at
most once per turn (`stop_hook_active`) so it never loops.
"""
import json
import re
import sys

MIN_LETTERS = 40  # shorter answers are not judged
# Measured over the 25 latest sessions of each agent: healthy answers run 62-100%
# Hangul, half-English ones cluster at 36-50%. 0.2 let every one of them through.
MIN_HANGUL_RATIO = 0.6
NOISE = (r"```.*?```", r"`[^`\n]*`", r"https?://\S+", r"[A-Za-z]:[\\/][^\s)]*|~?/[\w./-]+")


def prose(text):
    text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
    for pattern in NOISE:
        text = re.sub(pattern, " ", text, flags=re.S)
    return text


def final_answer_from_transcript(path):
    """Claude Code transcript (JSONL): assistant text after the last user entry."""
    texts = []
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().splitlines()
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("isSidechain"):
            continue
        if entry.get("type") == "user":  # a prompt or tool result ends the final answer
            break
        content = (entry.get("message") or {}).get("content") if entry.get("type") == "assistant" else None
        if isinstance(content, list):
            texts[:0] = [c.get("text") or "" for c in content if isinstance(c, dict) and c.get("type") == "text"]
    return "\n".join(texts)


def verdict(payload):
    """Block reason when the answer needs a Korean rewrite, else None."""
    if payload.get("stop_hook_active"):
        return None
    answer = payload.get("last_assistant_message")
    if not isinstance(answer, str):
        path = payload.get("transcript_path")
        answer = final_answer_from_transcript(path) if path else ""
    text = prose(answer)
    hangul = len(re.findall(r"[가-힣]", text))
    latin = len(re.findall(r"[A-Za-z]", text))
    if hangul + latin < MIN_LETTERS or hangul / (hangul + latin) >= MIN_HANGUL_RATIO:
        return None
    return (f"마지막 답변이 영어로 작성됐습니다(한글 비율 {round(100 * hangul / (hangul + latin))}%). "
            "전역 규칙에 따라 같은 내용을 한국어로 다시 작성하세요. 코드, 명령어, 파일명, 식별자는 그대로 둡니다. "
            "프로젝트 AGENTS.md 가 다른 언어를 정했으면 그 사실을 한 줄로 밝히고 그대로 두세요.")


def main():
    try:
        reason = verdict(json.load(sys.stdin))
    except Exception:  # never block a session because of a hook error
        return
    if reason:
        print(json.dumps({"decision": "block", "reason": reason}, ensure_ascii=False))


if __name__ == "__main__":
    main()
