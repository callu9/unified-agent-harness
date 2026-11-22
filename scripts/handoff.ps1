[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory)][string]$ProjectPath,
    [string]$TaskPath,
    [string]$Summary,
    [switch]$IncludeDiffStat
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/CodexHarness.psm1') -Force -DisableNameChecking

function Add-ExecutiveSummary {
    param([string]$Content, [string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $Content }
    $safeText = $Text -replace '[\r\n]+', ' '
    $pattern = '(?s)(## Executive Summary\s*)(.*?)(\s*## Repository Snapshot)'
    if (-not [regex]::IsMatch($Content, $pattern)) { throw 'HANDOFF.md에 Executive Summary 또는 Repository Snapshot 섹션이 없습니다.' }
    return [regex]::Replace($Content, $pattern, { param($match) "$($match.Groups[1].Value)$($match.Groups[2].Value.TrimEnd())`n`n- Automation summary: $safeText`n$($match.Groups[3].Value.TrimStart())" }, 1)
}

try {
    $project = Resolve-CodexHarnessPath -Path $ProjectPath
    if (-not (Test-CodexHarnessGitRepositoryRoot -Path $project)) { throw "대상 프로젝트가 Git 저장소가 아닙니다: $project" }
    $taskDirectory = Get-CodexHarnessActiveTaskDirectory -ProjectPath $project -TaskPath $TaskPath
    $handoffPath = Join-Path $taskDirectory 'HANDOFF.md'
    Assert-CodexHarnessUnlinkedPath -Path $handoffPath
    if (-not (Test-Path -LiteralPath $handoffPath -PathType Leaf)) { throw "HANDOFF.md가 없습니다: $handoffPath" }

    $branchResult = Invoke-CodexHarnessGit -RepositoryPath $project -Arguments @('rev-parse', '--abbrev-ref', 'HEAD') -AllowFailure
    $branch = if (($branchResult.ExitCode -eq 0) -and (($branchResult.Output -join '').Trim() -ne 'HEAD')) { ($branchResult.Output -join '').Trim() } else { "detached@$((Invoke-CodexHarnessGit -RepositoryPath $project -Arguments @('rev-parse', '--short', 'HEAD')).Output -join '')" }
    $head = Invoke-CodexHarnessGit -RepositoryPath $project -Arguments @('log', '-1', '--format=%H%x09%s')
    $headParts = ($head.Output -join '').Trim().Split("`t", 2)
    $upstreamResult = Invoke-CodexHarnessGit -RepositoryPath $project -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}') -AllowFailure
    $upstream = if ($upstreamResult.ExitCode -eq 0) { ($upstreamResult.Output -join '').Trim() } else { 'none' }
    $aheadBehind = if ($upstream -ne 'none') { (Invoke-CodexHarnessGit -RepositoryPath $project -Arguments @('rev-list', '--left-right', '--count', "$upstream...HEAD")).Output -join '' } else { '' }
    $status = (Invoke-CodexHarnessGit -RepositoryPath $project -Arguments @('status', '--porcelain=v1')).Output

    $snapshot = [System.Collections.Generic.List[string]]::new()
    $snapshot.Add('<!-- codex-harness:snapshot:start -->')
    $snapshot.Add("- Captured at: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))")
    $snapshot.Add('- Repository: .')
    $snapshot.Add("- Branch: $branch")
    $snapshot.Add("- HEAD: $($headParts[0]) $($headParts[1])")
    $snapshot.Add("- Upstream: $upstream")
    if ($aheadBehind) { $snapshot.Add("- Ahead/behind: $aheadBehind") }
    if (@($status).Count -eq 0) { $snapshot.Add('- Working tree: clean') }
    else {
        $snapshot.Add('- Working tree: dirty')
        foreach ($lineObject in $status) {
            $line = [string]$lineObject
            if ($line.Length -lt 4) { continue }
            $code = $line.Substring(0, 2)
            $path = $line.Substring(3)
            if ($code -eq '??') { $snapshot.Add("- untracked: $path"); continue }
            if ($code[0] -ne ' ') { $snapshot.Add("- staged ($($code[0])): $path") }
            if ($code[1] -ne ' ') { $snapshot.Add("- unstaged ($($code[1])): $path") }
        }
    }
    if ($IncludeDiffStat) {
        $snapshot.Add('- Diff stat:')
        foreach ($stat in @((Invoke-CodexHarnessGit -RepositoryPath $project -Arguments @('diff', '--stat')).Output, (Invoke-CodexHarnessGit -RepositoryPath $project -Arguments @('diff', '--cached', '--stat')).Output)) {
            foreach ($line in @($stat)) { if ($line) { $snapshot.Add("  $line") } }
        }
    }
    $snapshot.Add('<!-- codex-harness:snapshot:end -->')

    $content = Read-CodexHarnessText -Path $handoffPath
    $content = Update-CodexHarnessManagedBlock -Existing $content -Block ($snapshot -join "`n") -StartMarker '<!-- codex-harness:snapshot:start -->' -EndMarker '<!-- codex-harness:snapshot:end -->'
    $content = Add-ExecutiveSummary -Content $content -Text $Summary
    if ($PSCmdlet.ShouldProcess($handoffPath, 'Git 상태 스냅샷 갱신')) { Write-CodexHarnessText -Path $handoffPath -Content $content; Write-Output "갱신: $handoffPath" }
    exit 0
}
catch {
    [Console]::Error.WriteLine("handoff 실패: $($_.Exception.Message)")
    exit 1
}
