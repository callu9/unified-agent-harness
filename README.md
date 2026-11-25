# agent-harness

코딩 에이전트(Claude Code, Codex 등)에게 주는 **지침**, 그 지침 가운데 어겨선 안 되는 것을 기계로 강제하는 **게이트**,
필요할 때 꺼내 쓰는 **Skill**을 한 저장소에서 관리하고, 이 컴퓨터의 모든 에이전트에 같은 방식으로 적용하는 하네스입니다.
(GitHub 저장소 이름은 `unified-agent-harness`, 도구 이름과 설치 링크 이름은 `agent-harness`입니다.)

> **English summary.** agent-harness is a single source for the instructions, enforcement gates and optional skills that govern coding agents
> (Claude Code, Codex, ...) on one machine. `harness apply` renders agent-neutral rules into each agent's global instruction file and registers
> hooks and global Git hooks; one adapter file per agent holds the differences. Instructions an agent could ignore are promoted to gates where
> possible, for example: in an enrolled repository `git commit` is refused unless a PASS receipt written by `harness verify run` matches the exact
> worktree state. Python 3 standard library only; developed and tested on macOS. [SPEC.md](SPEC.md) is in English; this README is in Korean.

## 하네스가 관리하는 것

| 구성 | 위치 | 하는 일 |
|---|---|---|
| 지침 | `rules/*.md`, `templates/AGENTS.project.md` | 모든 프로젝트에 공통인 전역 규약 9개 파일과 프로젝트 지침 템플릿. `apply`가 에이전트별 전역 지침 파일에 렌더링 |
| 게이트 | `checks/`, `githooks/` | 지침 중 어겨선 안 되는 것(검증 없는 commit, force-push, AI 작성 표기 등)을 에이전트 hook과 전역 Git hook으로 강제 |
| Skill | `skills/` | 요청이 맞을 때만 쓰는 절차 묶음 14개(분석·계획 9, 구현 보조 3, 협업·학습 2). `apply`가 배포하지 않고 필요한 것만 직접 둠 |
| 어댑터 | `adapters/*.json` | 에이전트별 차이(지침 파일 위치, hook 설정 파일, shell tool 이름). 새 에이전트 = 파일 하나 |
| 프로젝트 등록 | `bin/harness enroll`, `.harness/harness.json` | 저장소마다 검증 명령을 정해 등록하고, `AGENTS.md`가 있으면 Claude용 `CLAUDE.md`(`@AGENTS.md`) 포인터를 만듦 |
| Task·Handoff 도구 | `scripts/*.ps1`, `templates/` | 선택. 작업 기록, 인수인계, 완료 확인, 병합된 브랜치 정리(PowerShell 7) |
| 점검·감사 | `harness doctor`, `harness audit` | 배포 상태를 이 저장소와 비교하고, Codex·Claude Code 로그에서 반복된 교정을 찾음 |

그 밖에 현재 계약은 [SPEC.md](SPEC.md), 변경 이력은 [CHANGELOG.md](CHANGELOG.md), 테스트는 `tests/`, 버전은 `VERSION`에 있습니다.

## 지침

`rules/`의 파일이 지침의 정본입니다. 에이전트 이름이 들어가지 않는 중립 문장으로 쓰고, `harness apply --write`가 감지된 에이전트마다
그 에이전트의 전역 지침 파일(예: Claude Code의 `~/.claude/CLAUDE.md`) 안에 `<!-- agent-harness:start/end -->` 블록으로 렌더링합니다.
다른 도구가 만든 마커 블록은 그대로 보존됩니다.

| 파일 | 지침 |
|---|---|
| `00-precedence` | 적용 순서: 사용자의 현재 지시 > 가장 가까운 프로젝트 지침(`AGENTS.md`) > 전역 규약 > 도구 기본값. 충돌하면 어느 규칙을 적용했는지 보고 |
| `10-reporting` | 실제 실행한 검증만 보고하고, 실행하지 않은 것은 `미검증`으로 씀. 위임한 에이전트의 보고는 확인한 사실·추측·사람이 정할 것으로 나눠 받음 |
| `20-scope` | 요청 범위를 넘지 않고 범위 밖 개선은 제안으로 남김. 무관한 변경을 보존하고 의존성을 임의로 추가하지 않음 |
| `25-analysis` | 원하는 결과와 제약을 먼저 파악하고, 결론을 좌우하는 전제·반례·실패 가능성을 확인하며, 계획은 완료 조건에서 역산 |
| `30-language` | 사용자에게 보이는 문장은 한국어 |
| `35-tools` | 작업 도구는 최신 버전을 유지하고 특정 버전을 요구 조건으로 쓰지 않음. 재시작이 필요한 업데이트는 사용자에게 요청하며, 사용자가 업무용 브라우저 프로필을 지정했을 때만 그 프로필에서 작업 |
| `40-git` | Git 작업 규칙: 하드 게이트 안내, 브랜치 이름, 브랜치·이슈 정리, PR |
| `45-documents` | 사용자에게 주는 업무 문서는 사용자가 정한 파일 이름 형식을 따름. 첫 버전 `v0.1`, 만든 날 날짜, 다른 날 수정은 새 버전 파일(코드·임시 파일 제외) |
| `50-promote-repeated` | 같은 교정을 두 번 받으면 일회성 지시가 아니라 규칙으로 보고, 기계로 검사할 수 있으면 게이트·스크립트·설정으로 올림 |

프로젝트별 지침은 프로젝트의 `AGENTS.md`가 맡습니다(시작용 템플릿: `templates/AGENTS.project.md`).
규칙 내용은 저장소 소유자의 작업 방식이라, 가져다 쓸 때는 `rules/`를 자기 규칙으로 고치고 `apply --write`하는 구조입니다.
배포된 파일의 블록은 손으로 고치지 않습니다.

## 게이트: 지침 중 어겨선 안 되는 것을 기계로 강제

지침은 에이전트가 놓치거나 무시할 수 있습니다. 그래서 `rules/50`의 원칙대로, 기계로 검사할 수 있는 것은 명령 실행 전에 막습니다.
가장 눈에 띄는 것이 **검증 영수증 게이트**입니다. 작업 저장소마다 검증 명령을 먼저 정해 두고, 그 명령이 실제로 돌아 PASS한 영수증이
현재 작업 트리와 맞을 때만 `git commit`을 허용합니다. 에이전트와 사람의 commit에 똑같이 적용됩니다.

임시 HOME의 샘플 저장소에서 실제로 실행한 출력입니다(검증 명령은 `echo tests pass` 한 줄만 둔 최소 예시).

```text
$ git commit -m "feat: add a"          # 검증 영수증 없음
agent-harness: commit blocked, verification receipt is MISSING. Run `harness verify run` first.

$ harness verify run
==> echo tests pass
tests pass

harness verify: PASS recorded for 4b857c757273

$ git commit -m "feat: add a"          # 영수증이 현재 작업 트리와 일치 → 통과

$ (파일을 더 고친 뒤) git commit -m "feat: more"
agent-harness: commit blocked, verification receipt is STALE. Run `harness verify run` first.

$ git commit -m "feat: more" -m "Co-Authored-By: Claude <noreply@anthropic.com>"   # 영수증은 새로 받은 상태
agent-harness: commit blocked, the message carries AI attribution: 'Co-Authored-By: Claude <noreply@anthropic.com>'. Remove it and commit again.
```

따라 해 보는 방법은 아래 [안전하게 해 보기](#안전하게-해-보기)에 있습니다.

| 층 | 위치 | 하는 일 |
|---|---|---|
| 에이전트 hook | `checks/` | 같은 스크립트가 Codex·Claude hook 입력을 모두 처리. 위험한 명령은 실행 전에 거부(PreToolUse), 매 턴 현재 게이트와 저장소 상태를 주입(UserPromptSubmit) |
| Git hook | `githooks/` | 전역 `core.hooksPath`. hook이 없는 에이전트와 사람의 commit에도 적용되는 바닥층 |
| 영수증 | `harness verify run` | 설정된 명령을 **직접 실행**하고, 끝났을 때 작업 트리 지문(HEAD, 추적 파일의 diff, 미추적 파일의 경로와 내용)과 함께 PASS/FAIL을 기록 |

저장소는 `.harness/harness.json`(`gate`, `commands`)이 있을 때만 등록됩니다. 등록하지 않은 저장소는 아무것도 달라지지 않습니다.

게이트 목록(자세한 계약은 [SPEC.md](SPEC.md)의 Gates):

- `git commit`: 현재 작업 트리와 일치하는 PASS 영수증이 필요합니다.
- force-push: 에이전트 hook이 어디서든 거부하고, Git 층은 등록 저장소의 non-fast-forward push를 거부합니다.
- commit 메시지의 AI 작성 표기(`Co-Authored-By: Claude…`, "Generated with…"): 등록 저장소에서 거부합니다.
- `git commit --no-verify`, 자동 `codex/`·`claude/`·`agent/` 브랜치 접두사: 에이전트 hook이 거부합니다.
- 모델 인자: 지정한 세대보다 오래된 Codex 모델 이름을 인자로 넘기는 명령을 거부합니다(개인 정책이며 `checks/codex_model_guard.py`에서 바꿉니다).
- 예외는 같은 명령 앞에 붙이는 `HARNESS_VERIFY_OVERRIDE`, `HARNESS_USER_BRANCH_NAME` 표시 변수뿐입니다.

### 설계 결정과 한계

- **프롬프트가 아니라 hook과 Git 층에서 막습니다.** 지침은 에이전트가 놓치거나 무시할 수 있지만, 명령 실행 전 hook과 Git hook은 그럴 수 없습니다. Git 층은 에이전트와 무관하므로 hook을 지원하지 않는 에이전트와 사람의 commit도 막습니다.
- **영수증은 `verify run`이 명령을 직접 실행해야만 생깁니다.** 에이전트가 "테스트 통과했다"고 쓰는 것으로는 만들 수 없습니다. 영수증에는 명령 문자열, 종료 코드, 소요 시간만 저장하고 로그·diff·환경값은 저장하지 않으며, Git 디렉터리 안에 두어 commit되지 않습니다. 검증 중 작업 트리가 바뀌면 영수증을 만들지 않습니다.
- **검사할 수 없으면 통과시킵니다(fail-open).** 판단하지 못하는 상황에서 정상 작업을 막지 않기 위해서입니다. 대신 이 도구는 방어 시스템이 아니라 실수 방지 장치입니다.
- **한계.** 영수증은 "명령이 이 작업 트리에서 실제로 돌았다"는 기록이지, 그 명령이 충분한 검증이라는 보증은 아닙니다. 표시 변수(`HARNESS_VERIFY_OVERRIDE`)는 에이전트가 "사용자가 명시적으로 허락했다"고 주장하는 표시일 뿐 독립적인 증명이 아닙니다. 전역 Git hook 대신 저장소 자체의 `core.hooksPath`(husky 등)를 쓰는 저장소는 Git 층을 우회하며, `doctor`와 `enroll`이 이를 알려 줍니다.


## Skill

Skill은 요청이 설명과 맞을 때만 쓰는 절차 묶음입니다. `harness apply`가 배포하지 않으며, 필요한 것만 직접 골라 둡니다([Skill 설치](#skill-설치)).

| 묶음 | Skill | 쓰는 때 |
|---|---|---|
| 분석·계획 (Codex·Claude Code 공통) | `clarify-goal` | 목표·대상·범위·완료 기준이 여러 가지로 해석되고 그 차이가 결과를 크게 바꿀 때 |
| | `compare-options` | 후보가 정해진 의사결정에서 대안을 비교하거나 우선순위에 맞는 선택지를 추천할 때 |
| | `benchmark-approach` | 이미 쓰는 접근법을 전문 기준이나 실무 관행, 비교 사례에 비춰 평가할 때 |
| | `stress-test-idea` | 아이디어·제안·계획의 약점, 반례, 숨은 전제, 실패 가능성을 검토할 때 |
| | `plan-from-outcome` | 목표 결과나 마감에서 역산해 여러 단계의 계획을 짤 때 |
| | `extract-actionable-insights` | 문서·기사·회의록·인터뷰에서 의사결정과 실행에 쓸 통찰과 근거를 뽑을 때 |
| | `find-market-opportunities` | 특정 산업·기술·고객군에서 놓치기 쉬운 사업 기회와 해결되지 않은 수요를 찾을 때 |
| | `design-learning-plan` | 특정 기술을 익히기 위한 학습 경로, 연습 과제, 복습 일정이 필요할 때 |
| | `design-execution-routine` | 반복 업무나 습관을 일정하게 실행할 루틴, 시작 신호, 점검 주기, 진척 지표가 필요할 때 |
| 구현 보조 | `before-after-report` | UI·API·동작 변경의 전후 비교 HTML 보고서를 만들 때(영향 분류, BEFORE·AFTER 표, 기술 상태와 검증 상태 분리, 제출 전 확인) |
| | `frontend-polish` | 웹 프론트 결과물을 깔끔한 레이아웃과 스타일에 맞춘 풍부한 모션으로 만들거나 다듬을 때 |
| | `figma-fidelity` | Figma 링크를 기준으로 UI를 구현·검증할 때(말단 노드 사양표와 계산된 스타일 측정표로 완료 판정) |
| 협업·학습 | `cross-repo-coordination` | 공통 패키지·API·배포 순서처럼 여러 저장소가 함께 변할 때(호환성과 롤백 조건으로 순서 결정) |
| | `understanding-debt` | 사용자가 명시적으로 요청한 학습·회상 연습 |

Codex는 `$<이름>`, Claude Code는 `/<이름>` 뒤에 요청을 붙여 호출하거나, 설명과 맞는 요청에서 자동으로 고릅니다.

## 안전하게 해 보기

`apply --write`는 감지된 모든 에이전트의 전역 지침 파일, hook 설정, `~/.agent-harness` 링크, **전역 git `core.hooksPath`**를 바꿉니다(처음 쓸 때 원본을 `<파일>.bak-agent-harness`로 보관). 먼저 임시 HOME에서 위 데모만 재현해 보세요. 이 방식은 전역 설정을 바꾸지 않습니다.

```sh
HARNESS=/path/to/unified-agent-harness          # 이 저장소를 clone한 경로
export HOME=$(mktemp -d)                       # 이 셸에서만 임시 HOME을 씁니다
mkdir demo && cd demo && git init -b main
git config user.name demo && git config user.email demo@example.invalid
"$HARNESS/bin/harness" enroll --repo . --apply -- "echo tests pass"
echo hi > a.txt && git add a.txt
git -c core.hooksPath="$HARNESS/githooks" commit -m "feat: add a"   # MISSING으로 차단
"$HARNESS/bin/harness" verify run
git -c core.hooksPath="$HARNESS/githooks" commit -m "feat: add a"   # 통과
```

실제로 쓰려면 먼저 미리보기를 확인합니다.

```sh
bin/harness apply                # 미리보기 (diff)
bin/harness apply --write        # 적용
bin/harness doctor --workspace ~/workspace   # 등록 저장소와 전역 설정 점검
```

- 규칙을 바꿀 때는 `rules/`를 고치고 `apply --write`합니다. 배포된 파일의 `<!-- agent-harness:start/end -->` 블록은 손으로 고치지 않습니다.
- 다른 도구의 마커 블록과 hook은 그대로 보존됩니다. 기존 전역 `core.hooksPath`나 다른 `~/.agent-harness`는 덮어쓰지 않습니다.
- Codex는 hook 명령이 바뀌면 신뢰를 다시 요구합니다. apply 후 Codex에서 hook 신뢰를 한 번 승인합니다.

## 요구사항과 검증 상태

- 런타임: Git과 macOS `/usr/bin/python3`(3.9, 표준 라이브러리만). PowerShell 7은 선택적 Task 도구와 저장소 검증(`scripts/check.ps1`)에만 씁니다.
- macOS에서 개발하고 검증했습니다. 다른 OS에서의 동작은 확인하지 않았습니다.
- 검증: `pwsh -NoLogo -NoProfile -File ./scripts/check.ps1`(doctor, Pester, Python unit test). Python 테스트만 돌리려면 `/usr/bin/python3 -m unittest discover -s tests/python`. GitHub Actions CI는 일부러 두지 않았고 PR 전에 로컬에서 실행합니다.
- 이 스냅샷에서 실제로 실행한 결과(2026-11-22, macOS): `scripts/check.ps1` 종료 코드 0, Pester 57개 통과·실패 0, Python unit test 18개 OK.

## 프로젝트 등록

```sh
bin/harness enroll --repo ../my-project                    # 미리보기
bin/harness enroll --repo ../my-project --apply -- "npm run lint" "npm test"
```

`.harness/harness.json`이 생기고, `AGENTS.md`가 있으면 Claude용 `CLAUDE.md`(`@AGENTS.md`) 포인터도 만듭니다.
명령을 생략하면 `package.json`의 lint/typecheck/test/build 스크립트를 씁니다. 등록 저장소에서는
`harness verify run`의 PASS 영수증 없이 commit할 수 없고, 매 턴 현재 상태가 주입됩니다.
프로젝트 계약 한 줄 요약은 `.harness/contract.md`에 둡니다(매 턴 주입, 700자까지).

## 배경

개인 장비용으로 쓰던 도구(이전 이름 `codex-harness-core`, v2.0.1까지)에서 v3.4.0 시점의 내용을 가져온 공개 스냅샷입니다.
개인 Orca 워커 흐름용 선택 Skill(`codex-workflow`)은 포함하지 않았고, 변경 이력은 [CHANGELOG.md](CHANGELOG.md)에 있습니다.

## 새 에이전트 추가

`adapters/_template.json` 을 복사해 `home`, `global_file`, `project_file` 을 채웁니다. hook을 지원하면
`hooks_file`, `shell_matcher` 도 채웁니다. hook 형식이 Codex·Claude와 다르면 `checks/` 앞에 변환 shim이 필요합니다.
hook이 없으면 렌더링된 지침에 "기계 검사되지 않음"이 표시되고 git 층 게이트만 적용됩니다.

## 선택적 도구

core clone의 스크립트를 **대상 Git 저장소의 정확한 루트**에 직접 실행합니다.
대상에는 설치 VERSION, 관리 AGENTS 블록, Skill 묶음이 필요하지 않습니다.
이 예시의 상대경로는 core checkout 기준입니다.

```powershell
pwsh -NoLogo -NoProfile -File ./scripts/new-task.ps1 `
  -ProjectPath ../my-project -Name 'API compatibility' -TaskId api-compatibility

# Skill은 선택적 메타데이터이며 설치·호출하지 않습니다. 팀 고유 이름도 허용합니다.
pwsh -NoLogo -NoProfile -File ./scripts/new-task.ps1 `
  -ProjectPath ../my-project -Name 'Team procedure' -Skill team-procedure

pwsh -NoLogo -NoProfile -File ./scripts/handoff.ps1 `
  -ProjectPath ../my-project -TaskPath docs/codex/tasks/active/api-compatibility `
  -IncludeDiffStat -Summary 'Resume at compatibility verification'

pwsh -NoLogo -NoProfile -File ./scripts/complete-task.ps1 `
  -ProjectPath ../my-project -TaskPath docs/codex/tasks/active/api-compatibility `
  -ShowEvidenceTarget

pwsh -NoLogo -NoProfile -File ./scripts/complete-task.ps1 `
  -ProjectPath ../my-project -TaskPath docs/codex/tasks/active/api-compatibility -WhatIf
```

Task는 필요한 작업에서만 만듭니다. 기존 `docs/codex/tasks/active/<id>`와
`completed/<id>`, TASK/HANDOFF 및 Decisions 형식은 유지하며 기록을 마이그레이션하지
않습니다. Task가 여러 개면 `-TaskPath`로 고릅니다. 절대·외부·중첩·linked Task
경로와 linked 쓰기 경로는 거부합니다. 쓰기 도구는 `-WhatIf`를 지원합니다.

완료 도구는 status, 체크된 Acceptance Criteria, 순차 `V1: 설명` 검증 계획,
정확히 대응하는 최신 PASS Evidence, 현재 working-tree 지문을 검사하고 Task를
completed로 옮깁니다. `-ShowEvidenceTarget`의 값을 최신 PASS record에 기록합니다.
이후 대상 파일이 바뀌면 검증을 다시 실행하고 지문을 갱신해야 합니다.
**이 검사는 기록 정합성 검사입니다. Evidence의 command를 실행하거나 PASS의
진실성·운영 효과를 증명하지 않습니다.** 실제 검증은 작업자가 별도로 실행합니다.

Handoff는 Git 경로·상태·선택적 diff stat만 기록하며 파일 본문과 diff 본문을
수집하지 않습니다. `templates/DECISIONS.md`와 PR template도 필요한 프로젝트가
선택해 생성하는 자료입니다. 어떤 도구도 이 파일들을 자동 생성하지 않습니다.

## Skill 설치

필요한 Skill 하나만 검토해서 사용자 또는 프로젝트 Skill 위치에 둘 수 있습니다.
같은 이름의 기존 Skill이 있으면 보존하고 출처를 확인합니다. 자동 installer와
workspace 제한 loader는 없습니다. 일반 기능·버그·리뷰 절차는 프로젝트가 이미
쓰는 도구를 사용하며 Superpowers를 비롯한 다른 Skill 묶음은 필수 의존성이 아닙니다.

## 진단과 프로젝트 정책

```powershell
pwsh -NoLogo -NoProfile -File ./scripts/doctor.ps1 -Mode Core -Path . -Strict
pwsh -NoLogo -NoProfile -File ./scripts/doctor.ps1 -Mode Project -Path ../my-project -Strict
pwsh -NoLogo -NoProfile -File ./scripts/doctor.ps1 `
  -Mode Project -Path ../my-project -CheckBranchPolicy -SuggestBranchRename -Type fix
```

Project doctor는 선택적 Task 기록을 읽습니다. 하네스가 없는 프로젝트도 정상입니다.
설치 버전이나 공통 지침·Skill 존재를 검사하지 않고 재설치를 권하지 않습니다.
완료 gate의 전체 지문 검사는 `complete-task`가 수행합니다.

기계 검증이 필요한 팀만 `.codex-harness/branch-policy.json`을 직접 관리하고
`-CheckBranchPolicy`를 지정합니다. `-SuggestBranchRename`도 검사를 선택합니다.
기본 정책이나 자연어 정책 파서는 없습니다. 예시:

```json
{
  "pattern": "^(feat|fix)/[a-z0-9]+(?:-[a-z0-9]+)*$",
  "types": ["feat", "fix"],
  "ignored_patterns": ["^main$"]
}
```

doctor는 명령을 제안할 뿐 branch를 바꾸거나 push하지 않습니다.

## 명시적 Git 정리

```powershell
pwsh -NoLogo -NoProfile -File ./scripts/cleanup-git.ps1 -RepositoryPath . -BaseBranch main
pwsh -NoLogo -NoProfile -File ./scripts/cleanup-git.ps1 -RepositoryPath . -BaseBranch main -Apply
```

기본은 후보 출력입니다. Apply도 base/current branch와 worktree, primary,
detached, locked, dirty, unmerged 상태를 보호하고 force 삭제를 하지 않습니다.

## 저장소 검증과 버전

```sh
pwsh -NoLogo -NoProfile -File ./scripts/check.ps1
```

`scripts/check.ps1`은 doctor(Core, Strict), Pester, Python unittest를 차례로 실행합니다.
Pester 5.7.1 이상이 설치되어 있어야 합니다(`Install-Module Pester -MinimumVersion 5.7.1 -Scope CurrentUser`).
GitHub Actions CI는 없으며, PR 전과 release tag 전에 이 명령을 로컬에서 실행합니다.
release tag는 추가로 `./scripts/doctor.ps1 -Mode Core -Path . -Strict -RequireVersionTag`로 확인합니다.
VERSION은 이 저장소 계약의 SemVer입니다.
