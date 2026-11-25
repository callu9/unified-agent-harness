# agent-harness

## Purpose and map

This repository is the single source for personal agent guidance and gates (v3.5.0).
`bin/harness apply --write` deploys it to every agent with an adapter; nothing deploys on checkout.

- rules/: agent-neutral global rules rendered into each agent's global instruction file.
- adapters/: per-agent file locations and hook settings; one JSON file per agent.
- checks/: hook and gate logic shared by all agents (Python 3.9 standard library).
- githooks/: global Git hook dispatcher, the agent-independent gate floor.
- bin/harness: apply, doctor, enroll, verify, audit.
- templates/, scripts/, skills/: project guide template, optional PowerShell Task tools, optional Skills.
- SPEC.md: current public contract. CHANGELOG.md and Git history: prior contracts.

## Maintenance rules

- Read SPEC.md before changing contracts; update VERSION, CHANGELOG and SPEC together.
- Keep rules/ free of agent names, absolute personal paths and project-specific policy.
- Agent differences belong in adapters/, never as branches inside checks/ or rules/.
- Deploy (`apply --write`, `enroll --apply`) only when the user asks; preview first.
- Preserve other tools' marker blocks and hook entries in deployed files.
- Use temporary fixtures in tests; never touch the real home directory from tests.

## Validation

Run `pwsh -NoLogo -NoProfile -File ./scripts/check.ps1` (doctor, Pester and Python unit tests;
there is no GitHub Actions CI) before completion.
