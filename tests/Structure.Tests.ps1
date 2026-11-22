BeforeAll { $repoRoot = Split-Path -Parent $PSScriptRoot }
Describe 'v2 source contracts' {
    It 'removes automatic distribution entry points and defaults' {
        foreach ($path in @('scripts/bootstrap.ps1', 'scripts/bootstrap-workspace.ps1', 'scripts/sync-core.ps1', 'scripts/dispatch-active.ps1', 'scripts/install-user-profile.ps1', 'scripts/install-device-trigger.ps1', 'scripts/hooks/session-start.ps1', 'scripts/hooks/post-checkout', 'scripts/lib/CodexHarness.Sync.psm1', 'defaults/branch-policy.json', 'templates/AGENTS.core.md', 'templates/AGENTS.user-loader.md')) {
            Test-Path (Join-Path $repoRoot $path) | Should -BeFalse -Because $path
        }
    }
    It 'keeps version, public specification and repository guidance in agreement' {
        $version = (Get-Content "$repoRoot/VERSION" -Raw).Trim()
        $version | Should -Match '^3\.\d+\.\d+$'
        (Get-Content "$repoRoot/CHANGELOG.md" -Raw) | Should -Match ([regex]::Escape("## $version"))
        (Get-Content "$repoRoot/SPEC.md" -Raw) | Should -Match ([regex]::Escape("v$version"))
        (Get-Content "$repoRoot/AGENTS.md" -Raw) | Should -Match ([regex]::Escape("v$version"))
    }
    It 'keeps personal defaults separate from project-owned guidance' {
        $global = (Get-ChildItem "$repoRoot/rules" -Filter '*.md' | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"
        $project = Get-Content "$repoRoot/templates/AGENTS.project.md" -Raw
        $global | Should -Not -Match 'Skill Routing|Installed core|branch-policy|loader|/Users/'
        $project | Should -Not -Match 'codex-harness-core:start|CORE_VERSION|CORE_DEFAULTS|SessionStart'
        $project | Should -Match 'Build and verification'
        $project | Should -Match 'Team policies and domain constraints'
    }
    It 'preserves Task evidence fields and Handoff markers' {
        $task = Get-Content "$repoRoot/templates/TASK.md" -Raw
        foreach ($field in @('Check', 'Command / Scenario', 'Result', 'Target Commit / Diff', 'Environment', 'Verified At', 'Verified By', 'Limitations')) {
            $task | Should -Match ([regex]::Escape("- ${field}:"))
        }
        $handoff = Get-Content "$repoRoot/templates/HANDOFF.md" -Raw
        $handoff | Should -Match '<!-- codex-harness:snapshot:start -->'
        $handoff | Should -Match '<!-- codex-harness:snapshot:end -->'
    }
}
