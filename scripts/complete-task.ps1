[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [string]$TaskPath,
    [switch]$ShowEvidenceTarget
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/CodexHarness.psm1') -Force -DisableNameChecking

try {
    $project = Resolve-CodexHarnessPath -Path $ProjectPath
    Assert-CodexHarnessUnlinkedPath -Path $project
    if (-not (Test-CodexHarnessGitRepositoryRoot -Path $project)) { throw "대상 프로젝트가 Git 저장소가 아닙니다: $project" }

    $taskDirectory = Get-CodexHarnessActiveTaskDirectory -ProjectPath $project -TaskPath $TaskPath
    $taskFile = Join-Path $taskDirectory 'TASK.md'
    foreach ($path in @(
        (Join-Path $project 'docs'),
        (Join-Path $project 'docs/codex'),
        (Join-Path $project 'docs/codex/tasks'),
        (Join-Path $project 'docs/codex/tasks/active'),
        $taskDirectory,
        $taskFile
    )) { Assert-CodexHarnessUnlinkedPath -Path $path }
    if (-not (Test-Path -LiteralPath $taskFile -PathType Leaf)) { throw "TASK.md가 없습니다: $taskFile" }
    if ($ShowEvidenceTarget) {
        Write-Output (Get-CodexHarnessWorkingTreeFingerprint -RepositoryPath $project -TaskPath $taskFile)
        exit 0
    }
    $task = Get-CodexHarnessTaskState -Path $taskFile
    $frontmatter = [regex]::Match($task.Content, '(?s)\A---\r?\n(?<value>.*?)\r?\n---(?:\r?\n|$)')
    if (-not $frontmatter.Success) { throw 'TASK.md frontmatter를 읽을 수 없습니다.' }
    $frontmatterValue = $frontmatter.Groups['value']
    $statusPattern = '(?m)^status:[ \t]*["'']?[a-z_]+["'']?[ \t]*$'
    $updatedAtPattern = '(?m)^updated_at:[ \t]*[^\r\n]*$'
    if ([regex]::Matches($frontmatterValue.Value, $statusPattern).Count -ne 1) { throw 'TASK.md frontmatter에 status가 정확히 하나 있어야 합니다.' }
    if ([regex]::Matches($frontmatterValue.Value, $updatedAtPattern).Count -ne 1) { throw 'TASK.md frontmatter에 updated_at이 정확히 하나 있어야 합니다.' }
    if (-not $task.StatusValid) { throw "허용되지 않은 Task status입니다: $($task.Status)" }
    if ($task.Status -notin @('review', 'done')) { throw "Task status가 review 또는 done이어야 합니다: $($task.Status)" }
    if (($task.AcceptanceCount -eq 0) -or ($task.AcceptanceUncheckedCount -gt 0)) { throw 'Acceptance Criteria가 하나 이상 있고 모두 체크되어야 합니다.' }
    if (($task.VerificationCount -eq 0) -or ($task.VerificationUncheckedCount -gt 0)) { throw 'Verification Plan이 하나 이상 있고 모두 체크되어야 합니다.' }
    if (-not $task.VerificationIdsValid) { throw "Verification Plan ID가 유효하지 않습니다: $($task.VerificationIdErrors -join ' ')" }
    if ((-not $task.EvidenceHasContent) -or ($task.EvidenceRecordCount -eq 0) -or (-not $task.EvidenceRecordsComplete)) {
        throw 'Evidence에는 모든 필드가 채워진 Verification Record가 하나 이상 있어야 합니다.'
    }
    $latestEvidence = @{}
    foreach ($record in $task.EvidenceRecords) {
        if ($record.Check -cnotmatch '\AV[1-9][0-9]*\z') { throw "Evidence Check는 Verification Plan ID만 포함해야 합니다: $($record.Check)" }
        $latestEvidence[$record.Check] = $record
    }
    foreach ($id in $task.VerificationIds) {
        if (-not $latestEvidence.ContainsKey($id)) { throw "Verification Plan ID에 최신 Evidence Record가 없습니다: $id" }
    }
    foreach ($id in $latestEvidence.Keys) {
        if ($task.VerificationIds -cnotcontains $id) { throw "Evidence Check가 Verification Plan에 없습니다: $id" }
    }
    foreach ($record in $latestEvidence.Values) {
        if ($record.Result -cne 'PASS') { throw "Check의 마지막 Evidence Result는 PASS여야 합니다: $($record.Check)" }
    }

    $currentTarget = Get-CodexHarnessWorkingTreeFingerprint -RepositoryPath $project -TaskPath $taskFile
    foreach ($record in $latestEvidence.Values) {
        $target = $record.Target.Trim()
        if ($target -cne $currentTarget) { throw "Evidence Target Commit / Diff가 현재 working-tree fingerprint와 일치하지 않습니다: $target" }
    }

    $completedRoot = Join-Path $project 'docs/codex/tasks/completed'
    Assert-CodexHarnessUnlinkedPath -Path $completedRoot
    if ((Test-Path -LiteralPath $completedRoot) -and -not (Test-Path -LiteralPath $completedRoot -PathType Container)) { throw "completed 경로가 디렉터리가 아닙니다: $completedRoot" }
    $destination = Join-Path $completedRoot (Split-Path -Leaf $taskDirectory)
    if (Test-Path -LiteralPath $destination) { throw "완료 Task 경로가 이미 있습니다: $destination" }

    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $updatedFrontmatter = [regex]::Replace($frontmatterValue.Value, $statusPattern, 'status: "done"', 1)
    $updatedFrontmatter = [regex]::Replace($updatedFrontmatter, $updatedAtPattern, "updated_at: `"$timestamp`"", 1)
    $updated = $task.Content.Substring(0, $frontmatterValue.Index) + $updatedFrontmatter + $task.Content.Substring($frontmatterValue.Index + $frontmatterValue.Length)

    if ($PSCmdlet.ShouldProcess($taskDirectory, "Task 완료 후 $destination 로 이동")) {
        try {
            Ensure-CodexHarnessDirectory -Path $completedRoot
            Write-CodexHarnessTextAtomic -Path $taskFile -Content $updated
            [System.IO.Directory]::Move($taskDirectory, $destination)
        }
        catch {
            if (Test-Path -LiteralPath $taskFile -PathType Leaf) { Write-CodexHarnessTextAtomic -Path $taskFile -Content $task.Content }
            throw
        }
        Write-Output "완료: $destination"
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine("complete-task 실패: $($_.Exception.Message)")
    exit 1
}
