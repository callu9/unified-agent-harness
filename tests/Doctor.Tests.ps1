BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $doctor = Join-Path $repoRoot 'scripts/doctor.ps1'
    function Invoke-Doctor {
        param([string]$Path, [string[]]$Arguments = @())
        $output = & pwsh -NoLogo -NoProfile -File $doctor -Path $Path @Arguments 2>&1
        [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
    }
    function New-Project {
        $path = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory $path
        & git -C $path init --quiet -b main
        return $path
    }
    function New-CoreFixture {
        $path = New-Project
        foreach ($name in @('scripts', 'skills', 'templates', 'bin', 'checks', 'adapters', 'githooks', 'rules', 'VERSION', 'README.md', 'AGENTS.md', 'CHANGELOG.md', 'SPEC.md')) {
            Copy-Item -LiteralPath (Join-Path $repoRoot $name) -Destination $path -Recurse
        }
        return $path
    }
}
Describe 'doctor v2' {
    It 'passes Core Strict with one JSON document' {
        $result = Invoke-Doctor $repoRoot @('-Mode', 'Core', '-Strict', '-Json')
        $result.ExitCode | Should -Be 0
        $document = ($result.Output -join "`n") | ConvertFrom-Json
        $document.mode | Should -Be Core
        $document.exit_code | Should -Be 0
    }
    It 'requires an exact version tag only when requested' {
        $fixture = New-CoreFixture
        & git -C $fixture -c user.name=test -c user.email=test@example.com commit --quiet --allow-empty -m initial
        (Invoke-Doctor $fixture @('-Mode', 'Core', '-Strict')).ExitCode | Should -Be 0
        (Invoke-Doctor $fixture @('-Mode', 'Core', '-RequireVersionTag')).ExitCode | Should -Be 1
        $version = (Get-Content "$fixture/VERSION" -Raw).Trim()
        & git -C $fixture tag "v$version"
        (Invoke-Doctor $fixture @('-Mode', 'Core', '-RequireVersionTag')).ExitCode | Should -Be 0
    }
    It 'rejects missing source, invalid version, syntax and broken template structure' {
        foreach ($case in @('missing', 'version', 'syntax', 'template', 'skill')) {
            $fixture = New-CoreFixture
            switch ($case) {
                missing { Remove-Item "$fixture/scripts/new-task.ps1" }
                version { Set-Content "$fixture/VERSION" invalid }
                syntax { Set-Content "$fixture/scripts/new-task.ps1" 'function {' }
                template { Set-Content "$fixture/templates/TASK.md" '# Task' }
                skill { Set-Content "$fixture/skills/understanding-debt/SKILL.md" '# no frontmatter' }
            }
            (Invoke-Doctor $fixture @('-Mode', 'Core', '-Strict')).ExitCode | Should -Be 1 -Because $case
        }
    }
    It 'accepts a project without any harness artifacts' {
        $project = New-Project
        $result = Invoke-Doctor $project @('-Mode', 'Project', '-Strict')
        $result.ExitCode | Should -Be 0
        ($result.Output -join "`n") | Should -Not -Match 'bootstrap|VERSION|Skill:'
        Test-Path "$project/.codex-harness" | Should -BeFalse
    }
    It 'does not require or audit leftover legacy installation files' {
        $project = New-Project
        $null = New-Item -ItemType Directory "$project/.codex-harness"
        Set-Content "$project/.codex-harness/VERSION" '0.8.0'
        Set-Content "$project/AGENTS.md" 'Project owned guidance'
        (Invoke-Doctor $project @('-Mode', 'Project', '-Strict')).ExitCode | Should -Be 0
    }
    It 'reports missing or invalid active Task records without changing them' {
        $project = New-Project
        $task = "$project/docs/codex/tasks/active/legacy-task"
        $null = New-Item -ItemType Directory $task -Force
        (Invoke-Doctor $project @('-Mode', 'Project')).ExitCode | Should -Be 1
        Set-Content "$task/TASK.md" "---`nstatus: invalid`n---`n"
        (Invoke-Doctor $project @('-Mode', 'Project')).ExitCode | Should -Be 1
        (Get-Content "$task/TASK.md" -Raw) | Should -Match 'invalid'
    }
    It 'warns for incomplete review records and misplaced done Tasks' {
        foreach ($status in @('review', 'done')) {
            $project = New-Project
            $null = & pwsh -NoLogo -NoProfile -File "$repoRoot/scripts/new-task.ps1" -ProjectPath $project -Name Review -TaskId review
            $file = "$project/docs/codex/tasks/active/review/TASK.md"
            $text = (Get-Content $file -Raw).Replace('status: "draft"', "status: `"$status`"")
            [System.IO.File]::WriteAllText($file, $text)
            (Invoke-Doctor $project @('-Mode', 'Project')).ExitCode | Should -Be 0
            $result = Invoke-Doctor $project @('-Mode', 'Project', '-Strict', '-Json')
            $result.ExitCode | Should -Be 1
            (($result.Output -join "`n") | ConvertFrom-Json).diagnostics.Status | Should -Contain WARN
            [System.IO.File]::ReadAllText($file) | Should -BeExactly $text
        }
    }
    It 'checks only explicitly selected project branch policy' {
        $project = New-Project
        & git -C $project -c user.name=test -c user.email=test@example.com commit --quiet --allow-empty -m initial
        & git -C $project switch --quiet -c other/name
        $null = New-Item -ItemType Directory "$project/.codex-harness"
        Set-Content "$project/.codex-harness/branch-policy.json" '{"pattern":"^fix/[a-z]+$","types":["fix"],"ignored_patterns":["^main$"]}'
        (Invoke-Doctor $project @('-Mode', 'Project', '-Strict')).ExitCode | Should -Be 0
        (Invoke-Doctor $project @('-Mode', 'Project', '-Strict', '-CheckBranchPolicy')).ExitCode | Should -Be 1
        $result = Invoke-Doctor $project @('-Mode', 'Project', '-SuggestBranchRename', '-Type', 'fix')
        ($result.Output -join "`n") | Should -Match 'branch -m'
        (& git -C $project branch --show-current) | Should -Be 'other/name'
        Set-Content "$project/.codex-harness/branch-policy.json" '{invalid'
        (Invoke-Doctor $project @('-Mode', 'Project', '-Strict')).ExitCode | Should -Be 0
        (Invoke-Doctor $project @('-Mode', 'Project', '-CheckBranchPolicy')).ExitCode | Should -Be 1
    }
    It 'has no Core default when an opt-in project policy is absent' {
        $project = New-Project
        (Invoke-Doctor $project @('-Mode', 'Project', '-Strict', '-CheckBranchPolicy')).ExitCode | Should -Be 0
    }
}
