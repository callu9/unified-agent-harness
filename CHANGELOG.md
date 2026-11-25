# Changelog

All notable changes follow Semantic Versioning.

> **Public snapshot.** This repository starts from the v3.4.0 tree of a private repository. The optional `codex-workflow` skill (a personal Orca orchestration flow) is not included, and the 3.3.x entries below are rewritten to describe only what ships here. Earlier entries are kept as written.

## 3.5.0

- Add `rules/35-tools.md`: keep work tools (agent CLIs and apps) on their latest version, never write a specific version as a requirement in guidance, issues, task specs or reports (a version appears only as evidence of what ran), ask the user to restart for updates that need it when no work is running and never restart on the agent's own, and, only when the user's guidance names a work browser profile, work in that profile alone and report a different connected profile instead of proceeding. This also restores the no-pinned-versions rule that the 3.3.0 entry described but `rules/` no longer contained.
- Add `rules/45-documents.md`: work documents handed to the user follow the file-name format the user's own guidance defines (suffix placeholder `_v<version>_YYYYMMDD_<author>`); first version `v0.1`, the date is the creation day, a file holds only its own day's content and a later change is a new file copied from the latest with the next version and that day's date; code, repository files and scratch files are excluded.
- `rules/25-analysis.md`: UI work that must match a design source is judged complete by a measured comparison of computed styles and positions, never by eye or a scaled-down screenshot; Figma links follow the `figma-fidelity` skill.
- Add the optional `before-after-report` skill: a before-and-after HTML report with an overview, impact classification (affected, conditional, not affected, unconfirmed), issue cards (problem, why it matters, fix or direction), BEFORE/AFTER tables with the evidence environment, same-region crops with originals, separate technical status and verification status, open/closed detail cards, row-to-detail links and a pre-submission checklist, with an `assets/issue-card.html` markup example.

## 3.4.0

- Add `rules/25-analysis.md`: find the wanted outcome and constraints first and ask only when unknowns change the result; check the premises, counterexamples and failure paths that decide a conclusion, separating checked facts from assumptions; plan multi-step work backwards from the completion condition.
- Add nine optional analysis and planning skills shared by Codex and Claude Code: `benchmark-approach`, `clarify-goal`, `compare-options`, `design-execution-routine`, `design-learning-plan`, `extract-actionable-insights`, `find-market-opportunities`, `plan-from-outcome`, `stress-test-idea`.

## 3.3.1

- `codex_model_guard` inspects an argv list as one command string and drops the per-launcher `-c` parsing that kept leaving bypasses (`bash --norc -c`, `env bash -c`, `pwsh -Command`, `sh -c 'exec "$@"'`); deliberate trade-off: a prompt argument that quotes an old `--model` value is now denied.
- `git_gate` blocks AI trailers only by tool form: noreply/bot addresses at anthropic.com or openai.com, any `Co-authored-by` with a `<id>+Copilot@users.noreply.github.com` address, and AI names in a GitHub `[bot]` login only as a whole name unit (`claude[bot]`, `openai-codex[bot]` blocked; `codexml-validator[bot]` passes). A human's GitHub private-email trailer commits.
- The PR role rule in `rules/40-git.md` keeps only agent-neutral invariants.

## 3.3.0

- `rules/40-git.md` replaces "Claude Code implements, Codex reviews" with an implementer/reviewer split: findings go to the implementer, not GitHub; the user merges unless repository rules allow otherwise. Tool versions are never pinned as requirements.
- Add the optional `frontend-polish` skill: clean layout with motion as rich as the page style carries, reduced-motion support, and delegation at Opus 5.5 / Fable 5.2 with effort max.
- The Claude adapter also sets `language: korean` and `env.CLAUDE_CODE_SUBAGENT_MODEL`.
- Review fixes: adapter `settings` merge dict values one level deep (existing `env` keys survive); `git_gate` matches AI trailers by tool form and reads only `.harness/harness.json` for commit-msg; the dispatcher runs the repository's commit-msg hook before the harness check; `codex_model_guard` inspects launcher segments only and argument tokens (newlines split commands).


## 3.2.0

- `rules/10-reporting.md`: take and pass on delegated reports (reviewers, subagents, peer AIs) split into checked facts with evidence and who checked them, guesses, and decisions for humans. An unrun test, a confident claim or two agents agreeing is not evidence.
- `rules/40-git.md`: Codex review runs on `gpt-6.2-astra`. Commit messages and PR bodies carry no AI attribution, overriding any attribution prompt from the runtime.
- Add a commit-msg gate to the Git layer: enrolled repositories reject `Co-Authored-By` trailers naming an AI and "Generated with/by <AI>" lines.
- Add `checks/codex_model_guard.py`, a PreToolUse gate that denies commands passing an Astra/Sol model older than `gpt-6.2` (`--model`, `model=`, or `-m` in a codex command); `rules/40-git.md` pins Astra and Sol to `gpt-6.2-astra` and `gpt-6.2-sol`.
- Adapters may declare `settings`, top-level keys `apply` writes into `hooks_file`; the Claude adapter sets `attribution` to empty strings.
- Add the optional `figma-fidelity` skill: read Figma down to leaf nodes, hand off a node spec table, and call UI work done only with a measured comparison table.

## 3.1.0

- Add `checks/korean_answer_check.py`, registered for every adapter on Stop and SubagentStop: when an answer is mostly English (Hangul under 60% of letters outside code, URLs and paths), it asks once for a Korean rewrite. Fails open and never blocks twice in a turn. The threshold is measured — healthy answers run 62-100% Hangul, half-English ones 36-50%.
- `rules/30-language.md`: every user-visible line, including progress notes and question cards, is Korean even when tool output is English.
- `rules/20-scope.md`: carry a requested outcome through to a verified result without asking to continue; keep long JSON, diffs and logs out of the conversation.
- `rules/40-git.md`: never delete or rename default branches during cleanup; after a merge, close the issue only when no follow-up remains; delete branches with `-d` only.

## 3.0.2

- `rules/40-git.md`: when Codex review fails because of an outage (connection errors, failed reconnects, `workspace routing discovery timed out`), run the same review with a Claude Code subagent and note the Codex error and the substitute review in the PR comment.

## 3.0.1

- Replace GitHub Actions CI with local verification: `scripts/check.ps1` runs doctor (Core, Strict), Pester and the Python unit tests and fails when Pester 5.7.1+ or Python cannot be loaded. `.harness/harness.json` runs it as the single verification command; release tags are checked locally with `doctor.ps1 -RequireVersionTag`. Hosted runners no longer check PRs on Windows/Ubuntu or release tags on Windows/macOS/Ubuntu.
- Add a PR section to `rules/40-git.md`: turn on PR monitoring without asking, route implementation to Claude Code and PR review to Codex `gpt-6-astra`, and record local verification results in the PR body.
- Document the Pester 5.7.1+ prerequisite in the README.

## 3.0.0

- Breaking: rename to `agent-harness` and make this repository the live source for global rules and gates across agents. `bin/harness apply` renders `rules/` into every detected adapter (`adapters/codex.json`, `adapters/claude.json`), registers the shared hooks and links `~/.agent-harness`; it previews by default and preserves other tools' marker blocks and hooks.
- Move the hand-built Codex hooks (turn contract, commit gate, branch guard), verification receipts and repeated-correction audit into `checks/`. Enrollment moves from `.codex/verify.json`/`.codex/contract.md` to `.harness/harness.json`/`.harness/contract.md`; override markers become `HARNESS_VERIFY_OVERRIDE` and `HARNESS_USER_BRANCH_NAME`; `claude/` joins the rejected automatic branch prefixes.
- Add a global Git hook dispatcher that enforces the commit receipt and blocks non-fast-forward pushes in enrolled repositories for any agent or manual commit, chaining to each repository's own hooks.
- The turn contract stays silent outside enrolled repositories. The audit reads Claude Code logs as well as Codex logs.
- Replace `templates/AGENTS.global.md` with `rules/` and `CODEX_HARNESS_CORE_BUILD_SPEC.md` with `SPEC.md`.
- Remove the v1 removal tools `detach-project.ps1` and `remove-user-hook.ps1`; v1 artifacts are removed directly and the tools remain at tag v2.0.1.

## 2.0.1

- Recognize Windows directory separator variants of the exact legacy release checkout hook during detach; preserve relative, case-different and unrelated hook paths.
- Fix hidden worktree `.git` fixture writes and run link protection tests on Windows, using directory junctions and file symbolic links instead of skipping the platform.
- Run doctor and Pester on Windows and Ubuntu for every PR, retaining the three-platform release-tag checks.

## 2.0.0

- Breaking: remove project bootstrap, Copy/Reference distribution, release updater, loader, and SessionStart/checkout/login installers. Existing installations are not changed by upgrading this source checkout.
- Separate a short personal global guidance example from project-owned guidance. Remove mandatory feature/bug/review Skill routing and keep cross-repository coordination and learning/recall as optional Skills with no workspace restriction.
- Run Task creation, completion and Handoff directly against an explicit Git root without installed VERSION, managed AGENTS, or bundled Skills. Preserve existing Task and evidence formats; completion checks records, never executes their commands.
- Make branch-policy diagnostics explicitly opt-in and project-owned, with no Core default.
- Preserve unknown or modified legacy Skills and guidance during preview-first detach; compare actual root names and entire Skill trees byte-for-byte against an explicitly supplied installation source. Remove only the exact legacy SessionStart command from user hook groups.
- Protect base/current secondary worktrees before Git cleanup and reject linked write paths, including raw Git references before collapsing `..`, Git-resolved metadata and local config before detach removes files. Preserve normal worktree support.

## 1.0.0

- Limit automatic Copy installation, workspace rollout, and Sync doctor to explicitly enrolled Git repositories and their worktrees. An absent or empty `managed_repositories` list enrolls none.
- Stop installing a PR template and shared checkout hook by default; expose explicit bootstrap switches for each. Create Task directories only when a Task needs them.
- Route the optional checkout hook through scoped local sync, and add preview-first `detach-project.ps1` to remove unmodified harness files and managed hook configuration after de-enrollment while preserving project content.

## 0.8.0

- Share exact Copy distribution integrity checks across bootstrap and both doctor modes, including managed guidance and Core Skill bodies; report override shadowing without claiming runtime application.
- Route Reference loader and SessionStart hook through the effective Codex home, validate loader integrity, and register SessionStart for startup, resume, clear, and compact.
- Separate local Copy readiness from remote update state and emit bounded structured SessionStart context while preserving fail-open startup behavior.
- Require sequential Verification Plan IDs and exact latest Evidence ID coverage before Task completion; document active Task migration.
- Make Core Skill routing explicitly invoke the matching `$skill-name`.

## 0.7.6

- Accept `feature/` in the core fallback branch policy and preserve explicitly requested branch names.

## 0.7.5

- Reduce GitHub Actions usage by running doctor and Pester on one Ubuntu job for pull requests, while keeping the Windows/macOS/Ubuntu compatibility matrix and single Ubuntu release-tag verification for `v*` tags.

## 0.7.4

- Automatically bootstrap a newly created linked Git worktree through a managed shared `post-checkout` hook in Copy mode.
- Preserve projects with existing Git hooks or a configured `core.hooksPath`; they continue to require explicit workspace bootstrap.

## 0.7.3

- Make the originator responsible for resolving delegated work to a stable target, receiving its result, independently verifying acceptance, and reporting inline in the originating conversation.
- Separate local, synthetic, connected-system, operational-effect, and achieved-goal evidence without requiring Tasks for trivial work.

## 0.7.2

- Include every live registered Git worktree when explicitly bootstrapping a workspace, with aggregate rollout counts and read-only preview.
- Make Copy-mode Sync doctor fail when any direct-child repository or registered worktree is missing or differs from the active release.

## 0.7.1

- Seed new projects with a concise GitHub PR template and direct agents to keep PR descriptions to the change summary and executed verification.
- Preserve repository-owned PR templates during bootstrap and validate the template source in Core doctor.

## 0.7.0

- Automatically bootstrap the current local Git project on every Codex SessionStart in Copy mode, including projects registered outside the configured workspace and nested repositories.
- Stop automatically modifying inactive workspace repositories when a release is activated; keep workspace-wide bootstrap as an explicit command.
- Require bootstrap targets to be exact Git roots and active Task paths to be direct project-relative children.
- Bind completion evidence to a deterministic working-tree SHA-256 fingerprint so later changes invalidate PASS records.
- Restore mandatory bug-investigation, PR-review, and cross-repository coordination procedures.
- Remove the no-op `ForceManagedFiles` switch and replace historical implementation plans with the concise current contract.

## 0.6.0

- Enforce evidence-backed Task completion through stronger feature-delivery guidance, structured Task evidence, read-only Project doctor diagnostics, and a safe complete-task command.

## 0.5.1

- Strengthen the understanding-debt Skill with evidence-based explanation inputs, flow tracing, recall criteria, evidence-layer separation, and read-only guardrails.

## 0.5.0

- Add explicit preview/apply cleanup for merged local branches and their clean secondary worktrees.
- Document GitHub-native automatic deletion of merged pull-request branches.

## 0.4.1

- Fix first-time SessionStart hook installation when `hooks.json` does not exist.

## 0.4.0

- Add stable-tag automatic synchronization with TTL, locking, detached release worktrees, validation, and rollback-safe activation.
- Keep Windows on verified per-project Copy mode and add macOS user-level Reference mode through an active-release loader and Skill symlinks.
- Add Codex SessionStart and optional Windows Task Scheduler or macOS launchd login triggers.
- Add read-only Sync diagnostics and explicit project-over-core instruction precedence.
- Reject linked workspace targets and unverified CoreRoot paths, keep sync previews read-only, and atomically switch managed release pointers.
- Diagnose active release structure, state, locks, Reference links, user Skill links, and stale project-local Skill copies.
- Render the effective project-first branch policy into installed `AGENTS.md` before branch creation or rename.
- Remove unresolved project placeholders and make active-task guidance conditional.
- Default the cross-platform sync example to Copy mode and keep Reference mode opt-in.
- Add optional `doctor -Mode Core -RequireVersionTag` release verification and tag-only CI enforcement.

## 0.3.0

- Add direct-child Git repository discovery and workspace-wide harness bootstrap.
- Make repository-owned and nearer nested instructions explicitly override core defaults.

## 0.2.0

- Add project-overridable branch policy diagnostics and read-only rename command suggestions to doctor.

## 0.1.0

- Initial Codex harness core.
