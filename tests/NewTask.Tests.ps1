BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $newTask = Join-Path $repoRoot 'scripts/new-task.ps1'
    $pwsh = 'pwsh'

    function New-TestProject {
        $project = Join-Path $TestDrive ('project-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $project
        & git -C $project init --quiet
        return $project
    }

    function Invoke-NewTask {
        param([string]$ProjectPath, [string]$Name, [string]$Skill, [string[]]$Arguments = @())

        $output = & $pwsh -NoLogo -NoProfile -File $newTask -ProjectPath $ProjectPath -Name $Name -Skill $Skill @Arguments 2>&1
        [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
    }
}

Describe 'new-task.ps1' {
    It 'creates TASK and HANDOFF with replaced metadata' {
        $project = New-TestProject
        $result = Invoke-NewTask -ProjectPath $project -Name 'Implement doctor flow' -Skill 'feature-delivery' -Arguments @('-TaskId', '20260807-120000-doctor-flow', '-Description', 'Doctor acceptance')
        $taskPath = Join-Path $project 'docs/codex/tasks/active/20260807-120000-doctor-flow/TASK.md'
        $handoffPath = Join-Path $project 'docs/codex/tasks/active/20260807-120000-doctor-flow/HANDOFF.md'

        $result.ExitCode | Should -Be 0
        Test-Path -LiteralPath $taskPath | Should -BeTrue
        Test-Path -LiteralPath $handoffPath | Should -BeTrue
        $task = [System.IO.File]::ReadAllText($taskPath)
        $task | Should -Match 'id: "20260807-120000-doctor-flow"'
        $task | Should -Match 'title: "Implement doctor flow"'
        $task | Should -Match 'skill: "feature-delivery"'
        $task | Should -Match 'Doctor acceptance'
        $task | Should -Not -Match '\{\{[A-Z0-9_]+\}\}'
    }

    It 'rejects malformed Skill metadata before creating a task' {
        $project = New-TestProject
        $result = Invoke-NewTask -ProjectPath $project -Name 'Nope' -Skill '../unsupported' -Arguments @('-TaskId', 'task-nope')

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'Skill'
        Test-Path -LiteralPath (Join-Path $project 'docs/codex/tasks/active/task-nope') | Should -BeFalse
    }

    It 'rejects an existing task ID without overwriting it' {
        $project = New-TestProject
        $first = Invoke-NewTask -ProjectPath $project -Name 'First' -Skill 'feature-delivery' -Arguments @('-TaskId', 'existing-task')
        $taskPath = Join-Path $project 'docs/codex/tasks/active/existing-task/TASK.md'
        $before = [System.IO.File]::ReadAllText($taskPath)
        $second = Invoke-NewTask -ProjectPath $project -Name 'Second' -Skill 'feature-delivery' -Arguments @('-TaskId', 'existing-task')

        $first.ExitCode | Should -Be 0
        $second.ExitCode | Should -Be 1
        [System.IO.File]::ReadAllText($taskPath) | Should -Be $before
    }

    It 'uses a stable non-empty fallback slug for a Korean-only name' {
        $project = New-TestProject
        $result = Invoke-NewTask -ProjectPath $project -Name '한글 작업' -Skill 'feature-delivery'
        $created = Get-ChildItem -LiteralPath (Join-Path $project 'docs/codex/tasks/active') -Directory

        $result.ExitCode | Should -Be 0
        $created.Count | Should -Be 1
        $created[0].Name | Should -Match '^\d{8}-\d{6}-task-[0-9a-f]{8}$'
    }

    It 'does not create a task in WhatIf mode' {
        $project = New-TestProject
        $result = Invoke-NewTask -ProjectPath $project -Name 'Preview' -Skill 'feature-delivery' -Arguments @('-TaskId', 'preview-task', '-WhatIf')

        $result.ExitCode | Should -Be 0
        Test-Path -LiteralPath (Join-Path $project 'docs/codex/tasks/active/preview-task') | Should -BeFalse
    }
}
