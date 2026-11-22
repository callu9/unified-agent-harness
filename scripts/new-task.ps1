[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [Parameter(Mandatory)][string]$Name,
    [string]$Skill = '',
    [string]$TaskId,
    [string]$Description
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/CodexHarness.psm1') -Force -DisableNameChecking

try {
    $project = Resolve-CodexHarnessPath -Path $ProjectPath
    Assert-CodexHarnessUnlinkedPath -Path $project
    if (-not (Test-CodexHarnessGitRepositoryRoot -Path $project)) { throw "정확한 Git root가 필요합니다: $project" }
    if ($Skill -and $Skill -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$') { throw "Skill 이름이 유효하지 않습니다: $Skill" }
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[\r\n]') { throw 'Name은 비어 있지 않은 한 줄이어야 합니다.' }
    if ([string]::IsNullOrWhiteSpace($TaskId)) { $TaskId = "$(Get-Date -Format 'yyyyMMdd-HHmmss')-$(ConvertTo-CodexHarnessSlug -Text $Name)" }
    if ($TaskId -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*$') { throw "TaskId는 영문, 숫자, 하이픈만 사용할 수 있습니다: $TaskId" }
    $taskDirectory = Join-Path $project "docs/codex/tasks/active/$TaskId"
    Assert-CodexHarnessUnlinkedPath -Path $taskDirectory
    if (Test-Path -LiteralPath $taskDirectory) { throw "같은 TaskId가 이미 있습니다: $TaskId" }

    if ($PSCmdlet.ShouldProcess($taskDirectory, 'TASK.md와 HANDOFF.md 생성')) {
        $coreRoot = Get-CodexHarnessCoreRoot
        $timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        $values = @{
            TASK_ID = $TaskId; TASK_TITLE = $Name.Replace('\', '\\').Replace('"', '\"'); SKILL_NAME = $Skill
            TASK_DESCRIPTION = $(if ($Description) { $Description } else { '작업 시작 전에 배경과 범위를 작성하십시오.' })
            CREATED_AT = $timestamp; UPDATED_AT = $timestamp
        }
        Ensure-CodexHarnessDirectory -Path $taskDirectory
        $task = Expand-CodexHarnessTemplate -Template (Read-CodexHarnessText -Path (Join-Path $coreRoot 'templates/TASK.md')) -Values $values
        $handoff = Expand-CodexHarnessTemplate -Template (Read-CodexHarnessText -Path (Join-Path $coreRoot 'templates/HANDOFF.md')) -Values $values
        Write-CodexHarnessText -Path (Join-Path $taskDirectory 'TASK.md') -Content $task
        Write-CodexHarnessText -Path (Join-Path $taskDirectory 'HANDOFF.md') -Content $handoff
        Write-Output "생성: $taskDirectory"
        Write-Output "Skill: $Skill"
        Write-Output '다음: TASK.md의 범위, acceptance criteria, 검증 계획을 작성하십시오.'
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine("new-task 실패: $($_.Exception.Message)")
    exit 1
}
