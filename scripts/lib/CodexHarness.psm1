Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CodexHarnessCoreRoot { return Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }

function Resolve-CodexHarnessPath {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.Path]::GetFullPath($Path)
}

function Assert-CodexHarnessUnlinkedPath {
    param([Parameter(Mandatory)][string]$Path)
    $candidate = Resolve-CodexHarnessPath -Path $Path
    while ($candidate) {
        $item = Get-Item -LiteralPath $candidate -Force -ErrorAction SilentlyContinue
        if ($item -and ((-not [string]::IsNullOrWhiteSpace([string]$item.LinkType)) -or
            (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0))) {
            throw "linked 또는 reparse-point 경로는 사용할 수 없습니다: $candidate"
        }
        $candidate = [System.IO.Path]::GetDirectoryName($candidate)
    }
}

function Get-CodexHarnessActiveTaskDirectory {
    param([Parameter(Mandatory)][string]$ProjectPath, [string]$TaskPath)

    $project = Resolve-CodexHarnessPath -Path $ProjectPath
    Assert-CodexHarnessUnlinkedPath -Path $project
    $taskRoots = @(
        (Join-Path $project 'docs'),
        (Join-Path $project 'docs/codex'),
        (Join-Path $project 'docs/codex/tasks'),
        (Join-Path $project 'docs/codex/tasks/active')
    )
    foreach ($path in $taskRoots) { Assert-CodexHarnessUnlinkedPath -Path $path }
    $activeRoot = Resolve-CodexHarnessPath -Path $taskRoots[-1]

    if ($TaskPath) {
        if ([System.IO.Path]::IsPathRooted($TaskPath)) { throw "TaskPath는 프로젝트 기준 상대경로여야 합니다: $TaskPath" }
        $candidate = Resolve-CodexHarnessPath -Path (Join-Path $project $TaskPath)
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) { throw "지정한 TaskPath가 없습니다: $candidate" }
        if (-not (Split-Path -Parent $candidate).Equals($activeRoot, $(if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }))) { throw "TaskPath는 active 디렉터리의 직계 Task여야 합니다: $candidate" }
        Assert-CodexHarnessUnlinkedPath -Path $candidate
        return $candidate
    }

    $tasks = @(if (Test-Path -LiteralPath $activeRoot -PathType Container) { Get-ChildItem -LiteralPath $activeRoot -Directory })
    if ($tasks.Count -eq 1) {
        Assert-CodexHarnessUnlinkedPath -Path $tasks[0].FullName
        return $tasks[0].FullName
    }
    $names = if ($tasks.Count -eq 0) { '없음' } else { $tasks.Name -join ', ' }
    throw "active 작업이 정확히 하나여야 합니다. 현재: $names. -TaskPath로 지정하십시오."
}

function Read-CodexHarnessText {
    param([Parameter(Mandatory)][string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

function Write-CodexHarnessText {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    [System.IO.File]::WriteAllText($Path, $normalized, [System.Text.UTF8Encoding]::new($false))
}

function Write-CodexHarnessTextAtomic {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Content)
    $fullPath = Resolve-CodexHarnessPath -Path $Path
    $directory = Split-Path -Parent $fullPath
    Ensure-CodexHarnessDirectory -Path $directory
    $temporary = Join-Path $directory ('.' + [System.IO.Path]::GetFileName($fullPath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($temporary, $Content, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::Move($temporary, $fullPath, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Ensure-CodexHarnessDirectory {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { $null = [System.IO.Directory]::CreateDirectory($Path) }
}

function Test-CodexHarnessSemVer {
    param([Parameter(Mandatory)][string]$Version)
    return $Version -match '^\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'
}

function Get-CodexHarnessVersion {
    param([Parameter(Mandatory)][string]$CoreRoot)
    $versionPath = Join-Path $CoreRoot 'VERSION'
    if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) { throw "Core VERSION 파일이 없습니다: $versionPath" }
    $version = (Read-CodexHarnessText -Path $versionPath).Trim()
    if (-not (Test-CodexHarnessSemVer -Version $version)) { throw "Core VERSION이 유효한 SemVer가 아닙니다: $version" }
    return $version
}

function ConvertTo-CodexHarnessSlug {
    param([Parameter(Mandatory)][string]$Text)
    $slug = ($Text.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ($slug) { return $slug }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return 'task-' + ([System.Convert]::ToHexString($hash).Substring(0, 8).ToLowerInvariant())
}

function Expand-CodexHarnessTemplate {
    param([Parameter(Mandatory)][string]$Template, [Parameter(Mandatory)][hashtable]$Values)
    $result = $Template
    foreach ($key in $Values.Keys) { $result = $result.Replace("{{$key}}", [string]$Values[$key]) }
    return $result
}

function Update-CodexHarnessManagedBlock {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Existing, [Parameter(Mandatory)][string]$Block,
        [Parameter(Mandatory)][string]$StartMarker, [Parameter(Mandatory)][string]$EndMarker
    )
    $startCount = [regex]::Matches($Existing, [regex]::Escape($StartMarker)).Count
    $endCount = [regex]::Matches($Existing, [regex]::Escape($EndMarker)).Count
    if (($startCount -eq 0) -and ($endCount -eq 0)) {
        if ([string]::IsNullOrWhiteSpace($Existing)) { return $Block.Trim() + "`n" }
        return $Existing.TrimEnd() + "`n`n" + $Block.Trim() + "`n"
    }
    if (($startCount -ne 1) -or ($endCount -ne 1)) { throw '관리 마커가 없거나 중복되었습니다. 대상 파일의 마커를 확인하십시오.' }
    $pattern = '(?s)' + [regex]::Escape($StartMarker) + '.*?' + [regex]::Escape($EndMarker)
    $match = [regex]::Match($Existing, $pattern)
    if (-not $match.Success) { throw '관리 마커 순서가 올바르지 않습니다. 시작 마커가 종료 마커보다 앞에 있어야 합니다.' }
    return $Existing.Substring(0, $match.Index) + $Block.Trim() + $Existing.Substring($match.Index + $match.Length)
}

function Get-CodexHarnessTaskState {
    param([Parameter(Mandatory)][string]$Path)

    $content = Read-CodexHarnessText -Path $Path
    $frontmatter = [regex]::Match($content, '(?s)\A---\r?\n(?<value>.*?)\r?\n---(?:\r?\n|$)')
    $status = if ($frontmatter.Success) {
        [regex]::Match($frontmatter.Groups['value'].Value, '(?m)^status:\s*["'']?(?<value>[a-z_]+)["'']?\s*$').Groups['value'].Value
    }
    else { '' }
    $allowedStatuses = @('draft', 'ready', 'in_progress', 'blocked', 'review', 'done', 'cancelled')

    $sections = @{}
    foreach ($heading in @('Acceptance Criteria', 'Verification Plan', 'Evidence')) {
        $match = [regex]::Match($content, '(?ms)^##\s+' + [regex]::Escape($heading) + '\s*\r?\n(?<value>.*?)(?=^##\s+|\z)')
        $sections[$heading] = if ($match.Success) { $match.Groups['value'].Value } else { '' }
    }

    $checklistPattern = '(?m)^\s*[-*+]\s+\[(?: |x|X)\][ \t]+\S.*$'
    $uncheckedPattern = '(?m)^\s*[-*+]\s+\[ \](?:[ \t]+\S.*)?[ \t]*$'
    $acceptance = $sections['Acceptance Criteria']
    $verification = $sections['Verification Plan']
    $evidence = $sections['Evidence']

    $verificationIds = [System.Collections.Generic.List[string]]::new()
    $verificationIdErrors = [System.Collections.Generic.List[string]]::new()
    $verificationItems = [regex]::Matches($verification, '(?m)^\s*(?:[-*+]|[0-9]+[.)])[ \t]+(?<item>[^\r\n]*?)[ \t]*$')
    foreach ($itemMatch in $verificationItems) {
        $checkboxMatch = [regex]::Match($itemMatch.Groups['item'].Value, '\A\[(?<state> |x|X)\](?:[ \t]+(?<item>.*?))?[ \t]*\z')
        if (-not $checkboxMatch.Success) {
            $verificationIdErrors.Add('Every Verification Plan list item must be a checked checkbox with the form V1: description, using sequential unique IDs.')
            continue
        }
        $item = $checkboxMatch.Groups['item'].Value.Trim()
        $idMatch = [regex]::Match($item, '\A(?<id>V[1-9][0-9]*):[ \t]+\S.*\z')
        if (-not $idMatch.Success) {
            $verificationIdErrors.Add('Every Verification Plan item must use the form V1: description, with IDs sequential and unique.')
            continue
        }
        $id = $idMatch.Groups['id'].Value
        $expectedId = 'V' + ($verificationIds.Count + 1)
        if ($verificationIds -ccontains $id) {
            $verificationIdErrors.Add("Verification Plan ID is duplicated: $id")
        }
        elseif ($id -cne $expectedId) {
            $verificationIdErrors.Add("Verification Plan IDs must be sequential; expected $expectedId but found $id.")
        }
        $verificationIds.Add($id)
    }

    $evidenceFields = @('Check', 'Command / Scenario', 'Result', 'Target Commit / Diff', 'Environment', 'Verified At', 'Verified By', 'Limitations')
    $fieldNamesPattern = ($evidenceFields | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $substantiveEvidence = [regex]::Replace($evidence, '(?ms)<!--.*?-->', '')
    $substantiveEvidence = [regex]::Replace($substantiveEvidence, '(?m)^\s*#{3,}\s+.*$', '')
    $substantiveEvidence = [regex]::Replace($substantiveEvidence, "(?m)^\s*[-*+]\s+(?:$fieldNamesPattern):[ \t]*$", '')

    $recordMatches = [regex]::Matches($evidence, '(?ms)^###\s+Verification Record\s*\r?\n(?<value>.*?)(?=^###\s+|\z)')
    $recordsComplete = $recordMatches.Count -gt 0
    $evidenceRecords = [System.Collections.Generic.List[object]]::new()
    foreach ($recordMatch in $recordMatches) {
        $record = $recordMatch.Groups['value'].Value
        $values = @{}
        foreach ($field in $evidenceFields) {
            $fieldMatch = [regex]::Match($record, '(?m)^\s*[-*+]\s+' + [regex]::Escape($field) + ':[ \t]*(?<value>[^\r\n]*?)[ \t]*$')
            if ((-not $fieldMatch.Success) -or [string]::IsNullOrWhiteSpace($fieldMatch.Groups['value'].Value)) {
                $recordsComplete = $false
            }
            else { $values[$field] = $fieldMatch.Groups['value'].Value.Trim() }
        }
        if ($values.Count -eq $evidenceFields.Count) {
            $evidenceRecords.Add([pscustomobject]@{
                Check = $values['Check']
                Result = $values['Result']
                Target = $values['Target Commit / Diff']
            })
        }
    }

    return [pscustomobject]@{
        Path = $Path
        Content = $content
        Status = $status
        StatusValid = $allowedStatuses -contains $status
        AcceptanceCount = [regex]::Matches($acceptance, $checklistPattern).Count
        AcceptanceUncheckedCount = [regex]::Matches($acceptance, $uncheckedPattern).Count
        VerificationCount = [regex]::Matches($verification, $checklistPattern).Count
        VerificationUncheckedCount = [regex]::Matches($verification, $uncheckedPattern).Count
        VerificationIds = @($verificationIds)
        VerificationIdsValid = $verificationIdErrors.Count -eq 0
        VerificationIdErrors = @($verificationIdErrors)
        EvidenceHasContent = -not [string]::IsNullOrWhiteSpace($substantiveEvidence)
        EvidenceRecordCount = $recordMatches.Count
        EvidenceRecordsComplete = $recordsComplete
        EvidenceRecords = @($evidenceRecords)
    }
}

function Get-CodexHarnessSkillMetadata {
    param([Parameter(Mandatory)][string]$Path)
    $content = Read-CodexHarnessText -Path $Path
    $match = [regex]::Match($content, '(?s)\A---\r?\n(?<frontmatter>.*?)\r?\n---')
    if (-not $match.Success) { return [pscustomobject]@{ Valid = $false; Name = ''; Description = ''; Error = 'YAML frontmatter가 없습니다.' } }
    $frontmatter = $match.Groups['frontmatter'].Value
    $name = [regex]::Match($frontmatter, '(?m)^name:\s*(?<value>.+?)\s*$').Groups['value'].Value.Trim(' ', '"', "'")
    $description = [regex]::Match($frontmatter, '(?m)^description:\s*(?<value>.+?)\s*$').Groups['value'].Value.Trim(' ', '"', "'")
    $valid = -not [string]::IsNullOrWhiteSpace($name) -and -not [string]::IsNullOrWhiteSpace($description)
    return [pscustomobject]@{ Valid = $valid; Name = $name; Description = $description; Error = $(if ($valid) { '' } else { 'name 또는 description이 비어 있습니다.' }) }
}

function Invoke-CodexHarnessGit {
    param([Parameter(Mandatory)][string]$RepositoryPath, [Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    $output = & git -C $RepositoryPath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if (($exitCode -ne 0) -and (-not $AllowFailure)) { throw "Git 명령이 실패했습니다 (git $($Arguments -join ' ')): $($output -join [Environment]::NewLine)" }
    return [pscustomobject]@{ Output = @($output); ExitCode = $exitCode }
}

function Invoke-CodexHarnessGitText {
    param([Parameter(Mandatory)][string]$RepositoryPath, [Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = 'git'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('-C', $RepositoryPath) + $Arguments) { $null = $startInfo.ArgumentList.Add($argument) }
    $process = [System.Diagnostics.Process]::Start($startInfo)
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $result = [pscustomobject]@{
        Output = $stdout.GetAwaiter().GetResult()
        Error = $stderr.GetAwaiter().GetResult()
        ExitCode = $process.ExitCode
    }
    if (($result.ExitCode -ne 0) -and (-not $AllowFailure)) {
        throw "Git 명령이 실패했습니다 (git $($Arguments -join ' ')): $($result.Error.Trim())"
    }
    return $result
}

function Get-CodexHarnessWorkingTreeFingerprint {
    param([Parameter(Mandatory)][string]$RepositoryPath, [Parameter(Mandatory)][string]$TaskPath)

    $repository = Resolve-CodexHarnessPath -Path $RepositoryPath
    $task = Resolve-CodexHarnessPath -Path $TaskPath
    $taskRelative = [System.IO.Path]::GetRelativePath($repository, $task).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    if ([System.IO.Path]::IsPathRooted($taskRelative) -or $taskRelative -eq '..' -or $taskRelative.StartsWith('../')) {
        throw "TASK.md는 저장소 안에 있어야 합니다: $task"
    }

    $headResult = Invoke-CodexHarnessGitText -RepositoryPath $repository -Arguments @('rev-parse', '--verify', 'HEAD') -AllowFailure
    $head = if ($headResult.ExitCode -eq 0) { $headResult.Output.Trim() } else { 'UNBORN' }
    $diffOptions = @('-c', 'core.quotepath=true', 'diff', '--no-color', '--no-ext-diff', '--no-textconv', '--binary', '--full-index', '--no-renames')
    $excludeTask = ":(exclude,literal)$taskRelative"
    if ($head -ne 'UNBORN') {
        $otherDiff = (Invoke-CodexHarnessGitText -RepositoryPath $repository -Arguments ($diffOptions + @('HEAD', '--', '.', $excludeTask))).Output
        $taskDiff = (Invoke-CodexHarnessGitText -RepositoryPath $repository -Arguments ($diffOptions + @('HEAD', '--', $taskRelative))).Output
    }
    else {
        $otherDiff = (Invoke-CodexHarnessGitText -RepositoryPath $repository -Arguments ($diffOptions + @('--cached', '--', '.', $excludeTask))).Output
        $otherDiff += (Invoke-CodexHarnessGitText -RepositoryPath $repository -Arguments ($diffOptions + @('--', '.', $excludeTask))).Output
        $taskDiff = (Invoke-CodexHarnessGitText -RepositoryPath $repository -Arguments ($diffOptions + @('--cached', '--', $taskRelative))).Output
        $taskDiff += (Invoke-CodexHarnessGitText -RepositoryPath $repository -Arguments ($diffOptions + @('--', $taskRelative))).Output
    }
    $taskDiff = [regex]::Replace($taskDiff, '(?m)^index [0-9a-f]+\.\.[0-9a-f]+(?: [0-7]+)?$', 'index <task-fingerprint-normalized>')
    $taskDiff = [regex]::Replace($taskDiff, '(?m)^(?<prefix>[ +\-])- Target Commit / Diff:[^\r\n]*$', {
        param($match)
        return $match.Groups['prefix'].Value + '- Target Commit / Diff: <working-tree-fingerprint>'
    })

    $untrackedResult = Invoke-CodexHarnessGitText -RepositoryPath $repository -Arguments @('ls-files', '-z', '--others', '--exclude-standard')
    $untracked = @($untrackedResult.Output.Split([char]0, [System.StringSplitOptions]::RemoveEmptyEntries))
    [array]::Sort($untracked, [System.StringComparer]::Ordinal)
    $untrackedManifest = [System.Text.StringBuilder]::new()
    foreach ($relativePath in $untracked) {
        if ($relativePath -eq $taskRelative) {
            $taskContent = Read-CodexHarnessText -Path $task
            $taskContent = [regex]::Replace($taskContent, '(?m)^- Target Commit / Diff:[^\r\n]*$', '- Target Commit / Diff: <working-tree-fingerprint>')
            $blobBytes = [System.Text.Encoding]::UTF8.GetBytes($taskContent)
            $blob = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($blobBytes)).ToLowerInvariant()
        }
        else {
            $blob = (Invoke-CodexHarnessGitText -RepositoryPath $repository -Arguments @('hash-object', '--no-filters', '--', $relativePath)).Output.Trim()
        }
        $null = $untrackedManifest.Append($relativePath).Append([char]0).Append($blob).Append("`n")
    }

    $fingerprintSource = "codex-harness-working-tree-v1`nHEAD`0$head`nDIFF`0$otherDiff`nTASK-DIFF`0$taskDiff`nUNTRACKED`0$untrackedManifest"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($fingerprintSource)
    return 'working-tree-sha256:' + [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-CodexHarnessGitRoot {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) { return $null }
    $result = Invoke-CodexHarnessGit -RepositoryPath $Path -Arguments @('rev-parse', '--show-toplevel') -AllowFailure
    if ($result.ExitCode -ne 0) { return $null }
    return Resolve-CodexHarnessPath -Path (($result.Output -join "`n").Trim())
}

function Test-CodexHarnessGitRepositoryRoot {
    param([Parameter(Mandatory)][string]$Path)
    $candidate = Resolve-CodexHarnessPath -Path $Path
    $root = Get-CodexHarnessGitRoot -Path $candidate
    return $null -ne $root -and $candidate.Equals($root, $(if ($IsWindows) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }))
}

function Get-CodexHarnessBranchPolicy {
    param([Parameter(Mandatory)][string]$ProjectPath)

    $projectPolicy = Join-Path $ProjectPath '.codex-harness/branch-policy.json'
    Assert-CodexHarnessUnlinkedPath -Path $projectPolicy
    $policyPath = if (Test-Path -LiteralPath $projectPolicy -PathType Leaf) { $projectPolicy } else { return $null }
    try { $policy = (Read-CodexHarnessText -Path $policyPath) | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "브랜치 정책 JSON을 읽을 수 없습니다: $policyPath ($($_.Exception.Message))" }

    $pattern = [string]$policy.pattern
    $types = @($policy.types | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $ignoredPatterns = @($policy.ignored_patterns | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ([string]::IsNullOrWhiteSpace($pattern) -or $types.Count -eq 0) { throw "브랜치 정책에는 pattern과 하나 이상의 types가 필요합니다: $policyPath" }
    try {
        $null = [regex]::new($pattern)
        foreach ($ignoredPattern in $ignoredPatterns) { $null = [regex]::new($ignoredPattern) }
    }
    catch { throw "브랜치 정책 정규식이 올바르지 않습니다: $policyPath ($($_.Exception.Message))" }
    return [pscustomobject]@{ Pattern = $pattern; Types = $types; IgnoredPatterns = $ignoredPatterns; Path = $policyPath }
}

function Get-CodexHarnessCurrentBranch {
    param([Parameter(Mandatory)][string]$RepositoryPath)

    $result = Invoke-CodexHarnessGit -RepositoryPath $RepositoryPath -Arguments @('branch', '--show-current') -AllowFailure
    if ($result.ExitCode -ne 0) { return $null }
    $branch = ($result.Output -join '').Trim()
    return $(if ($branch) { $branch } else { $null })
}

function Get-CodexHarnessBranchRenameCommands {
    param(
        [Parameter(Mandatory)][string]$RepositoryPath,
        [Parameter(Mandatory)][string]$Branch,
        [Parameter(Mandatory)][string]$Type
    )

    $leaf = ($Branch -split '/')[-1]
    $newBranch = "$Type/$(ConvertTo-CodexHarnessSlug -Text $leaf)"
    $quote = { param([string]$Value) return "'" + $Value.Replace("'", "''") + "'" }
    $repository = & $quote $RepositoryPath
    $commands = [System.Collections.Generic.List[string]]::new()
    $commands.Add("git -C $repository branch -m -- $(& $quote $newBranch)")
    $upstream = Invoke-CodexHarnessGit -RepositoryPath $RepositoryPath -Arguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}') -AllowFailure
    if ($upstream.ExitCode -eq 0) {
        $remote = (($upstream.Output -join '').Trim() -split '/', 2)[0]
        if ($remote) {
            $commands.Add("git -C $repository push $(& $quote $remote) -u $(& $quote $newBranch)")
            $commands.Add("git -C $repository push $(& $quote $remote) --delete $(& $quote $Branch)")
        }
    }
    return $commands
}

function New-CodexHarnessDiagnostic {
    param([Parameter(Mandatory)][ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status, [Parameter(Mandatory)][string]$Check, [Parameter(Mandatory)][string]$Message)
    return [pscustomobject]@{ Status = $Status; Check = $Check; Message = $Message }
}

Export-ModuleMember -Function @(
    'Assert-CodexHarnessUnlinkedPath', 'ConvertTo-CodexHarnessSlug', 'Ensure-CodexHarnessDirectory', 'Expand-CodexHarnessTemplate',
    'Get-CodexHarnessActiveTaskDirectory',
    'Get-CodexHarnessBranchPolicy', 'Get-CodexHarnessBranchRenameCommands', 'Get-CodexHarnessCoreRoot', 'Get-CodexHarnessCurrentBranch', 'Get-CodexHarnessGitRoot', 'Get-CodexHarnessSkillMetadata', 'Get-CodexHarnessVersion',
    'Get-CodexHarnessTaskState', 'Get-CodexHarnessWorkingTreeFingerprint',
    'Invoke-CodexHarnessGit', 'New-CodexHarnessDiagnostic', 'Read-CodexHarnessText',
    'Resolve-CodexHarnessPath', 'Test-CodexHarnessGitRepositoryRoot', 'Test-CodexHarnessSemVer',
    'Update-CodexHarnessManagedBlock', 'Write-CodexHarnessText', 'Write-CodexHarnessTextAtomic'
)
