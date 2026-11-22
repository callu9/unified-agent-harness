BeforeAll { $repoRoot = Split-Path -Parent $PSScriptRoot }
Describe 'optional Skills' {
    It 'retains only specialized procedures without a workspace stop rule' {
        $skills = Get-ChildItem "$repoRoot/skills" -Directory
        @($skills.Name | Sort-Object) | Should -Be @('benchmark-approach', 'clarify-goal', 'compare-options', 'cross-repo-coordination', 'design-execution-routine', 'design-learning-plan', 'extract-actionable-insights', 'figma-fidelity', 'find-market-opportunities', 'frontend-polish', 'plan-from-outcome', 'stress-test-idea', 'understanding-debt')
        foreach ($skill in $skills) {
            $text = Get-Content (Join-Path $skill.FullName 'SKILL.md') -Raw
            $text | Should -Match ([regex]::Escape("name: $($skill.Name)"))
            $text | Should -Match 'description:'
            $text | Should -Not -Match 'Workspace Scope Guard|Outside that workspace|active Codex Harness user loader'
        }
    }
    It 'chooses cross-repository order by compatibility and rollback' {
        $text = Get-Content "$repoRoot/skills/cross-repo-coordination/SKILL.md" -Raw
        $text | Should -Match 'order from compatibility and rollback'
        $text | Should -Match 'consumer-first'
        $text | Should -Not -Match 'provider → consumer order'
    }
    It 'limits understanding-debt to explicit learning and recall' {
        $text = Get-Content "$repoRoot/skills/understanding-debt/SKILL.md" -Raw
        $text | Should -Match 'explicitly asks for learning or recall'
        $text | Should -Match 'only asks for an explanation'
        $text | Should -Match 'read-only'
        $text | Should -Match 'fact.*inference.*unverified'
        $text | Should -Match 'auto-confirm user understanding'
    }
}
