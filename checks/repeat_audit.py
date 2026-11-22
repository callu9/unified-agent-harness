#!/usr/bin/python3
"""Find instructions you had to repeat, so they can be promoted into rules.

Reads this machine's own Codex and Claude Code session logs, keeps the short corrective user
turns ("...하지 마", "왜 ...", "또 ...", "매번 ..."), groups the ones that say the
same thing, and reports the groups per project with how often they recurred.
A group with two or more hits is a rule that was never written down.

Output stays on this machine; nothing is uploaded, and no file is modified.
"""
import argparse
import collections
import json
import os
import re
import subprocess
import sys
import time

SESSION_DIRS = ("~/.codex/archived_sessions", "~/.codex/sessions", "~/.claude/projects")
RG = "/Applications/ChatGPT.app/Contents/Resources/codex-cli/codex-path/rg"

# A corrective turn tells the agent it got something wrong, or repeats a standing rule.
CORRECTION_MARKERS = (
    "하지 마", "하지마", "하지말", "금지", "왜 ", "왜그", "왜 자꾸", "또 ", "또다시",
    "매번", "자꾸", "빼먹", "누락", "안 했", "안했", "잊었", "잊지", "아니 ",
    "말했", "반복", "지침", "규칙대로", "하지 않", "하면 안", "지랄", "다시 하",
    "do not", "don't", "never", "stop ",
)
# Wrapper turns the client injects; they are not the user speaking.
WRAPPERS = ("# AGENTS.md instructions", "<INSTRUCTIONS>", "<environment_context>",
            "<app-context>", "<user_instructions>", "<llmwiki-context",
            "<codex-turn-contract>", "<harness-turn-contract>", "<system-reminder>", "<command-name>", "<in-app-browser-context", "ambient-ui-state",
            "<selected-text>", "automatically supplied",
            "# Response annotations:", "# Files mentioned by the user:",
            "<response-annotations>", "# Selected text:")
MIN_CONTENT_TOKENS = 4
PARTICLES = re.compile(r"(은|는|이|가|을|를|에|의|로|으로|도|만|와|과|에서|부터|까지|"
                       r"하라|해라|해줘|하고|한다|했다|했어|한테|이다)$")
STOPWORDS = {"그리고", "그런데", "그래서", "지금", "이거", "저거", "너무", "조금", "다시",
             "현재", "이번", "다음", "진행", "확인", "그냥", "이제", "아니", "the", "and",
             "for", "with", "that", "this", "you", "not", "but", "are", "was"}
MACHINE_HINTS = (("커밋", "commit"), ("푸시", "push"), ("브랜치", "branch"), ("lint",),
                 ("test", "테스트"), ("build", "빌드"), ("검증",), ("타입", "typecheck"))


def session_files(days, limit_dirs=SESSION_DIRS):
    cutoff = time.time() - days * 86400 if days else 0
    found = []
    for base in limit_dirs:
        root = os.path.expanduser(base)
        for dirpath, _dirs, names in os.walk(root):
            for name in names:
                if not name.endswith(".jsonl"):
                    continue
                path = os.path.join(dirpath, name)
                try:
                    if os.path.getmtime(path) >= cutoff:
                        found.append(path)
                except OSError:
                    continue
    return sorted(found)


def scan(paths):
    """Yield (path, parsed line) for session metadata and user turns only."""
    if not paths:
        return
    use_rg = os.path.exists(RG)
    if use_rg:
        proc = subprocess.Popen(
            [RG, "--no-heading", "--with-filename", "--color", "never", "-e",
             r'"type":\s*"session_meta"', "-e", r'"role":\s*"user"', "--", *paths],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
            errors="replace", bufsize=1 << 20)
        for raw in proc.stdout:
            path, _, payload = raw.partition(":")
            try:
                yield path, json.loads(payload)
            except ValueError:
                continue
        proc.wait()
        return
    for path in paths:
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                for raw in fh:
                    if '"session_meta"' not in raw and '"user"' not in raw:
                        continue
                    try:
                        yield path, json.loads(raw)
                    except ValueError:
                        continue
        except OSError:
            continue


def message_text(payload):
    if payload.get("type") not in ("message", None) or payload.get("role") != "user":
        return None
    parts = payload.get("content") or []
    if isinstance(parts, str):  # Claude Code stores plain prompts as a string.
        return parts.strip() or None
    text = "".join(c.get("text", "") for c in parts if isinstance(c, dict))
    return text.strip() or None


def project_of(cwd):
    if not cwd:
        return "(unknown)"
    out = subprocess.run(("git", "-C", cwd, "rev-parse", "--show-toplevel"),
                         capture_output=True, text=True)
    root = out.stdout.strip() if out.returncode == 0 else cwd
    return os.path.basename(root.rstrip("/")) or root


def is_correction(text, max_chars):
    if len(text) > max_chars:
        return False
    head = text[:400]
    if any(w in head for w in WRAPPERS):
        return False
    if head.lstrip().startswith("<") and ">" in head:
        return False  # A client-injected context block, not the user speaking.
    return any(m in text for m in CORRECTION_MARKERS)


def tokens(text):
    text = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
    text = re.sub(r"`[^`]*`", " ", text)
    text = re.sub(r"https?://\S+|/\S+/\S*", " ", text)
    raw = re.findall(r"[0-9A-Za-z_\-]{3,}|[가-힣]{2,}", text)
    out = set()
    for token in raw:
        token = token.lower()
        if re.fullmatch(r"[가-힣]{2,}", token):
            token = PARTICLES.sub("", token) or token
        if len(token) >= 2 and token not in STOPWORDS:
            out.add(token)
    return out


def cluster(entries, threshold):
    """Greedy grouping of utterances that share most of their content words."""
    groups = []
    for entry in sorted(entries, key=lambda e: len(e["tokens"]), reverse=True):
        for group in groups:
            shared = len(entry["tokens"] & group["tokens"])
            union = len(entry["tokens"] | group["tokens"]) or 1
            if shared / union >= threshold:
                group["members"].append(entry)
                group["tokens"] |= entry["tokens"]
                break
        else:
            groups.append({"tokens": set(entry["tokens"]), "members": [entry]})
    return groups


def promotion_hint(text):
    for words in MACHINE_HINTS:
        if any(w in text.lower() for w in words):
            return "기계 검사 후보 (게이트·스크립트·CI)"
    return ".harness/contract.md 또는 가장 가까운 AGENTS.md 한 줄"


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--days", type=int, default=30, help="최근 N일 (0=전체, 기본 30)")
    ap.add_argument("--project", help="프로젝트 디렉터리 이름으로 필터")
    ap.add_argument("--min", type=int, default=2, dest="minimum", help="최소 반복 횟수 (기본 2)")
    ap.add_argument("--limit", type=int, default=6, help="프로젝트별 출력 그룹 수 (기본 6)")
    ap.add_argument("--max-chars", type=int, default=500, help="교정 발화로 볼 최대 길이")
    ap.add_argument("--threshold", type=float, default=0.45, help="묶는 기준 Jaccard (기본 0.45)")
    ap.add_argument("--json", action="store_true", dest="as_json")
    args = ap.parse_args(argv)

    paths = session_files(args.days)
    if not paths:
        print("세션 로그가 없다.", file=sys.stderr)
        return 1
    cwd_of = {}
    name_of = {}
    by_project = collections.defaultdict(list)
    for path, record in scan(paths):
        kind = record.get("type")
        if kind == "session_meta":
            cwd_of[path] = (record.get("payload") or {}).get("cwd")
            continue
        if kind == "user":  # Claude Code: one record per turn, cwd on the record.
            cwd_of[path] = record.get("cwd") or cwd_of.get(path)
            text = message_text(record.get("message") or {})
        else:
            text = message_text(record.get("payload") or {})
        if not text or not is_correction(text, args.max_chars):
            continue
        words = tokens(text)
        if len(words) < MIN_CONTENT_TOKENS:
            continue  # Too thin to say what the rule would be.
        cwd = cwd_of.get(path)
        if cwd not in name_of:
            # One project can be worked on from several worktrees; report it once.
            name_of[cwd] = project_of(cwd)
        by_project[name_of[cwd]].append(
            {"text": text, "at": (record.get("timestamp") or "")[:10], "tokens": words})

    report = []
    for name, entries in by_project.items():
        if args.project and args.project not in name:
            continue
        groups = [g for g in cluster(entries, args.threshold)
                  if len(g["members"]) >= args.minimum]
        groups.sort(key=lambda g: len(g["members"]), reverse=True)
        if not groups:
            continue
        report.append({
            "project": name,
            "corrective_turns": len(entries),
            "groups": [{
                "count": len(g["members"]),
                "first": min(m["at"] for m in g["members"]),
                "last": max(m["at"] for m in g["members"]),
                "sample": min((m["text"] for m in g["members"]), key=len)[:220],
                "promote_to": promotion_hint(" ".join(m["text"] for m in g["members"])),
            } for g in groups[:args.limit]],
        })
    report.sort(key=lambda r: sum(g["count"] for g in r["groups"]), reverse=True)

    if args.as_json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
        return 0
    if not report:
        print(f"최근 {args.days}일 안에 {args.minimum}회 이상 반복된 교정이 없다.")
        return 0
    print(f"# 반복된 교정 — 최근 {args.days or '전체'}일, {len(paths)}개 세션 로그\n")
    for item in report:
        print(f"## {item['project']}  (교정성 발화 {item['corrective_turns']}건)")
        for group in item["groups"]:
            print(f"  {group['count']}회  {group['first']}~{group['last']}")
            print(f"    “{group['sample'].replace(chr(10), ' ')}”")
            print(f"    → 승격 위치: {group['promote_to']}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
