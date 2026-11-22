---
name: understanding-debt
description: "특정 변경을 학습하고 회상 연습을 요청할 때 사용한다. 일반 설명 요청에는 사용하지 않는다. 개인 업무일지나 자동 수집에는 사용하지 않는다. (understanding debt)"
---
# Purpose
Explain one selected change from evidence without changing it.
## Use When
- A user explicitly asks for learning or recall practice on one change.
## Do Not Use When
- The request only asks for an explanation, or collects personal activity or work logs.
## Required Inputs
- Selected change unit.
- Actual code or PR diff.
- At least one caller or result consumer.
- Code, test, or run evidence showing the failing input and the before-and-after result.
## Workflow
1. Fix the selected change unit and cite the evidence used.
2. State one likely initial misconception; label it as inference unless evidence or the user confirms it.
3. Trace the actual input, state, and data flow through at least one caller or result consumer.
4. Identify the failure point and explain the failure mechanism from code, test, or run evidence.
5. Compare the same failing input before and after the change.
6. Explain at most one directly useful CS or SE concept and one counterexample or boundary where it does not apply.
7. Ask one recall question before concluding. State the evidence criterion that a correct answer must include.
8. Give one narrow, runnable verification procedure for the explained behavior.
9. List the evidence checked and the remaining unverified scope.
## Guardrails and Stop Conditions
- Separate facts, inferences, and unverified claims.
- Treat UI, API, DB, Runner, and deployment as separate evidence layers; do not use one layer as proof for another.
- If evidence is insufficient, mark the item `학습 후보/근거 부족`.
- Do not invent flow, cause, or concepts from PR titles or file lists alone.
- Do not auto-confirm user understanding.
- Treat explanation requests as read-only.
- Do not make code changes or write external records unless explicitly requested.
## Required Artifacts
- Evidence map, explanation, one recall question, one verification procedure, and unverified scope.
## Verification
- Tie every flow, failure, before-and-after, and concept claim to the required evidence.
- Report whether the narrow procedure was executed or only proposed.
## Completion Report
- State the change, evidence, explanation, recall question, verification result, and unverified scope.
