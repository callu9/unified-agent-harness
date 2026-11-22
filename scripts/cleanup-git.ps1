[CmdletBinding()]
param(
    [string]$RepositoryPath = '.',
    [Parameter(Mandatory)][string]$BaseBranch,
    [switch]$Apply
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/CodexHarness.psm1') -Force -DisableNameChecking

function ConvertFrom-WorktreePorcelain {
    param([string[]]$Lines)

    $records = [System.Collections.Generic.List[object]]::new()
    $fields = [ordered]@{}
    foreach ($line in @($Lines) + @('')) {
        if ($line -eq '') {
            if ($fields.Contains('worktree')) {
                $branch = if ($fields.Contains('branch') -and ([string]$fields.branch).StartsWith('refs/heads/')) {
                    ([string]$fields.branch).Substring('refs/heads/'.Length)
                }
                else { $null }
                $records.Add([pscustomobject]@{
                    Path = [string]$fields.worktree
                    Branch = $branch
                    Detached = $fields.Contains('detached')
                    Locked = $fields.Contains('locked')
                })
            }
            $fields = [ordered]@{}
            continue
        }
        $parts = $line.Split(' ', 2)
        $fields[$parts[0]] = if ($parts.Count -eq 2) { $parts[1] } else { $true }
    }
    return @($records)
}

function Write-CleanupLine {
    param([string]$Status, [string]$Kind, [string]$Value, [string]$Reason)
    Write-Output "$Status [$Kind] $Value - $Reason"
}

try {
    $repository = Resolve-CodexHarnessPath -Path $RepositoryPath
    Assert-CodexHarnessUnlinkedPath -Path $repository
    if (-not (Test-CodexHarnessGitRepositoryRoot -Path $repository)) { throw "Git 저장소가 아닙니다: $repository" }

    $baseRef = "refs/heads/$BaseBranch"
    $base = Invoke-CodexHarnessGit -RepositoryPath $repository -Arguments @('show-ref', '--verify', '--quiet', $baseRef) -AllowFailure
    if ($base.ExitCode -ne 0) { throw "로컬 기준 브랜치가 없습니다: $BaseBranch" }

    $currentBranch = Get-CodexHarnessCurrentBranch -RepositoryPath $repository
    $mergedResult = Invoke-CodexHarnessGit -RepositoryPath $repository -Arguments @(
        'for-each-ref', '--format=%(refname:short)', "--merged=$baseRef", 'refs/heads'
    )
    $mergedBranches = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($branch in $mergedResult.Output) {
        $name = ([string]$branch).Trim()
        if ($name) { $null = $mergedBranches.Add($name) }
    }

    $worktreeResult = Invoke-CodexHarnessGit -RepositoryPath $repository -Arguments @('worktree', 'list', '--porcelain')
    $worktrees = @(ConvertFrom-WorktreePorcelain -Lines $worktreeResult.Output)
    if ($worktrees.Count -eq 0) { throw 'Git worktree 정보를 읽을 수 없습니다.' }

    $attachedBranches = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($worktree in $worktrees) {
        if ($worktree.Branch) { $null = $attachedBranches.Add($worktree.Branch) }
    }
    $deletedBranches = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $failures = 0

    for ($index = 1; $index -lt $worktrees.Count; $index++) {
        $worktree = $worktrees[$index]
        if (($worktree.Branch -ceq $BaseBranch) -or ($worktree.Branch -ceq $currentBranch) -or
            ((Resolve-CodexHarnessPath -Path $worktree.Path) -ceq $repository)) {
            Write-CleanupLine SKIP worktree $worktree.Path 'base/current'; continue
        }
        Assert-CodexHarnessUnlinkedPath -Path $worktree.Path
        if ($worktree.Detached) { Write-CleanupLine SKIP worktree $worktree.Path 'detached'; continue }
        if (-not $worktree.Branch) { Write-CleanupLine SKIP worktree $worktree.Path 'local branch 없음'; continue }
        if ($worktree.Locked) { Write-CleanupLine SKIP worktree $worktree.Path "locked ($($worktree.Branch))"; continue }
        if (-not $mergedBranches.Contains($worktree.Branch)) { Write-CleanupLine SKIP worktree $worktree.Path "미병합 ($($worktree.Branch))"; continue }
        if (-not (Test-Path -LiteralPath $worktree.Path -PathType Container)) { Write-CleanupLine SKIP worktree $worktree.Path 'stale metadata'; continue }

        $status = Invoke-CodexHarnessGit -RepositoryPath $worktree.Path -Arguments @('status', '--porcelain', '--untracked-files=all') -AllowFailure
        if (($status.ExitCode -ne 0) -or ($status.Output.Count -gt 0)) { Write-CleanupLine SKIP worktree $worktree.Path "dirty ($($worktree.Branch))"; continue }

        if (-not $Apply) {
            Write-CleanupLine PLAN worktree $worktree.Path "병합된 clean branch $($worktree.Branch)"
            Write-CleanupLine PLAN branch $worktree.Branch 'worktree 제거 후 삭제'
            continue
        }

        $remove = Invoke-CodexHarnessGit -RepositoryPath $repository -Arguments @('worktree', 'remove', '--', $worktree.Path) -AllowFailure
        if ($remove.ExitCode -ne 0) { Write-CleanupLine FAIL worktree $worktree.Path ($remove.Output -join ' '); $failures++; continue }
        Write-CleanupLine REMOVED worktree $worktree.Path $worktree.Branch

        $delete = Invoke-CodexHarnessGit -RepositoryPath $repository -Arguments @('branch', '-d', '--', $worktree.Branch) -AllowFailure
        if ($delete.ExitCode -ne 0) { Write-CleanupLine FAIL branch $worktree.Branch ($delete.Output -join ' '); $failures++; continue }
        $null = $deletedBranches.Add($worktree.Branch)
        Write-CleanupLine DELETED branch $worktree.Branch 'merged'
    }

    foreach ($branch in $mergedBranches) {
        if (($branch -ceq $BaseBranch) -or ($branch -ceq $currentBranch) -or $deletedBranches.Contains($branch) -or $attachedBranches.Contains($branch)) { continue }
        if (-not $Apply) { Write-CleanupLine PLAN branch $branch "merged into $BaseBranch"; continue }

        $delete = Invoke-CodexHarnessGit -RepositoryPath $repository -Arguments @('branch', '-d', '--', $branch) -AllowFailure
        if ($delete.ExitCode -ne 0) { Write-CleanupLine FAIL branch $branch ($delete.Output -join ' '); $failures++; continue }
        Write-CleanupLine DELETED branch $branch "merged into $BaseBranch"
    }

    if ($Apply) {
        $prune = Invoke-CodexHarnessGit -RepositoryPath $repository -Arguments @('worktree', 'prune') -AllowFailure
        if ($prune.ExitCode -ne 0) { Write-CleanupLine FAIL worktree-metadata $repository ($prune.Output -join ' '); $failures++ }
    }
    exit $(if ($failures -eq 0) { 0 } else { 1 })
}
catch {
    [Console]::Error.WriteLine("Git 정리 실패: $($_.Exception.Message)")
    exit 1
}
