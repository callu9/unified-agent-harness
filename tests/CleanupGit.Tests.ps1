BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $cleanup = Join-Path $repoRoot 'scripts/cleanup-git.ps1'
    $pwsh = 'pwsh'

    function Invoke-TestGit {
        param([Parameter(Mandatory)][string]$RepositoryPath, [Parameter(Mandatory)][string[]]$Arguments)
        $output = & git -C $RepositoryPath @Arguments 2>&1
        if ($LASTEXITCODE -ne 0) { throw "git $($Arguments -join ' ') failed: $($output -join "`n")" }
        return @($output)
    }

    function Add-TestCommit {
        param(
            [Parameter(Mandatory)][string]$RepositoryPath,
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][string]$Content
        )
        [System.IO.File]::WriteAllText((Join-Path $RepositoryPath $Name), $Content)
        $null = Invoke-TestGit $RepositoryPath @('add', '--', $Name)
        $null = Invoke-TestGit $RepositoryPath @('commit', '-m', $Name)
    }

    function New-TestRepository {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $repository = Join-Path $root 'repository'
        $null = New-Item -ItemType Directory -Path $repository -Force
        $null = Invoke-TestGit $repository @('init', '-b', 'main')
        $null = Invoke-TestGit $repository @('config', 'user.name', 'Codex Harness Test')
        $null = Invoke-TestGit $repository @('config', 'user.email', 'codex-harness@example.invalid')
        Add-TestCommit -RepositoryPath $repository -Name 'base.txt' -Content 'base'
        return [pscustomobject]@{ Root = $root; Repository = $repository }
    }

    function Add-MergedBranchWorktree {
        param(
            [Parameter(Mandatory)][object]$Fixture,
            [Parameter(Mandatory)][string]$Branch,
            [Parameter(Mandatory)][string]$WorktreeName
        )
        $null = Invoke-TestGit $Fixture.Repository @('switch', '-c', $Branch)
        Add-TestCommit -RepositoryPath $Fixture.Repository -Name (($Branch -replace '/', '-') + '.txt') -Content $Branch
        $null = Invoke-TestGit $Fixture.Repository @('switch', 'main')
        $null = Invoke-TestGit $Fixture.Repository @('merge', '--no-ff', '--no-edit', $Branch)
        $worktree = Join-Path $Fixture.Root $WorktreeName
        $null = Invoke-TestGit $Fixture.Repository @('worktree', 'add', $worktree, $Branch)
        return $worktree
    }

    function New-CleanupFixture {
        $fixture = New-TestRepository
        $mergedWorktree = Add-MergedBranchWorktree -Fixture $fixture -Branch 'fix/merged' -WorktreeName 'merged-worktree'
        return [pscustomobject]@{
            Root = $fixture.Root
            Repository = $fixture.Repository
            MergedWorktree = $mergedWorktree
        }
    }

    function New-SafetyFixture {
        $fixture = New-TestRepository
        $dirtyWorktree = Add-MergedBranchWorktree -Fixture $fixture -Branch 'fix/dirty' -WorktreeName 'dirty-worktree'
        [System.IO.File]::WriteAllText((Join-Path $dirtyWorktree 'untracked.txt'), 'keep')

        $null = Invoke-TestGit $fixture.Repository @('branch', 'fix/locked', 'main')
        $lockedWorktree = Join-Path $fixture.Root 'locked-worktree'
        $null = Invoke-TestGit $fixture.Repository @('worktree', 'add', $lockedWorktree, 'fix/locked')
        $null = Invoke-TestGit $fixture.Repository @('worktree', 'lock', $lockedWorktree)

        $detachedWorktree = Join-Path $fixture.Root 'detached-worktree'
        $null = Invoke-TestGit $fixture.Repository @('worktree', 'add', '--detach', $detachedWorktree, 'main')

        $unmergedWorktree = Join-Path $fixture.Root 'unmerged-worktree'
        $null = Invoke-TestGit $fixture.Repository @('worktree', 'add', '-b', 'feat/unmerged', $unmergedWorktree, 'main')
        Add-TestCommit -RepositoryPath $unmergedWorktree -Name 'unmerged.txt' -Content 'unmerged'

        return [pscustomobject]@{
            Root = $fixture.Root
            Repository = $fixture.Repository
            DirtyWorktree = $dirtyWorktree
            LockedWorktree = $lockedWorktree
            DetachedWorktree = $detachedWorktree
            UnmergedWorktree = $unmergedWorktree
        }
    }

    function Invoke-Cleanup {
        param(
            [Parameter(Mandatory)][object]$Fixture,
            [string]$BaseBranch = 'main',
            [string[]]$Arguments = @()
        )
        $output = & $pwsh -NoLogo -NoProfile -File $cleanup -RepositoryPath $Fixture.Repository -BaseBranch $BaseBranch @Arguments 2>&1
        return [pscustomobject]@{ Output = @($output); ExitCode = $LASTEXITCODE }
    }

    function Test-LocalBranch {
        param([Parameter(Mandatory)][string]$RepositoryPath, [Parameter(Mandatory)][string]$Branch)
        & git -C $RepositoryPath show-ref --verify --quiet "refs/heads/$Branch"
        return $LASTEXITCODE -eq 0
    }
}

Describe 'cleanup-git.ps1' {
    It 'previews a merged branch and clean worktree without changing them' {
        $fixture = New-CleanupFixture

        $result = Invoke-Cleanup -Fixture $fixture

        $result.ExitCode | Should -Be 0
        ($result.Output -join "`n") | Should -Match 'PLAN.*fix/merged'
        Test-Path -LiteralPath $fixture.MergedWorktree | Should -BeTrue
        (Test-LocalBranch $fixture.Repository 'fix/merged') | Should -BeTrue
    }

    It 'applies removal of a merged branch and its clean secondary worktree' {
        $fixture = New-CleanupFixture

        $result = Invoke-Cleanup -Fixture $fixture -Arguments @('-Apply')

        $result.ExitCode | Should -Be 0
        Test-Path -LiteralPath $fixture.MergedWorktree | Should -BeFalse
        (Test-LocalBranch $fixture.Repository 'fix/merged') | Should -BeFalse
    }

    It 'preserves unmerged branches and dirty locked or detached worktrees' {
        $fixture = New-SafetyFixture

        $result = Invoke-Cleanup -Fixture $fixture -Arguments @('-Apply')

        $result.ExitCode | Should -Be 0
        foreach ($path in @($fixture.DirtyWorktree, $fixture.LockedWorktree, $fixture.DetachedWorktree, $fixture.UnmergedWorktree)) {
            Test-Path -LiteralPath $path | Should -BeTrue
        }
        (Test-LocalBranch $fixture.Repository 'fix/dirty') | Should -BeTrue
        (Test-LocalBranch $fixture.Repository 'fix/locked') | Should -BeTrue
        (Test-LocalBranch $fixture.Repository 'feat/unmerged') | Should -BeTrue
    }

    It 'rejects an invalid base branch without mutation' {
        $fixture = New-CleanupFixture

        $result = Invoke-Cleanup -Fixture $fixture -BaseBranch 'missing' -Arguments @('-Apply')

        $result.ExitCode | Should -Be 1
        Test-Path -LiteralPath $fixture.MergedWorktree | Should -BeTrue
        (Test-LocalBranch $fixture.Repository 'fix/merged') | Should -BeTrue
    }
    It 'preserves both base and current secondary worktrees before deleting' {
        $project = Join-Path $TestDrive 'repo'; $null = New-Item -ItemType Directory $project
        & git -C $project init --quiet -b main
        & git -C $project -c user.name=test -c user.email=test@example.com commit --quiet --allow-empty -m initial
        & git -C $project switch --quiet -c primary
        $base = Join-Path $TestDrive 'base'; $current = Join-Path $TestDrive 'current'
        $null = & git -C $project worktree add --quiet $base main
        $null = & git -C $project worktree add --quiet -b current $current main
        $output = & pwsh -NoLogo -NoProfile -File $cleanup -RepositoryPath $current -BaseBranch main -Apply 2>&1
        Test-Path $base | Should -BeTrue
        Test-Path $current | Should -BeTrue
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}
