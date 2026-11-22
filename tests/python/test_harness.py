"""Contract tests for the agent-neutral harness: rendering, hook merge and both gate layers."""
import importlib.machinery
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "checks"))
harness = importlib.machinery.SourceFileLoader("harness", os.path.join(ROOT, "bin", "harness")).load_module()
import gates  # noqa: E402
import codex_model_guard  # noqa: E402
import korean_answer_check  # noqa: E402
import git_gate  # noqa: E402
import turn_contract  # noqa: E402

CODEX = {"name": "codex", "home": "~", "global_file": "~/x", "project_file": "AGENTS.md",
         "hooks_file": "~/h.json", "shell_matcher": "exec_command|Bash",
         "legacy_hook_paths": ["/old/hooks/commit-gate.py"], "legacy_blocks": ["branch-name-guard"]}
HOOKLESS = {"name": "new", "home": "~", "global_file": "~/y", "project_file": "NEW.md"}


def git(repo, *args, env=None):
    return subprocess.run(("git", "-C", repo) + args, capture_output=True, text=True, env=env)


def make_repo(enrolled):
    repo = tempfile.mkdtemp()
    git(repo, "init", "-q")
    git(repo, "config", "user.email", "t@example.com")
    git(repo, "config", "user.name", "t")
    with open(os.path.join(repo, "a.txt"), "w") as fh:
        fh.write("a\n")
    if enrolled:
        os.makedirs(os.path.join(repo, ".harness"))
        with open(os.path.join(repo, ".harness", "harness.json"), "w") as fh:
            json.dump({"gate": True, "commands": ["true"]}, fh)
    git(repo, "add", "-A")
    git(repo, "commit", "-qm", "init", "--no-verify")
    return repo


class Rendering(unittest.TestCase):
    def test_compose_keeps_foreign_blocks_and_drops_legacy(self):
        text = ("old body\n\n<!-- llmwiki-context:start -->\nwiki\n<!-- llmwiki-context:end -->\n\n"
                "<!-- branch-name-guard:start -->\nold\n<!-- branch-name-guard:end -->\n")
        out = harness.compose(text, CODEX, adopt=True)
        self.assertTrue(out.startswith(harness.START))
        self.assertIn("<!-- llmwiki-context:start -->\nwiki\n", out)
        self.assertNotIn("branch-name-guard", out)
        self.assertNotIn("old body", out)
        self.assertEqual(out, harness.compose(out, CODEX, adopt=False))  # idempotent
        self.assertIn("old body", harness.compose(text, CODEX, adopt=False))  # no silent loss

    def test_render_has_no_unfilled_placeholders(self):
        for adapter in (CODEX, HOOKLESS):
            self.assertNotIn("{{", harness.render(adapter))

    def test_hookless_agent_is_told_what_is_not_enforced(self):
        text = "\n".join(gates.lines(agent_hooks=False))
        self.assertIn("기계 검사되지 않는다", text)
        self.assertIn("git hook 으로만", text)
        self.assertNotIn("<harness-turn-contract>", harness.render(HOOKLESS))


class HookMerge(unittest.TestCase):
    def test_merge_replaces_legacy_and_keeps_foreign_hooks(self):
        settings = {"hooks": {
            "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "llmwiki hook"}]}],
            "PreToolUse": [{"matcher": "Bash", "hooks": [
                {"type": "command", "command": "python3 /old/hooks/commit-gate.py"}]}]}}
        once = harness.merge_hooks(json.loads(json.dumps(settings)), CODEX)
        twice = harness.merge_hooks(json.loads(json.dumps(once)), CODEX)
        self.assertEqual(once, twice)
        commands = [h["command"] for gs in once["hooks"].values() for g in gs for h in g["hooks"]]
        self.assertIn("llmwiki hook", commands)
        self.assertFalse(any("/old/hooks" in c for c in commands))
        self.assertTrue(once["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"].endswith("turn_contract.py"))
        self.assertEqual(len(once["hooks"]["PreToolUse"]), sum(h[0] == "PreToolUse" for h in harness.HOOKS))


class Gates(unittest.TestCase):
    def test_pre_commit_requires_fresh_receipt_only_when_enrolled(self):
        free, gated = make_repo(False), make_repo(True)
        cwd = os.getcwd()
        try:
            os.chdir(free)
            self.assertIsNone(git_gate.pre_commit())
            os.chdir(gated)
            self.assertIn("MISSING", git_gate.pre_commit())
            os.environ["HARNESS_VERIFY_OVERRIDE"] = "user said so"
            self.assertIsNone(git_gate.pre_commit())
            del os.environ["HARNESS_VERIFY_OVERRIDE"]
            subprocess.run((sys.executable, os.path.join(ROOT, "bin", "harness"), "verify", "run"),
                           capture_output=True, check=True)
            self.assertIsNone(git_gate.pre_commit())
        finally:
            os.chdir(cwd)

    def test_staging_after_verify_keeps_receipt_fresh(self):
        repo = make_repo(True)
        with open(os.path.join(repo, "new.txt"), "w") as fh:
            fh.write("new\n")
        subprocess.run((sys.executable, os.path.join(ROOT, "bin", "harness"), "verify", "run", "--repo", repo),
                       capture_output=True, check=True)
        git(repo, "add", "-A")
        self.assertEqual(git_gate.verify.status(repo)["state"], "FRESH")
        with open(os.path.join(repo, "new.txt"), "a") as fh:
            fh.write("edited\n")
        self.assertEqual(git_gate.verify.status(repo)["state"], "STALE")

    def test_pre_push_blocks_non_fast_forward(self):
        repo = make_repo(True)
        old = git(repo, "rev-parse", "HEAD").stdout.strip()
        git(repo, "commit", "-q", "--amend", "-m", "rewritten", "--no-verify")
        new = git(repo, "rev-parse", "HEAD").stdout.strip()
        cwd = os.getcwd()
        try:
            os.chdir(repo)
            self.assertIn("non-fast-forward", git_gate.pre_push([f"refs/heads/m {new} refs/heads/m {old}"]))
            self.assertIsNone(git_gate.pre_push([f"refs/heads/m {new} refs/heads/m {'0' * 40}"]))
        finally:
            os.chdir(cwd)

    def test_dispatcher_runs_gate_and_chains_repository_hook(self):
        repo = make_repo(True)
        own = os.path.join(repo, ".git", "hooks", "commit-msg")
        with open(own, "w") as fh:
            fh.write("#!/bin/sh\ntouch \"$(git rev-parse --git-dir)/chained\"\n")
        os.chmod(own, 0o755)
        hooks = os.path.join(ROOT, "githooks")
        with open(os.path.join(repo, "a.txt"), "a") as fh:
            fh.write("b\n")
        git(repo, "add", "-A")
        blocked = git(repo, "-c", f"core.hooksPath={hooks}", "commit", "-qm", "x")
        self.assertNotEqual(blocked.returncode, 0)
        self.assertIn("agent-harness: commit blocked", blocked.stderr)
        env = dict(os.environ, HARNESS_VERIFY_OVERRIDE="test")
        done = git(repo, "-c", f"core.hooksPath={hooks}", "commit", "-qm", "x", env=env)
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertTrue(os.path.exists(os.path.join(repo, ".git", "chained")))


class CommitMessage(unittest.TestCase):
    def test_commit_msg_gate_rejects_ai_attribution_only_when_enrolled(self):
        cwd = os.getcwd()
        try:
            for enrolled, expected in ((True, True), (False, False)):
                os.chdir(make_repo(enrolled))
                with open("msg", "w", encoding="utf-8") as fh:
                    fh.write("feat: x\n\nCo-Authored-By: Claude Opus 5 <noreply@anthropic.com>\n")
                self.assertEqual(git_gate.commit_msg("msg") is not None, expected)
            os.chdir(make_repo(True))
            for text, blocked in (("feat: x\n\nCo-Authored-By: Kim <kim@example.com>\n", False),
                                  ("feat: x\n\nCo-Authored-By: Claude Martin <claude@example.com>\n", False),
                                  ("feat: x\n\nCo-Authored-By: Claude <noreply@anthropic.com>\n", True),
                                  ("feat: x\n\nCo-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>\n", True),
                                  ("feat: x\n\nCo-authored-by: Engineer <person@openai.com>\n", False),
                                  ("feat: x\n\nCo-authored-by: Claude Martin <12345+cmartin@users.noreply.github.com>\n", False),
                                  ("feat: x\n\nCo-authored-by: Claude <12345+claude[bot]@users.noreply.github.com>\n", True),
                                  ("feat: x\n\nCo-Authored-By: Codex <98765+chatgpt-codex-connector[bot]@users.noreply.github.com>\n", True),
                                  ("feat: x\n\nCo-authored-by: CodeXML Validator <12345+codexml-validator[bot]@users.noreply.github.com>\n", False),
                                  ("feat: x\n\nCo-authored-by: Codex <1+openai-codex[bot]@users.noreply.github.com>\n", True),
                                  ("feat: x\n\nCo-authored-by: Copilot <198982749+Copilot@users.noreply.github.com>\n", True),
                                  ("feat: x\n\nCo-authored-by: Copilot Coding Agent <198982749+Copilot@users.noreply.github.com>\n", True),
                                  ("feat: x\n\nCo-authored-by: Jane <12345+janegemini-talbot@users.noreply.github.com>\n", False),
                                  ("fix: retry generated ids\n", False),
                                  ("feat: x\n# Generated with Claude Code\n", False),
                                  ("docs: x\n\n- block `Co-Authored-By` and \"Generated with/by <AI>\" lines\n", False),
                                  ("feat: x\n\n🤖 Generated with [Claude Code](https://claude.com)\n", True)):
                with open("msg", "w", encoding="utf-8") as fh:
                    fh.write(text)
                self.assertEqual(git_gate.commit_msg("msg") is not None, blocked, text)
        finally:
            os.chdir(cwd)

    def test_adapter_settings_are_written(self):
        adapter = {**CODEX, "settings": {"attribution": {"commit": "", "pr": ""}}}
        merged = harness.merge_hooks({"attribution": {"commit": "x"}, "theme": "dark"}, adapter)
        self.assertEqual((merged["attribution"], merged["theme"]), ({"commit": "", "pr": ""}, "dark"))

    def test_adapter_dict_settings_merge_one_level_deep(self):
        adapter = {**CODEX, "settings": {"env": {"A": "1"}}}
        merged = harness.merge_hooks({"env": {"HTTPS_PROXY": "p", "A": "0"}}, adapter)
        self.assertEqual(merged["env"], {"HTTPS_PROXY": "p", "A": "1"})


class CodexModelGuard(unittest.TestCase):
    def test_old_astra_and_sol_models_are_denied_only_as_model_arguments(self):
        denied = ('codex review --base main -c model="gpt-6-astra" -c model_reasoning_effort="high"',
                  "codex exec -m gpt-6.1-sol 'fix it'",
                  "orca orchestration worker-start --agent codex --model gpt-6-sol --json",
                  "codex exec --model=gpt-6-astra x", "codex -mgpt-6.1-sol x",
                  "echo ok\ncodex exec --model gpt-6-astra 'x'", "cd x && codex review --config 'model=\"gpt-6-sol\"'")
        allowed = ('codex review --base main -c model="gpt-6.2-astra"', "codex -m gpt-6.2-sol",
                   'git commit -m "gpt-6-sol -> gpt-6.2-sol"', "grep -rn gpt-6-astra rules",
                   "grep -F -- '--model gpt-6-astra' README.md",
                   'codex exec --model gpt-6.2-astra "explain the old --model gpt-6-astra flag"',
                   "codex exec 'line one\n--model gpt-6-astra'")
        for command in denied:
            self.assertIn("gpt-6.2-", codex_model_guard.problem_in(command), command)
        for command in allowed:
            self.assertIsNone(codex_model_guard.problem_in(command), command)
        # Known false positive: an argv list is joined and scanned as one command, so a quoted prompt is denied.
        self.assertIn("gpt-6.2-", codex_model_guard.problem_in(["codex", "exec", "explain --model gpt-6-astra"]))
        for argv in (["bash", "--norc", "-c", "codex --model gpt-6-astra"],
                     ["/usr/bin/env", "bash", "-c", "codex --model gpt-6-astra"],
                     ["pwsh", "-Command", "codex --model gpt-6-astra"],
                     ["sh", "-c", 'exec "$@"', "sh", "codex", "--model", "gpt-6-astra"]):
            self.assertIn("gpt-6.2-", codex_model_guard.problem_in(argv), argv)
        self.assertIn("gpt-6.2-", codex_model_guard.problem_in(["codex", "--model", "gpt-6-astra", "exec", "x"]))
        self.assertIn("gpt-6.2-", codex_model_guard.problem_in(["/bin/bash", "-lc", "codex --model gpt-6-astra"]))
        payload = {"hook_event_name": "PreToolUse", "tool_name": "exec_command",
                   "tool_input": {"cmd": ["codex", "-m", "gpt-6-astra"]}}
        self.assertIsNotNone(codex_model_guard.inspect_payload(payload))


class AgentHooks(unittest.TestCase):
    def run_hook(self, script, payload):
        out = subprocess.run((sys.executable, os.path.join(ROOT, "checks", script)),
                             input=json.dumps(payload), capture_output=True, text=True)
        return json.loads(out.stdout)["hookSpecificOutput"]["permissionDecision"] if out.stdout else "allow"

    def test_same_scripts_serve_codex_and_claude_payloads(self):
        repo = make_repo(True)
        claude = {"hook_event_name": "PreToolUse", "cwd": repo, "tool_name": "Bash"}
        codex = {"hook_event_name": "PreToolUse", "cwd": repo, "tool_name": "exec_command"}
        branch = "git switch -c claude/auto-name"
        self.assertEqual(self.run_hook("branch_name_guard.py", {**claude, "tool_input": {"command": branch}}), "deny")
        self.assertEqual(self.run_hook("branch_name_guard.py", {**codex, "tool_input": {"cmd": branch.split()}}), "deny")
        explicit = "HARNESS_USER_BRANCH_NAME='claude/auto-name' " + branch
        self.assertEqual(self.run_hook("branch_name_guard.py", {**claude, "tool_input": {"command": explicit}}), "allow")
        commit = {"command": "git commit -m x"}
        self.assertEqual(self.run_hook("commit_gate.py", {**claude, "tool_input": commit}), "deny")
        self.assertEqual(self.run_hook("commit_gate.py", {**claude, "cwd": make_repo(False), "tool_input": commit}), "allow")


class TurnContract(unittest.TestCase):
    def test_silent_outside_enrolled_repositories(self):
        self.assertIsNone(turn_contract.build(make_repo(False)))
        payload = json.dumps({"hook_event_name": "UserPromptSubmit", "cwd": tempfile.mkdtemp()})
        out = subprocess.run((sys.executable, os.path.join(ROOT, "checks", "turn_contract.py")),
                             input=payload, capture_output=True, text=True)
        self.assertEqual((out.returncode, out.stdout), (0, ""))  # not a Git directory

    def test_enrolled_repository_gets_state(self):
        text = turn_contract.build(make_repo(True))
        self.assertIn("<harness-turn-contract>", text)
        self.assertIn("기록 없음", text)


class KoreanAnswerCheck(unittest.TestCase):
    ENGLISH = "I updated the rules and registered the hook so the next session picks it up properly."

    def test_blocks_english_once_and_passes_korean_or_code(self):
        self.assertIn("한국어", korean_answer_check.verdict({"last_assistant_message": self.ENGLISH}))
        self.assertIsNone(korean_answer_check.verdict({"last_assistant_message": self.ENGLISH,
                                                       "stop_hook_active": True}))
        korean = "규칙을 고치고 훅을 등록했습니다. `checks/korean_answer_check.py` 를 확인하세요.\n```\n" + self.ENGLISH + "\n```"
        self.assertIsNone(korean_answer_check.verdict({"last_assistant_message": korean}))

    def test_blocks_half_english_answer(self):
        # The band real sessions land in: Korean framing around English prose.
        half = "훅을 등록했습니다. " + self.ENGLISH + " 다음 세션부터 적용됩니다."
        self.assertIn("한국어", korean_answer_check.verdict({"last_assistant_message": half}))

    def test_reads_claude_transcript_and_fails_open(self):
        path = os.path.join(tempfile.mkdtemp(), "t.jsonl")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(json.dumps({"type": "user", "message": {"content": "질문"}}) + "\n")
            fh.write(json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": self.ENGLISH}]}}) + "\n")
        self.assertIsNotNone(korean_answer_check.verdict({"transcript_path": path}))
        out = subprocess.run((sys.executable, os.path.join(ROOT, "checks", "korean_answer_check.py")),
                             input="not json", capture_output=True, text=True)
        self.assertEqual((out.returncode, out.stdout), (0, ""))


if __name__ == "__main__":
    unittest.main()
