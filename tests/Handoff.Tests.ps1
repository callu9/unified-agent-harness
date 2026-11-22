BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $newTask = Join-Path $repoRoot 'scripts/new-task.ps1'
    $handoff = Join-Path $repoRoot 'scripts/handoff.ps1'
    $pwsh = 'pwsh'

    function New-TestProject {
        $project = Join-Path $TestDrive ('project-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $project
        & git -C $project init --quiet
        & git -C $project -c user.name=test -c user.email=test@example.com commit --allow-empty --quiet -m initial
        return $project
    }

    function New-ActiveTask {
        param([string]$ProjectPath, [string]$TaskId = 'handoff-task')
        $null = & $pwsh -NoLogo -NoProfile -File $newTask -ProjectPath $ProjectPath -Name 'Handoff task' -Skill feature-delivery -TaskId $TaskId
        if ($LASTEXITCODE -ne 0) { throw 'Task fixture setup failed.' }
        return Join-Path $ProjectPath "docs/codex/tasks/active/$TaskId"
    }

    function Invoke-Handoff {
        param([string]$ProjectPath, [string[]]$Arguments = @())
        $output = & $pwsh -NoLogo -NoProfile -File $handoff -ProjectPath $ProjectPath @Arguments 2>&1
        [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
    }
}

Describe 'handoff.ps1' {
    It 'records only Git status paths and optional diff stat while preserving manual text' {
        $project = New-TestProject
        $task = New-ActiveTask -ProjectPath $project
        $handoffPath = Join-Path $task 'HANDOFF.md'
        Add-Content -LiteralPath $handoffPath -Value "`nManual note: preserve this."
        [System.IO.File]::WriteAllText((Join-Path $project 'tracked.txt'), 'baseline')
        & git -C $project add tracked.txt
        & git -C $project -c user.name=test -c user.email=test@example.com commit --quiet -m tracked
        [System.IO.File]::WriteAllText((Join-Path $project 'tracked.txt'), 'top-secret-diff-content')
        [System.IO.File]::WriteAllText((Join-Path $project 'staged.txt'), 'staged')
        & git -C $project add staged.txt
        [System.IO.File]::WriteAllText((Join-Path $project 'untracked.txt'), 'untracked')

        $result = Invoke-Handoff -ProjectPath $project -Arguments @('-IncludeDiffStat', '-Summary', 'Resume safely')
        $content = [System.IO.File]::ReadAllText($handoffPath)

        $result.ExitCode | Should -Be 0
        $content | Should -Match 'Branch:'
        $content | Should -Match 'tracked.txt'
        $content | Should -Match 'staged.txt'
        $content | Should -Match 'untracked.txt'
        $content | Should -Match 'Diff stat'
        $content | Should -Match 'Manual note: preserve this.'
        $content | Should -Match 'Resume safely'
        $content | Should -Not -Match 'top-secret-diff-content'
        $content | Should -Not -Match 'diff --git'
    }

    It 'rejects zero or multiple active tasks instead of guessing' {
        $project = New-TestProject
        $none = Invoke-Handoff -ProjectPath $project
        $null = New-ActiveTask -ProjectPath $project -TaskId 'task-one'
        $null = New-ActiveTask -ProjectPath $project -TaskId 'task-two'
        $multiple = Invoke-Handoff -ProjectPath $project

        $none.ExitCode | Should -Be 1
        $multiple.ExitCode | Should -Be 1
        ($multiple.Output -join "`n") | Should -Match 'active'
    }

    It 'does not modify HANDOFF.md in WhatIf mode' {
        $project = New-TestProject
        $task = New-ActiveTask -ProjectPath $project
        $handoffPath = Join-Path $task 'HANDOFF.md'
        $before = [System.IO.File]::ReadAllText($handoffPath)

        $result = Invoke-Handoff -ProjectPath $project -Arguments @('-WhatIf', '-Summary', 'Preview only')

        $result.ExitCode | Should -Be 0
        [System.IO.File]::ReadAllText($handoffPath) | Should -Be $before
    }

    It 'rejects an absolute TaskPath outside the active task directory' {
        $project = New-TestProject
        $active = New-ActiveTask -ProjectPath $project
        $external = Join-Path $TestDrive ('external-task-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $external
        $handoffPath = Join-Path $external 'HANDOFF.md'
        Copy-Item -LiteralPath (Join-Path $active 'HANDOFF.md') -Destination $handoffPath
        $before = [System.IO.File]::ReadAllText($handoffPath)

        $result = Invoke-Handoff -ProjectPath $project -Arguments @('-TaskPath', $external, '-Summary', 'must not escape')

        $result.ExitCode | Should -Be 1
        [System.IO.File]::ReadAllText($handoffPath) | Should -Be $before
    }

    It 'rejects a relative TaskPath that escapes the project' {
        $project = New-TestProject
        $active = New-ActiveTask -ProjectPath $project
        $external = Join-Path (Split-Path -Parent $project) ('external-task-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $external
        $handoffPath = Join-Path $external 'HANDOFF.md'
        Copy-Item -LiteralPath (Join-Path $active 'HANDOFF.md') -Destination $handoffPath
        $before = [System.IO.File]::ReadAllText($handoffPath)
        $escapedPath = '../' + (Split-Path -Leaf $external)

        $result = Invoke-Handoff -ProjectPath $project -Arguments @('-TaskPath', $escapedPath, '-Summary', 'must not escape')

        $result.ExitCode | Should -Be 1
        [System.IO.File]::ReadAllText($handoffPath) | Should -Be $before
    }
}
