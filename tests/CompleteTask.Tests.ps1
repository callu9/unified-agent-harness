BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $newTask = Join-Path $repoRoot 'scripts/new-task.ps1'
    $completeTask = Join-Path $repoRoot 'scripts/complete-task.ps1'
    Import-Module (Join-Path $repoRoot 'scripts/lib/CodexHarness.psm1') -Force -DisableNameChecking
    $pwsh = 'pwsh'

    function New-TestProject {
        $project = Join-Path $TestDrive ('project-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $project
        & git -C $project init --quiet
        return $project
    }

    function New-ReviewTask {
        param(
            [string]$ProjectPath,
            [string]$TaskId = 'review-task',
            [string]$Acceptance = '- [x] Acceptance verified',
            [string]$Verification = '- [x] V1: Focused test passed',
            [string]$Evidence = @'
### Verification Record

- Check: V1
- Command / Scenario: pwsh -Command test
- Result: PASS
- Target Commit / Diff: working tree diff
- Environment: PowerShell 7 test fixture
- Verified At: 2026-09-02T00:00:00Z
- Verified By: test
- Limitations: fixture only
'@
        )

        $null = & $pwsh -NoLogo -NoProfile -File $newTask -ProjectPath $ProjectPath -Name 'Review task' -Skill feature-delivery -TaskId $TaskId
        if ($LASTEXITCODE -ne 0) { throw 'Task fixture setup failed.' }
        $taskDirectory = Join-Path $ProjectPath "docs/codex/tasks/active/$TaskId"
        $taskPath = Join-Path $taskDirectory 'TASK.md'
        $content = [System.IO.File]::ReadAllText($taskPath)
        $content = $content.Replace('status: "draft"', 'status: "review"')
        $content = [regex]::Replace($content, '(?s)(## Acceptance Criteria\s*).*?(\s*## Verification Plan)', "`$1$Acceptance`n`$2", 1)
        $content = [regex]::Replace($content, '(?s)(## Verification Plan\s*).*?(\s*## Execution Log)', "`$1$Verification`n`$2", 1)
        $content = [regex]::Replace($content, '(?s)(## Evidence\s*).*?(\s*## Open Questions)', "`$1$Evidence`n`$2", 1)
        [System.IO.File]::WriteAllText($taskPath, $content)
        if ($Evidence -match '(?m)^- Target Commit / Diff: working tree diff$') {
            $null = Set-CurrentEvidenceTarget -ProjectPath $ProjectPath -TaskDirectory $taskDirectory
        }
        return $taskDirectory
    }

    function Set-CurrentEvidenceTarget {
        param([string]$ProjectPath, [string]$TaskDirectory)
        $taskPath = Join-Path $TaskDirectory 'TASK.md'
        $target = Get-CodexHarnessWorkingTreeFingerprint -RepositoryPath $ProjectPath -TaskPath $taskPath
        $content = [System.IO.File]::ReadAllText($taskPath)
        $content = [regex]::Replace($content, '(?m)^- Target Commit / Diff:[^\r\n]*$', "- Target Commit / Diff: $target")
        [System.IO.File]::WriteAllText($taskPath, $content)
        return $target
    }

    function Invoke-CompleteTask {
        param([string]$ProjectPath, [string[]]$Arguments = @())
        $output = & $pwsh -NoLogo -NoProfile -File $completeTask -ProjectPath $ProjectPath @Arguments 2>&1
        [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
    }
}

Describe 'complete-task.ps1' {
    It 'marks a verified review task done and moves the whole directory to completed' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project
        [System.IO.File]::WriteAllText((Join-Path $active 'manual.txt'), 'preserve me')
        $null = Set-CurrentEvidenceTarget -ProjectPath $project -TaskDirectory $active

        $result = Invoke-CompleteTask -ProjectPath $project
        $completed = Join-Path $project 'docs/codex/tasks/completed/review-task'

        $result.ExitCode | Should -Be 0
        Test-Path -LiteralPath $active | Should -BeFalse
        Test-Path -LiteralPath $completed | Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path $completed 'TASK.md')) | Should -Match 'status: "done"'
        [System.IO.File]::ReadAllText((Join-Path $completed 'manual.txt')) | Should -Be 'preserve me'
    }

    It 'rejects unchecked acceptance criteria without moving or editing the task' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project -Acceptance '- [ ] Acceptance pending'
        $taskPath = Join-Path $active 'TASK.md'
        $before = [System.IO.File]::ReadAllText($taskPath)

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'Acceptance Criteria'
        Test-Path -LiteralPath $active | Should -BeTrue
        [System.IO.File]::ReadAllText($taskPath) | Should -Be $before
    }

    It 'rejects unchecked verification or incomplete evidence' {
        $project = New-TestProject
        $verificationTask = New-ReviewTask -ProjectPath $project -TaskId 'verification-pending' -Verification '- [ ] V1: Test pending'
        $evidenceTask = New-ReviewTask -ProjectPath $project -TaskId 'evidence-pending' -Evidence @'
### Verification Record

- Check: V1
- Command / Scenario:
- Result: PASS
- Target Commit / Diff: working tree diff
- Environment: PowerShell 7 test fixture
- Verified At: 2026-09-02T00:00:00Z
- Verified By: test
- Limitations: fixture only
'@

        $verification = Invoke-CompleteTask -ProjectPath $project -Arguments @('-TaskPath', 'docs/codex/tasks/active/verification-pending')
        $evidence = Invoke-CompleteTask -ProjectPath $project -Arguments @('-TaskPath', 'docs/codex/tasks/active/evidence-pending')

        $verification.ExitCode | Should -Be 1
        ($verification.Output -join "`n") | Should -Match 'Verification Plan'
        $evidence.ExitCode | Should -Be 1
        ($evidence.Output -join "`n") | Should -Match 'Evidence'
        Test-Path -LiteralPath $verificationTask | Should -BeTrue
        Test-Path -LiteralPath $evidenceTask | Should -BeTrue
    }

    It 'requires every checked Verification Plan ID to have a latest PASS Evidence record' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project -Verification @'
- [x] V1: Focused test passed
- [x] V2: Integration test passed
'@ -Evidence @'
### Verification Record

- Check: V1
- Command / Scenario: pwsh -Command test
- Result: PASS
- Target Commit / Diff: working tree diff
- Environment: PowerShell 7 test fixture
- Verified At: 2026-09-02T00:00:00Z
- Verified By: test
- Limitations: fixture only
'@

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'V2|ID|Verification Plan'
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'rejects Evidence IDs that are not present in the Verification Plan' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project -Evidence @'
### Verification Record

- Check: V2
- Command / Scenario: pwsh -Command test
- Result: PASS
- Target Commit / Diff: working tree diff
- Environment: PowerShell 7 test fixture
- Verified At: 2026-09-02T00:00:00Z
- Verified By: test
- Limitations: fixture only
'@

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'V2|ID|Verification Plan'
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'rejects duplicate Verification Plan IDs' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project -Verification @'
- [x] V1: Focused test passed
- [x] V1: Integration test passed
'@

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'duplicate|unique|ID|Verification Plan'
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'rejects malformed or non-sequential Verification Plan IDs' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project -Verification @'
- [x] V1: Focused test passed
- [x] V3: Integration test passed
'@

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'V3|sequential|ID|Verification Plan'
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'rejects a Verification Plan checklist item without an ID' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project -Verification @'
- [x] V1: Focused test passed
- [x] Integration test passed
'@

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'form V1|ID|Verification Plan'
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'rejects an untracked Markdown list item beside identified plan checkboxes' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project -Verification @'
- [x] V1: Focused test passed
- Run one more check manually
'@

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'Verification Plan|checkbox|ID'
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'rejects Evidence Check values that are not an ID by itself' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project -Evidence @'
### Verification Record

- Check: V1: Focused test
- Command / Scenario: pwsh -Command test
- Result: PASS
- Target Commit / Diff: working tree diff
- Environment: PowerShell 7 test fixture
- Verified At: 2026-09-02T00:00:00Z
- Verified By: test
- Limitations: fixture only
'@

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'Check|ID|malformed'
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'rejects a final failed result but allows preserved failure history followed by PASS' {
        $project = New-TestProject
        $failedTask = New-ReviewTask -ProjectPath $project -TaskId 'failed-result' -Evidence @'
### Verification Record

- Check: V1
- Command / Scenario: pwsh -Command test
- Result: FAIL
- Target Commit / Diff: working tree diff
- Environment: PowerShell 7 test fixture
- Verified At: 2026-09-02T00:00:00Z
- Verified By: test
- Limitations: fixture only
'@
        $historyTask = New-ReviewTask -ProjectPath $project -TaskId 'failure-history' -Evidence @'
### Verification Record

- Check: V1
- Command / Scenario: pwsh -Command test
- Result: FAIL
- Target Commit / Diff: working tree diff
- Environment: PowerShell 7 test fixture
- Verified At: 2026-09-02T00:00:00Z
- Verified By: test
- Limitations: initial failure

### Verification Record

- Check: V1
- Command / Scenario: pwsh -Command test
- Result: PASS
- Target Commit / Diff: working tree diff
- Environment: PowerShell 7 test fixture
- Verified At: 2026-09-02T00:01:00Z
- Verified By: test
- Limitations: fixture only
'@

        $failed = Invoke-CompleteTask -ProjectPath $project -Arguments @('-TaskPath', 'docs/codex/tasks/active/failed-result')
        $history = Invoke-CompleteTask -ProjectPath $project -Arguments @('-TaskPath', 'docs/codex/tasks/active/failure-history')

        $failed.ExitCode | Should -Be 1
        ($failed.Output -join "`n") | Should -Match 'PASS'
        Test-Path -LiteralPath $failedTask | Should -BeTrue
        $history.ExitCode | Should -Be 0
        Test-Path -LiteralPath $historyTask | Should -BeFalse
    }

    It 'rejects PASS evidence for an obsolete target diff' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project -Evidence @'
### Verification Record

- Check: V1
- Command / Scenario: pwsh -Command test
- Result: PASS
- Target Commit / Diff: obsolete diff
- Environment: PowerShell 7 test fixture
- Verified At: 2026-09-02T00:00:00Z
- Verified By: test
- Limitations: fixture only
'@

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'Target Commit / Diff'
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'rejects PASS evidence after the working tree changes' {
        $project = New-TestProject
        $implementation = Join-Path $project 'implementation.txt'
        [System.IO.File]::WriteAllText($implementation, 'verified state')
        & git -C $project add implementation.txt
        & git -C $project -c user.name=test -c user.email=test@example.com commit --quiet -m baseline
        $active = New-ReviewTask -ProjectPath $project
        [System.IO.File]::WriteAllText($implementation, 'changed after verification')

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'Target Commit / Diff|fingerprint'
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'rejects a linked active Task without changing its external target' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project
        $externalRoot = Join-Path $TestDrive ('external-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $externalRoot
        $externalTask = Join-Path $externalRoot 'review-task'
        Move-Item -LiteralPath $active -Destination $externalTask
        $null = New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Path $active -Target $externalTask
        $externalTaskFile = Join-Path $externalTask 'TASK.md'
        $before = [System.IO.File]::ReadAllText($externalTaskFile)

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'link|symbolic|reparse'
        Test-Path -LiteralPath $active | Should -BeTrue
        [System.IO.File]::ReadAllText($externalTaskFile) | Should -Be $before
    }

    It 'rejects a Task missing updated_at without moving it' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project
        $taskPath = Join-Path $active 'TASK.md'
        $content = [System.IO.File]::ReadAllText($taskPath) -replace '(?m)^updated_at:.*\r?\n', ''
        [System.IO.File]::WriteAllText($taskPath, $content)

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        ($result.Output -join "`n") | Should -Match 'updated_at'
        Test-Path -LiteralPath $active | Should -BeTrue
        [System.IO.File]::ReadAllText($taskPath) | Should -Be $content
    }

    It 'rejects checked checklist placeholders without text' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project -Acceptance '- [x] ' -Verification '- [x] '

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'rejects zero or multiple active tasks unless TaskPath selects one' {
        $project = New-TestProject
        $none = Invoke-CompleteTask -ProjectPath $project
        $first = New-ReviewTask -ProjectPath $project -TaskId 'task-one'
        $null = New-ReviewTask -ProjectPath $project -TaskId 'task-two'
        $null = Set-CurrentEvidenceTarget -ProjectPath $project -TaskDirectory $first
        $multiple = Invoke-CompleteTask -ProjectPath $project
        $selected = Invoke-CompleteTask -ProjectPath $project -Arguments @('-TaskPath', 'docs/codex/tasks/active/task-one')

        $none.ExitCode | Should -Be 1
        $multiple.ExitCode | Should -Be 1
        $selected.ExitCode | Should -Be 0
        Test-Path -LiteralPath $first | Should -BeFalse
    }

    It 'does not overwrite an existing completed task' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project
        $completed = Join-Path $project 'docs/codex/tasks/completed/review-task'
        $null = New-Item -ItemType Directory -Path $completed
        [System.IO.File]::WriteAllText((Join-Path $completed 'keep.txt'), 'existing')

        $result = Invoke-CompleteTask -ProjectPath $project

        $result.ExitCode | Should -Be 1
        Test-Path -LiteralPath $active | Should -BeTrue
        [System.IO.File]::ReadAllText((Join-Path $completed 'keep.txt')) | Should -Be 'existing'
    }

    It 'validates but does not change a task in WhatIf mode' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project
        $taskPath = Join-Path $active 'TASK.md'
        $before = [System.IO.File]::ReadAllText($taskPath)

        $result = Invoke-CompleteTask -ProjectPath $project -Arguments @('-WhatIf')

        $result.ExitCode | Should -Be 0
        Test-Path -LiteralPath $active | Should -BeTrue
        [System.IO.File]::ReadAllText($taskPath) | Should -Be $before
    }

    It 'rejects an absolute TaskPath even when it names a direct active task' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project

        $result = Invoke-CompleteTask -ProjectPath $project -Arguments @('-TaskPath', $active)

        $result.ExitCode | Should -Be 1
        Test-Path -LiteralPath $active | Should -BeTrue
    }

    It 'prints a stable current Evidence target without changing the task' {
        $project = New-TestProject
        $active = New-ReviewTask -ProjectPath $project
        $before = [System.IO.File]::ReadAllText((Join-Path $active 'TASK.md'))

        $first = Invoke-CompleteTask -ProjectPath $project -Arguments @('-ShowEvidenceTarget')
        $second = Invoke-CompleteTask -ProjectPath $project -Arguments @('-ShowEvidenceTarget')

        $first.ExitCode | Should -Be 0
        ($first.Output -join '').Trim() | Should -Match '^working-tree-sha256:[0-9a-f]{64}$'
        ($second.Output -join '').Trim() | Should -Be (($first.Output -join '').Trim())
        [System.IO.File]::ReadAllText((Join-Path $active 'TASK.md')) | Should -Be $before
    }
}
