BeforeAll {
    $repoRoot = Split-Path -Parent $PSScriptRoot
}
Describe 'v2 standalone contract' {
    It 'creates a Task without project installation or a bundled Skill' {
        $project = Join-Path $TestDrive 'standalone'
        $null = New-Item -ItemType Directory $project
        & git -C $project init --quiet
        $output = & pwsh -NoLogo -NoProfile -File "$repoRoot/scripts/new-task.ps1" -ProjectPath $project -Name Standalone -Skill team-specific -TaskId standalone 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        Test-Path "$project/docs/codex/tasks/active/standalone/TASK.md" | Should -BeTrue
        Test-Path "$project/.codex-harness" | Should -BeFalse
        Test-Path "$project/AGENTS.md" | Should -BeFalse
    }
    It 'accepts a project with no harness artifacts in strict doctor' {
        $project = Join-Path $TestDrive 'detached'
        $null = New-Item -ItemType Directory $project
        & git -C $project init --quiet
        $output = & pwsh -NoLogo -NoProfile -File "$repoRoot/scripts/doctor.ps1" -Mode Project -Path $project -Strict 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
    }
}
Describe 'standalone write boundaries' {
    It 'supports an omitted Skill and leaves all installation artifacts absent' {
        $project = Join-Path $TestDrive 'omitted-skill'
        $null = New-Item -ItemType Directory $project
        & git -C $project init --quiet
        $output = & pwsh -NoLogo -NoProfile -File "$repoRoot/scripts/new-task.ps1" -ProjectPath $project -Name Optional -TaskId optional 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        (Get-Content "$project/docs/codex/tasks/active/optional/TASK.md" -Raw) | Should -Match 'skill: ""'
        foreach ($path in @('AGENTS.md', '.codex-harness/VERSION', '.agents/skills', 'docs/codex/DECISIONS.md', '.github/PULL_REQUEST_TEMPLATE.md')) {
            Test-Path (Join-Path $project $path) | Should -BeFalse
        }
    }
    It 'rejects a Git subdirectory and a linked write ancestor' {
        $project = Join-Path $TestDrive 'boundaries'; $external = Join-Path $TestDrive 'external'
        $null = New-Item -ItemType Directory $project, $external
        & git -C $project init --quiet
        $null = & pwsh -NoLogo -NoProfile -File "$repoRoot/scripts/new-task.ps1" -ProjectPath $external -Name Outside -TaskId outside 2>&1
        $LASTEXITCODE | Should -Be 1
        $sub = Join-Path $project 'sub'; $null = New-Item -ItemType Directory $sub
        $null = & pwsh -NoLogo -NoProfile -File "$repoRoot/scripts/new-task.ps1" -ProjectPath $sub -Name Sub -TaskId sub 2>&1
        $LASTEXITCODE | Should -Be 1
        Test-Path "$sub/docs" | Should -BeFalse
        $null = New-Item -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Path "$project/docs" -Target $external
        $null = & pwsh -NoLogo -NoProfile -File "$repoRoot/scripts/new-task.ps1" -ProjectPath $project -Name Linked -TaskId linked 2>&1
        $LASTEXITCODE | Should -Be 1
        @(Get-ChildItem $external -Force).Count | Should -Be 0
    }
    It 'rejects linked Handoff files without changing their external target' {
        $project = Join-Path $TestDrive 'handoff-leaf'; $null = New-Item -ItemType Directory $project
        & git -C $project init --quiet
        & git -C $project -c user.name=test -c user.email=test@example.com commit --quiet --allow-empty -m initial
        $null = & pwsh -NoLogo -NoProfile -File "$repoRoot/scripts/new-task.ps1" -ProjectPath $project -Name Leaf -TaskId leaf
        $path = "$project/docs/codex/tasks/active/leaf/HANDOFF.md"; $external = Join-Path $TestDrive 'external-handoff.md'
        Move-Item $path $external
        $before = [System.IO.File]::ReadAllText($external)
        $null = New-Item -ItemType SymbolicLink -Path $path -Target $external
        $null = & pwsh -NoLogo -NoProfile -File "$repoRoot/scripts/handoff.ps1" -ProjectPath $project 2>&1
        $LASTEXITCODE | Should -Be 1
        [System.IO.File]::ReadAllText($external) | Should -BeExactly $before
    }
}
