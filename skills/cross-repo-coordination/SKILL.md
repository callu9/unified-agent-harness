---
name: cross-repo-coordination
description: "공통 패키지, API, 또는 배포 순서처럼 여러 저장소가 함께 변할 때 사용한다. 단일 저장소 변경에는 사용하지 않는다. (cross repo)"
---
# Purpose
Coordinate cross-repository contracts.
## Use When
- Providers and consumers change together.
## Do Not Use When
- One repository can complete independently.
## Required Inputs
- Repository list and contract boundary.
## Workflow
1. Record each repository's branch, commit, working tree, and Task/HANDOFF state when those artifacts exist.
2. Build a compatibility and rollback matrix for every changed contract.
3. Choose the implementation and rollout order from compatibility and rollback conditions; a consumer-first expansion may be safer than provider-first removal.
4. Verify each repository and integration.
## Guardrails and Stop Conditions
- Do not assume remote state or push without approval.
## Required Artifacts
- Matrix, order, and evidence.
## Verification
- Verify individual and shared contracts.
## Completion Report
- Report state per repository.
