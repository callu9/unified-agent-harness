[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Core', 'Project')][string]$Mode = 'Auto',
    [string]$Path = '.',
    [switch]$Strict,
    [switch]$Json,
    [switch]$RequireVersionTag,
    [switch]$CheckBranchPolicy,
    [switch]$SuggestBranchRename,
    [string]$Type
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/CodexHarness.psm1') -Force -DisableNameChecking

function Add-Diagnostic {
    param([string]$Status, [string]$Check, [string]$Message)
    $diagnostics.Add((New-CodexHarnessDiagnostic -Status $Status -Check $Check -Message $Message))
}

function Test-Core {
    param([string]$CorePath)
    foreach ($relative in @(
        'VERSION', 'README.md', 'AGENTS.md', 'CHANGELOG.md', 'SPEC.md',
        'templates/AGENTS.project.md', 'templates/TASK.md',
        'templates/HANDOFF.md', 'templates/DECISIONS.md', 'templates/PULL_REQUEST_TEMPLATE.md',
        'skills/cross-repo-coordination/SKILL.md', 'skills/understanding-debt/SKILL.md',
        'scripts/doctor.ps1', 'scripts/new-task.ps1', 'scripts/complete-task.ps1', 'scripts/handoff.ps1',
        'scripts/cleanup-git.ps1',
        'scripts/lib/CodexHarness.psm1',
        'bin/harness', 'checks/gates.py', 'checks/harness_verify.py', 'checks/git_gate.py',
        'checks/turn_contract.py', 'checks/commit_gate.py', 'checks/branch_name_guard.py',
        'checks/codex_model_guard.py', 'checks/korean_answer_check.py',
        'adapters/codex.json', 'adapters/claude.json', 'githooks/_dispatch', 'rules/00-precedence.md'
    )) {
        if (Test-Path -LiteralPath (Join-Path $CorePath $relative) -PathType Leaf) { Add-Diagnostic PASS $relative '존재합니다.' }
        else { Add-Diagnostic FAIL $relative '필수 소스 파일이 없습니다.' }
    }
    $version = Get-CodexHarnessVersion -CoreRoot $CorePath
    Add-Diagnostic PASS VERSION "유효한 SemVer: $version"
    if ($RequireVersionTag) {
        $tags = (Invoke-CodexHarnessGit -RepositoryPath $CorePath -Arguments @('tag', '--points-at', 'HEAD')).Output
        if ($tags -ccontains "v$version") { Add-Diagnostic PASS 'Version tag' "HEAD에 v$version tag가 있습니다." }
        else { Add-Diagnostic FAIL 'Version tag' "HEAD에 v$version tag가 없습니다." }
    }
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $CorePath 'scripts') -File -Recurse | Where-Object Extension -in '.ps1', '.psm1') {
        $tokens = $null; $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { Add-Diagnostic FAIL "Parse:$($file.Name)" ($errors.Message -join ' ') }
        else { Add-Diagnostic PASS "Parse:$($file.Name)" '구문을 해석했습니다.' }
    }
    foreach ($directory in Get-ChildItem -LiteralPath (Join-Path $CorePath 'skills') -Directory) {
        $metadata = Get-CodexHarnessSkillMetadata -Path (Join-Path $directory.FullName 'SKILL.md')
        if ($metadata.Valid -and $metadata.Name -ceq $directory.Name) { Add-Diagnostic PASS "Skill:$($directory.Name)" 'frontmatter가 유효합니다.' }
        else { Add-Diagnostic FAIL "Skill:$($directory.Name)" 'frontmatter가 유효하지 않습니다.' }
    }
    foreach ($contract in @(
        @{ Path = 'templates/TASK.md'; Fields = @('# Task', '## Acceptance Criteria', '## Verification Plan', '## Evidence') },
        @{ Path = 'templates/HANDOFF.md'; Fields = @('# Handoff', '## Executive Summary', '## Repository Snapshot', '<!-- codex-harness:snapshot:start -->', '<!-- codex-harness:snapshot:end -->') }
    )) {
        $text = Read-CodexHarnessText -Path (Join-Path $CorePath $contract.Path)
        foreach ($field in $contract.Fields) {
            if (-not $text.Contains($field)) { Add-Diagnostic FAIL $contract.Path "필수 필드가 없습니다: $field" }
        }
    }
}

function Test-Project {
    param([string]$ProjectPath)
    Assert-CodexHarnessUnlinkedPath -Path $ProjectPath
    if (-not (Test-CodexHarnessGitRepositoryRoot -Path $ProjectPath)) { throw '정확한 Git root가 필요합니다.' }
    Add-Diagnostic PASS Git 'Git root입니다. 하네스 설치는 필요하지 않습니다.'
    $activeRoot = Join-Path $ProjectPath 'docs/codex/tasks/active'
    Assert-CodexHarnessUnlinkedPath -Path $activeRoot
    $activeTasks = @(if (Test-Path -LiteralPath $activeRoot -PathType Container) { Get-ChildItem -LiteralPath $activeRoot -Directory })
    Add-Diagnostic PASS 'Active tasks' "Task 수: $($activeTasks.Count). 여러 Task는 -TaskPath로 선택합니다."
    foreach ($directory in $activeTasks) {
        try {
            $taskPath = Join-Path $directory.FullName 'TASK.md'
            Assert-CodexHarnessUnlinkedPath -Path $taskPath
            $task = Get-CodexHarnessTaskState -Path $taskPath
            if (-not $task.StatusValid) { Add-Diagnostic FAIL "Task:$($directory.Name)" "유효하지 않은 status: $($task.Status)"; continue }
            Add-Diagnostic PASS "Task:$($directory.Name)" "status: $($task.Status)"
            if ($task.Status -in @('review', 'done')) {
                if ($task.AcceptanceCount -eq 0 -or $task.AcceptanceUncheckedCount -gt 0) { Add-Diagnostic WARN 'Acceptance Criteria' '누락 또는 미체크 항목이 있습니다.' }
                if ($task.VerificationCount -eq 0 -or $task.VerificationUncheckedCount -gt 0 -or -not $task.VerificationIdsValid) { Add-Diagnostic WARN 'Verification Plan' '누락, 미체크 또는 잘못된 ID가 있습니다.' }
                if (-not $task.EvidenceHasContent -or -not $task.EvidenceRecordsComplete) { Add-Diagnostic WARN Evidence '기록이 비어 있거나 불완전합니다.' }
            }
            if ($task.Status -eq 'done') { Add-Diagnostic WARN 'Task location' '완료 Task가 active에 있습니다.' }
        }
        catch { Add-Diagnostic FAIL "Task:$($directory.Name)" $_.Exception.Message }
    }
    if ($CheckBranchPolicy -or $SuggestBranchRename) {
        $policy = Get-CodexHarnessBranchPolicy -ProjectPath $ProjectPath
        if (-not $policy) { Add-Diagnostic PASS 'Branch policy' '프로젝트에 기계 검증 정책이 없어 건너뜁니다.'; return }
        $branch = Get-CodexHarnessCurrentBranch -RepositoryPath $ProjectPath
        if (-not $branch) { Add-Diagnostic WARN Branch 'detached HEAD입니다.' }
        elseif (@($policy.IgnoredPatterns | Where-Object { $branch -cmatch $_ }).Count -gt 0 -or $branch -cmatch $policy.Pattern) { Add-Diagnostic PASS Branch "정책에 맞는 branch: $branch" }
        else {
            Add-Diagnostic WARN Branch "프로젝트 정책 위반: $branch"
            if ($SuggestBranchRename) {
                if ($policy.Types -ccontains $Type) { Add-Diagnostic WARN 'Branch rename' ((Get-CodexHarnessBranchRenameCommands -RepositoryPath $ProjectPath -Branch $branch -Type $Type) -join "`n") }
                else { Add-Diagnostic WARN 'Branch rename' "허용 type을 선택하십시오: $($policy.Types -join ', ')" }
            }
        }
    }
}

$diagnostics = [System.Collections.Generic.List[object]]::new()
$target = $Path
try {
    $target = Resolve-CodexHarnessPath -Path $Path
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { throw "검사 경로가 없습니다: $target" }
    if ($Mode -eq 'Auto') { $Mode = if ((Test-Path (Join-Path $target 'VERSION')) -and (Test-Path (Join-Path $target 'scripts/doctor.ps1'))) { 'Core' } else { 'Project' } }
    if ($Mode -eq 'Core') { Test-Core -CorePath $target }
    else { Test-Project -ProjectPath $target }
}
catch { Add-Diagnostic FAIL Doctor $_.Exception.Message }
$exitCode = if (@($diagnostics | Where-Object Status -eq 'FAIL').Count -or ($Strict -and @($diagnostics | Where-Object Status -eq 'WARN').Count)) { 1 } else { 0 }
if ($Json) { [pscustomobject]@{ mode = $Mode; path = $target; diagnostics = @($diagnostics); exit_code = $exitCode } | ConvertTo-Json -Depth 4 -Compress }
else { foreach ($diagnostic in $diagnostics) { Write-Output "$($diagnostic.Status) [$($diagnostic.Check)] $($diagnostic.Message)" } }
exit $exitCode
