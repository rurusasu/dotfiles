BeforeAll {
    . (Join-Path $PSScriptRoot '../lib/Invoke-ExternalCommand.ps1')
    $script:repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    $script:chezmoi = (Get-Command chezmoi -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
    if (-not $script:chezmoi -and $env:LOCALAPPDATA) {
        $packages = Join-Path $env:LOCALAPPDATA 'Microsoft/WinGet/Packages'
        if (Test-Path -LiteralPath $packages) {
            $script:chezmoi = Get-ChildItem -LiteralPath $packages -Directory -Filter 'twpayne.chezmoi_*' |
                ForEach-Object { Join-Path $_.FullName 'chezmoi.exe' } |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        }
    }
    $script:childShell = (Get-Process -Id $PID).Path

    function New-DesktopDeploymentFixture {
        param([string]$Os = 'windows')
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString() + ' desktop deployment')
        $source = Join-Path $root 'repo/chezmoi'
        $localData = Join-Path $root 'local'
        $managed = Join-Path $localData 'dotfiles/keybindings'
        [void][IO.Directory]::CreateDirectory($source)
        [void][IO.Directory]::CreateDirectory($managed)
        $config = Join-Path $root 'chezmoi.toml'
        [IO.File]::WriteAllText($config, '')
        $contract = '{"bindings":[]}'
        $action = "# managed action 日本語`n"
        $sync = @'
param($ContractJson, $ActionScriptPath, [switch]$RestartPowerToys)
[IO.File]::WriteAllText((Join-Path $env:LOCALAPPDATA 'sync-reached.txt'), 'synced')
'@
        foreach ($entry in @(
                @{ Path = 'nix/home/keybindings/generated.json'; Content = $contract },
                @{ Path = 'scripts/powershell/Invoke-DesktopAction.ps1'; Content = $action },
                @{ Path = 'scripts/powershell/Sync-PowerToysKeyboard.ps1'; Content = $sync }
            )) {
            $path = Join-Path (Join-Path $root 'repo') $entry.Path
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
            [IO.File]::WriteAllText($path, $entry.Content, (New-Object Text.UTF8Encoding($false)))
        }
        $template = Join-Path $script:repoRoot 'chezmoi/.chezmoiscripts/deploy/keybindings/run_onchange_sync_powertoys_keyboard.ps1.tmpl'
        $override = @{ chezmoi = @{ os = $Os } } | ConvertTo-Json -Compress
        $arguments = @('--config', $config, '--source', $source, '--destination', (Join-Path $root 'destination'),
            '--cache', (Join-Path $root 'cache'), '--persistent-state', (Join-Path $root 'state.boltdb'),
            '--override-data', $override, 'execute-template', '--file', $template)
        $output = @(Invoke-ExternalCommandWithTimeout -Command $script:chezmoi -Arguments $arguments -TimeoutSeconds 30)
        $LASTEXITCODE | Should -Be 0 -Because ($output -join "`n")
        $rendered = $output -join "`n"
        $entryPoint = Join-Path $root 'deploy.ps1'
        $prefix = '$env:LOCALAPPDATA = ''' + $localData.Replace("'", "''") + "'`n"
        [IO.File]::WriteAllText($entryPoint, ($prefix + $rendered), (New-Object Text.UTF8Encoding($true)))
        [pscustomobject]@{
            Root = $root; Managed = $managed; EntryPoint = $entryPoint; Rendered = $rendered
            ActionPath = Join-Path $managed 'Invoke-DesktopAction.ps1'; Action = $action
            ContractPath = Join-Path $managed 'keybindings.json'; Contract = $contract
            SyncMarker = Join-Path $localData 'sync-reached.txt'
        }
    }

    function Invoke-DesktopDeploymentFixture {
        param($Fixture)
        $output = @(Invoke-ExternalCommandWithTimeout -Command $script:childShell -Arguments @(
                '-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Fixture.EntryPoint
            ) -TimeoutSeconds 30)
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = $output -join "`n" }
    }
}

Describe 'Desktop keybindings managed deployment' {
    It 'should stop before PowerToys sync and preserve the old <Target> when replacement fails' -ForEach @(
        @{ Target = 'ActionPath' }, @{ Target = 'ContractPath' }
    ) {
        if (-not $script:chezmoi) { Set-ItResult -Skipped -Because 'Native chezmoi is required to render the actual deployment template'; return }
        $fixture = New-DesktopDeploymentFixture
        [IO.File]::WriteAllText($fixture.ActionPath, $fixture.Action, (New-Object Text.UTF8Encoding($true)))
        [IO.File]::WriteAllText($fixture.ContractPath, $fixture.Contract, (New-Object Text.UTF8Encoding($false)))
        $destination = $fixture.$Target
        [IO.File]::WriteAllText($destination, 'old managed content')
        $original = [Convert]::ToBase64String([IO.File]::ReadAllBytes($destination))
        # Permit the content comparison, but deny replacement of the destination.
        $lock = [IO.File]::Open($destination, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            $result = Invoke-DesktopDeploymentFixture $fixture
        }
        finally { $lock.Dispose() }
        $result.ExitCode | Should -Not -Be 0 -Because $result.Output
        Test-Path -LiteralPath $fixture.SyncMarker | Should -BeFalse
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($destination)) | Should -BeExactly $original
        @(Get-ChildItem -LiteralPath $fixture.Managed -Filter '*.tmp').Count | Should -Be 0
    }

    It 'should deploy exact UTF-8 content and avoid rewriting managed files on repeated applies' {
        if (-not $script:chezmoi) { Set-ItResult -Skipped -Because 'Native chezmoi is required to render the actual deployment template'; return }
        $fixture = New-DesktopDeploymentFixture
        $result = Invoke-DesktopDeploymentFixture $fixture
        $result.ExitCode | Should -Be 0 -Because $result.Output
        Test-Path -LiteralPath $fixture.SyncMarker | Should -BeTrue
        [IO.File]::ReadAllText($fixture.ActionPath) | Should -BeExactly $fixture.Action
        [IO.File]::ReadAllText($fixture.ContractPath) | Should -BeExactly $fixture.Contract
        ([IO.File]::ReadAllBytes($fixture.ActionPath)[0..2] -join ',') | Should -BeExactly '239,187,191'
        [IO.File]::ReadAllBytes($fixture.ContractPath)[0] | Should -Be 123
        $fixedTime = [datetime]::SpecifyKind([datetime]'2020-01-01', [DateTimeKind]::Utc)
        foreach ($path in @($fixture.ActionPath, $fixture.ContractPath)) { [IO.File]::SetLastWriteTimeUtc($path, $fixedTime) }
        $result = Invoke-DesktopDeploymentFixture $fixture
        $result.ExitCode | Should -Be 0 -Because $result.Output
        foreach ($path in @($fixture.ActionPath, $fixture.ContractPath)) { [IO.File]::GetLastWriteTimeUtc($path) | Should -Be $fixedTime }
        @(Get-ChildItem -LiteralPath $fixture.Managed -Filter '*.tmp').Count | Should -Be 0
    }

    It 'should leave <Os> deployment to Nix' -ForEach @(@{ Os = 'linux' }, @{ Os = 'darwin' }) {
        if (-not $script:chezmoi) { Set-ItResult -Skipped -Because 'Native chezmoi is required to render the actual deployment template'; return }
        (New-DesktopDeploymentFixture -Os $Os).Rendered.Trim() | Should -BeNullOrEmpty
    }
}
