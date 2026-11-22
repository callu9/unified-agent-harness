# agent-harness — Current Public Contract v3.4.0

Prior contracts live in CHANGELOG.md and Git history (v2.0.1 and earlier: `codex-harness-core`).

## Purpose and ownership

This repository is the single source for personal agent guidance and gates on this machine,
independent of any one agent. `bin/harness apply` deploys it; nothing deploys on checkout.

| Layer | Source | Deployed to |
|---|---|---|
| Global rules | `rules/*.md` (sorted, agent-neutral, `{{gates}}` `{{turn_contract}}` `{{harness}}` placeholders) | each detected adapter's `global_file`, inside `<!-- agent-harness:start/end -->` |
| Agent hooks | `checks/turn_contract.py`, `branch_name_guard.py`, `commit_gate.py`, `codex_model_guard.py`, `korean_answer_check.py` | each adapter's `hooks_file` (UserPromptSubmit, PreToolUse, Stop, SubagentStop) |
| Git hooks | `githooks/_dispatch` + one link per hook name (gates on pre-commit, commit-msg, pre-push) | global `core.hooksPath` |
| Gate list | `checks/gates.py` | rendered guidance and turn contract |
| Project enrollment | `.harness/harness.json` (`gate`, `commands`), optional `.harness/contract.md` | written by `harness enroll` in the project |

`~/.agent-harness` is a link to this checkout; every deployed command uses that path, so
moving the checkout only needs the link updated.

## Adapters

`adapters/<name>.json` (files starting with `_` are templates) declares only what differs per
agent: `home` (detection), `global_file`, `project_file`, optional `project_pointer`,
`hooks_file`, `shell_matcher`, optional `settings` (top-level keys `apply` writes into
`hooks_file`, e.g. Claude's empty `attribution`, `language` and subagent `env`), and migration-only `legacy_hook_paths`, `legacy_blocks`,
`legacy_lines`. Adding an agent means adding one adapter file. An adapter with
`hooks_file: null` gets guidance that marks agent-only gates as not machine-checked; Git-layer
gates still apply to it. Hook scripts accept Codex (`exec_command`/`shell`, `cmd` list or
string) and Claude Code (`Bash`, `command` string) payloads and answer with
`hookSpecificOutput.permissionDecision`; an agent with another hook schema needs a shim.

## Ownership inside deployed files

apply owns only its own block and the hook entries it registered (matched by command path).
Other marker blocks (`<!-- name:start -->…<!-- name:end -->`, e.g. `llmwiki-*`) and other hook
entries are preserved byte-for-byte. Unmarked text outside blocks is preserved and reported by
doctor; `--adopt` drops it after it has been moved into `rules/` or a project. The first write
keeps the pre-harness original as `<file>.bak-agent-harness`. apply previews by default and
writes only with `--write`. An existing global `core.hooksPath` or a foreign `~/.agent-harness`
is never overwritten.

## Gates

- Commit: in an enrolled repository the worktree fingerprint (HEAD, tracked binary diff,
  untracked paths and contents) must match a PASS receipt written by `harness verify run`, which
  executes the configured commands itself. Receipts live in the Git directory, never committed.
- Force-push: denied by the agent hook everywhere; the Git layer denies non-fast-forward pushes
  in enrolled repositories.
- AI attribution in commit messages (`Co-Authored-By: Claude…`, "Generated with…"): the Git
  layer's commit-msg gate denies it in enrolled repositories.
- Codex Astra/Sol models older than `gpt-6.2` passed as a model argument: agent hook.
- `git commit --no-verify` and automatic `codex/`, `claude/`, `agent/` branch prefixes: agent hook.
- Exceptions require the same-command markers `HARNESS_VERIFY_OVERRIDE` and
  `HARNESS_USER_BRANCH_NAME`, asserted only for an explicit user request.
- All checks fail open when they cannot evaluate; unenrolled repositories are untouched.
- The turn contract prints nothing outside an enrolled repository.
- The Git dispatcher chains to the repository's own `.git/hooks/<name>`. A repository-local
  `core.hooksPath` (husky, `.githooks`) bypasses the Git layer; doctor and enroll report it.

## Task and Handoff tools (unchanged from v2)

`new-task`, `complete-task`, `handoff`, `cleanup-git` and `doctor.ps1` keep their v2 contracts:
explicit exact Git root, `docs/codex/tasks/active|completed/<id>`, record-consistency completion
checks that never execute Evidence commands, preview-first Git cleanup.

## Validation

```sh
pwsh -NoLogo -NoProfile -File ./scripts/check.ps1
```

`scripts/check.ps1` runs doctor (Core, Strict), Pester and the Python unit tests in sequence.
There is no GitHub Actions CI; run it locally before every PR and release tag.

Python code stays compatible with macOS `/usr/bin/python3` (3.9) and uses the standard library only.
