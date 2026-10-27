#Requires -Module Pester

Describe 'Windows environment integration' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        $script:repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
        . (Join-Path $PSScriptRoot '../lib/Invoke-ExternalCommand.ps1')
        $script:originalPath = $env:PATH
        Update-ProcessEnvironmentPath
    }

    AfterAll { $env:PATH = $script:originalPath }

    It 'should run the installed <Command> executable' -ForEach @(
        @{ Command = 'winget'; Arguments = @('--version') }
        @{ Command = 'task'; Arguments = @('--version') }
        @{ Command = 'pwsh'; Arguments = @('--version') }
        @{ Command = 'chezmoi'; Arguments = @('--version') }
        @{ Command = 'wezterm'; Arguments = @('--version') }
    ) {
        Get-Command -Name $Command -CommandType Application -ErrorAction Stop | Should -Not -BeNullOrEmpty
        $output = @(Invoke-ExternalCommandWithTimeout -Command $Command -Arguments $Arguments -TimeoutSeconds 120)
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        $output -join '' | Should -Match '\d+'
    }

    It 'should deploy the Windows configuration through real chezmoi apply and remain idempotent' {
        # Keep the real user's configuration and chezmoi state outside the test.
        $destination = Join-Path $TestDrive 'home'
        $config = Join-Path $TestDrive 'chezmoi.toml'
        $state = Join-Path $TestDrive 'chezmoi-state.boltdb'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        [IO.File]::WriteAllText($config, '')
        $chezmoi = (Get-Command chezmoi -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $source = Join-Path $script:repoRoot 'chezmoi'
        # Font registration belongs to installer E2E and changes the current user's registry.
        $targets = @(
            'Documents/PowerShell/Microsoft.PowerShell_profile.ps1'
            '.chezmoiscripts/deploy/terminals/run_onchange_deploy.ps1.tmpl'
        ) | ForEach-Object { Join-Path $source $_ }
        $arguments = @('--config', $config, '--source', $source,
            '--destination', $destination, '--persistent-state', $state, '--source-path', 'apply', '--force', '--parent-dirs') + $targets
        $originalProfile = $env:USERPROFILE
        $originalLocalAppData = $env:LOCALAPPDATA
        try {
            # Isolate application settings from the real user.
            $env:USERPROFILE = $destination
            $env:LOCALAPPDATA = Join-Path $TestDrive 'localappdata'
            $output = @(& $chezmoi @arguments 2>&1)
            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            $deployed = Join-Path $destination '.config/wezterm/wezterm.lua'
            Test-Path -LiteralPath $deployed -PathType Leaf | Should -BeTrue
            $expected = [IO.File]::ReadAllText((Join-Path $script:repoRoot 'chezmoi/terminals/wezterm/wezterm.lua'))
            ([IO.File]::ReadAllText($deployed) -replace "`r`n?", "`n").TrimEnd() |
                Should -BeExactly (($expected -replace "`r`n?", "`n").TrimEnd())
            @(Get-ChildItem -LiteralPath (Join-Path $destination '.config') -Recurse -File -Force).Count | Should -Be 1
            $first = [Convert]::ToBase64String([IO.File]::ReadAllBytes($deployed))
            $output = @(& $chezmoi @arguments 2>&1)
            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            [Convert]::ToBase64String([IO.File]::ReadAllBytes($deployed)) | Should -BeExactly $first
        }
        finally {
            $env:USERPROFILE = $originalProfile
            $env:LOCALAPPDATA = $originalLocalAppData
        }
    }
}

Describe 'NixOS WSL environment integration' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        $script:nixosAvailable = $false
        if (Get-Command wsl.exe -CommandType Application -ErrorAction SilentlyContinue) {
            $distros = @(& wsl.exe --list --quiet 2>$null)
            $script:nixosAvailable = $LASTEXITCODE -eq 0 -and @($distros | Where-Object {
                    ($_ -replace "`0", '' -replace [char]0xFEFF, '').Trim() -eq 'NixOS'
                }).Count -gt 0
        }
    }

    It 'should resolve <_> in an existing NixOS distribution' -ForEach @('nvim', 'task', 'op', 'obsidian') {
        if (-not $script:nixosAvailable) {
            Set-ItResult -Skipped -Because 'NixOS is not installed here; disposable distro setup is exercised by the WSL E2E job'
            return
        }
        $output = @(& wsl.exe -d NixOS -- bash -lc "command -v $_" 2>&1)
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        $output -join '' | Should -Not -BeNullOrEmpty
    }
}
