#Requires -Module Pester

Describe 'Windows environment integration' -Skip:([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    BeforeAll {
        $script:repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
    }

    It 'should merge Windows Terminal settings into <Case> through real chezmoi apply and remain idempotent' -ForEach @(
        @{ Case = 'a new home'; ExistingSettings = $false }
        @{ Case = 'existing JSONC settings'; ExistingSettings = $true }
    ) {
        # Keep the real user's configuration and chezmoi state outside the test.
        $destination = Join-Path $TestDrive 'home'
        $config = Join-Path $TestDrive 'chezmoi.toml'
        $state = Join-Path $TestDrive 'chezmoi-state.boltdb'
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        [IO.File]::WriteAllText($config, '')
        $chezmoi = (Get-Command chezmoi -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
        $source = Join-Path $script:repoRoot 'chezmoi'
        # Registry activation and font registration must not change the real user's state here.
        $terminalRelative = 'AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json'
        $fragmentRelative = 'AppData/Local/Microsoft/Windows Terminal/Fragments/dotfiles/catppuccin-mocha.json'
        $deployed = Join-Path $destination $terminalRelative
        if ($ExistingSettings) {
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $deployed))
            $existing = @'
{
  // Windows Terminal accepts comments and trailing commas.
  "defaultProfile": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
  "copyOnSelect": true,
  "profiles": {
    "defaults": { "historySize": 8000, "font": { "weight": "semi-bold" } },
    "list": [
      { "guid": "{aa4bf240-2b1a-43c6-b629-665bf0f882dd}", "name": "Custom", "commandline": "cmd.exe" },
      { "guid": "{d3878e06-fc60-4fae-9f1c-fd03391609ca}", "name": "NixOS", "source": "Microsoft.WSL" },
    ],
  },
  "keybindings": [{ "keys": "ctrl+alt+q", "id": "Terminal.NewTab" }],
}
'@
            [IO.File]::WriteAllText($deployed, $existing, [Text.UTF8Encoding]::new($false))
        }
        $targets = @(
            'Documents/PowerShell/Microsoft.PowerShell_profile.ps1'
            'AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/modify_settings.json'
            $fragmentRelative
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
            Test-Path -LiteralPath $deployed -PathType Leaf | Should -BeTrue
            $settings = Get-Content -LiteralPath $deployed -Raw | ConvertFrom-Json
            $settings.defaultProfile | Should -Be '{574e775e-4f2a-5b96-ac1e-a2962a402336}'
            $settings.profiles.defaults.font.face | Should -Be 'UDEV Gothic NF'
            $settings.profiles.defaults.font.size | Should -Be 10
            $settings.profiles.defaults.opacity | Should -Be 75
            $fragment = Get-Content -LiteralPath (Join-Path $destination $fragmentRelative) -Raw | ConvertFrom-Json
            $settings.profiles.defaults.colorScheme | Should -Be $fragment.schemes[0].name
            if ($ExistingSettings) {
                $settings.copyOnSelect | Should -BeTrue
                $settings.profiles.defaults.historySize | Should -Be 8000
                $settings.profiles.defaults.font.weight | Should -Be 'semi-bold'
                @($settings.profiles.list).Count | Should -Be 2
                $settings.profiles.list[0].commandline | Should -Be 'cmd.exe'
                $settings.profiles.list[1].guid | Should -Be '{d3878e06-fc60-4fae-9f1c-fd03391609ca}'
                $settings.profiles.list[1].source | Should -Be 'Microsoft.WSL'
                $settings.keybindings[0].keys | Should -Be 'ctrl+alt+q'
            }
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

Describe 'Windows common shell commands' {
    BeforeAll {
        $script:profilePath = Join-Path $PSScriptRoot '../../../chezmoi/Documents/PowerShell/Microsoft.PowerShell_profile.ps1'
    }

    BeforeEach {
        # A separate runspace keeps aliases, functions and cwd out of the test runner.
        $script:shell = [powershell]::Create()
        $script:shell.Runspace.SessionStateProxy.SetVariable('ProfileTestSource', (Join-Path $TestDrive 'source repo/chezmoi'))
        $script:shell.AddScript(@'
foreach ($command in 'eza', 'rg', 'fd', 'lazygit', 'kubectl', 'kubectx', 'kubens', 'task') {
    $body = [scriptblock]::Create(@"
[pscustomobject]@{ Command = '$command'; Arguments = @(`$args); Directory = (Get-Location).Path }
`$global:LASTEXITCODE = 17
"@)
    Set-Item -Path "function:global:$command.exe" -Value $body
}
function global:chezmoi.exe { $global:LASTEXITCODE = 0; $global:ProfileTestSource }
'@).Invoke() | Out-Null
        $script:shell.Commands.Clear()
        $script:shell.AddScript([IO.File]::ReadAllText($script:profilePath)).Invoke() | Out-Null
        $script:shell.HadErrors | Should -BeFalse -Because ($script:shell.Streams.Error -join "`n")
        $script:shell.Commands.Clear()
    }

    AfterEach { $script:shell.Dispose() }

    It 'should forward <Name> options and paths with spaces to the Windows executable' -ForEach @(
        @{ Name = 'eza'; Command = 'eza'; Options = @('--icons', 'auto', '--color', 'auto', '--tree') }
        @{ Name = 'ls'; Command = 'eza'; Options = @('--icons', 'auto', '--color', 'auto', '--tree', '--level=1') }
        @{ Name = 'll'; Command = 'eza'; Options = @('--icons', 'auto', '--color', 'auto', '--tree', '--level=1', '--group-directories-first', '--time-style=long-iso') }
        @{ Name = 'la'; Command = 'eza'; Options = @('--icons', 'auto', '--color', 'auto', '--tree', '--level=1', '--group-directories-first', '--time-style=long-iso', '--git', '--hyperlink', '-F') }
        @{ Name = 'lt'; Command = 'eza'; Options = @('--icons', 'auto', '--color', 'auto', '--tree', '--level=2', '--group-directories-first', '--time-style=long-iso', '--git') }
        @{ Name = 'lla'; Command = 'eza'; Options = @('--icons', 'auto', '--color', 'auto', '--tree', '-la') }
        @{ Name = 'grep'; Command = 'rg'; Options = @() }
        @{ Name = 'find'; Command = 'fd'; Options = @() }
        @{ Name = 'lg'; Command = 'lazygit'; Options = @() }
        @{ Name = 'k'; Command = 'kubectl'; Options = @() }
        @{ Name = 'kgn'; Command = 'kubectl'; Options = @('get', 'nodes') }
        @{ Name = 'kgp'; Command = 'kubectl'; Options = @('get', 'pods', '-A') }
        @{ Name = 'kgs'; Command = 'kubectl'; Options = @('get', 'svc', '-A') }
        @{ Name = 'kctx'; Command = 'kubectx'; Options = @() }
        @{ Name = 'kns'; Command = 'kubens'; Options = @() }
    ) {
        $script:shell.AddCommand($Name).AddArgument('directory with spaces').AddArgument('--help') | Out-Null
        $actual = @($script:shell.Invoke())
        $script:shell.HadErrors | Should -BeFalse -Because ($script:shell.Streams.Error -join "`n")
        $actual.Count | Should -Be 1
        $actual[0].Command | Should -Be $Command
        ($actual[0].Arguments -join '|') | Should -Be ((@($Options) + @('directory with spaces', '--help')) -join '|')
        $script:shell.Commands.Clear()
        $script:shell.AddScript('$global:LASTEXITCODE').Invoke()[0] | Should -Be 17
    }

    It 'should run dotf in the chezmoi source repository without changing the current directory' {
        $script:shell.AddScript('(Get-Location).Path') | Out-Null
        $originalDirectory = $script:shell.Invoke()[0]
        $script:shell.Commands.Clear()
        $script:shell.AddCommand('dotf').AddArgument('test:powershell').AddArgument('ARG=two words') | Out-Null
        $actual = @($script:shell.Invoke())
        $script:shell.HadErrors | Should -BeFalse -Because ($script:shell.Streams.Error -join "`n")
        $actual.Count | Should -Be 1
        $actual[0].Command | Should -Be 'task'
        ($actual[0].Arguments -join '|') | Should -Be ((@('--dir', (Join-Path $TestDrive 'source repo'), 'test:powershell', 'ARG=two words')) -join '|')
        $actual[0].Directory | Should -Be $originalDirectory
        $script:shell.Commands.Clear()
        $script:shell.AddScript('(Get-Location).Path').Invoke()[0] | Should -Be $originalDirectory
    }

    It 'should stop dotf when chezmoi cannot resolve its source' {
        $script:shell.AddScript('function global:chezmoi.exe { $global:LASTEXITCODE = 9 }').Invoke() | Out-Null
        $script:shell.Commands.Clear()
        $script:shell.AddCommand('dotf').AddArgument('fmt') | Out-Null
        @($script:shell.Invoke()).Count | Should -Be 0
        $script:shell.Commands.Clear()
        $script:shell.AddScript('$global:LASTEXITCODE').Invoke()[0] | Should -Be 9
    }
}

# Isolated rendering requires the installed native chezmoi template engine.
Describe 'WSLg Windows font configuration rendering' -Skip:(-not (Get-Command chezmoi -CommandType Application -ErrorAction SilentlyContinue)) {
    BeforeAll {
        . (Join-Path $PSScriptRoot '../lib/Invoke-ExternalCommand.ps1')
        $script:repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
        $script:chezmoi = (Get-Command chezmoi -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source

        function New-WslgFontRenderFixture {
            $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            $source = Join-Path $root 'repo/chezmoi'
            $destination = Join-Path $root 'destination'
            $templates = @('dot_wslgconfig.tmpl', 'dot_config/dotfiles/wslg-fontconfig.conf.tmpl')
            foreach ($relative in $templates) {
                $original = Join-Path $script:repoRoot ('chezmoi/' + $relative)
                $copy = Join-Path $source $relative
                [void][IO.Directory]::CreateDirectory((Split-Path -Parent $copy))
                Copy-Item -LiteralPath $original -Destination $copy
            }
            Copy-Item -LiteralPath (Join-Path $script:repoRoot 'chezmoi/.chezmoiignore.tmpl') -Destination $source
            $canonical = Join-Path $root 'repo/nix/modules/fonts/wsl-fontconfig.conf'
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $canonical))
            $xml = "<?xml version=`"1.0`"?>`n<fontconfig><!-- canonical fixture --><dir>/fixture/fonts</dir></fontconfig>`n"
            [IO.File]::WriteAllText($canonical, $xml, (New-Object Text.UTF8Encoding($false)))
            [void][IO.Directory]::CreateDirectory($destination)
            $config = Join-Path $root 'chezmoi.toml'
            [IO.File]::WriteAllText($config, '')
            [pscustomobject]@{ Root = $root; Source = $source; Destination = $destination; Config = $config; Canonical = $xml }
        }

        function Invoke-WslgFontRender {
            param([object]$Fixture, [string]$HomeDir = 'C:\Users\tester', [string]$Os = 'windows', [string[]]$Command, [string]$Source = '')
            if (-not $Source) { $Source = $Fixture.Source }
            $override = @{ chezmoi = @{ os = $Os; homeDir = $HomeDir } } | ConvertTo-Json -Compress
            $arguments = @('--config', $Fixture.Config, '--config-format', 'toml', '--source', $Source,
                '--destination', $Fixture.Destination, '--cache', (Join-Path $Fixture.Root 'cache'),
                '--persistent-state', (Join-Path $Fixture.Root 'state.boltdb'), '--override-data', $override) + $Command
            $output = @(Invoke-ExternalCommandWithTimeout -Command $script:chezmoi -Arguments $arguments -TimeoutSeconds 30)
            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            $output -join "`n"
        }
    }

    It 'should convert <HomeDir> to a stable Windows-backed fontconfig path' -ForEach @(
        @{ HomeDir = 'C:\Users\tester'; Expected = '/mnt/c/Users/tester/.config/dotfiles/wslg-fontconfig.conf' },
        @{ HomeDir = 'D:\Users\Test User'; Expected = '/mnt/d/Users/Test User/.config/dotfiles/wslg-fontconfig.conf' },
        @{ HomeDir = 'e:/Profiles/Another User'; Expected = '/mnt/e/Profiles/Another User/.config/dotfiles/wslg-fontconfig.conf' }
    ) {
        $fixture = New-WslgFontRenderFixture
        $rendered = Invoke-WslgFontRender -Fixture $fixture -HomeDir $HomeDir -Command @('execute-template', '--file', (Join-Path $fixture.Source 'dot_wslgconfig.tmpl'))
        ($rendered -replace "`r", '').TrimEnd() | Should -BeExactly ("[system-distro-env]`nFONTCONFIG_FILE=" + $Expected)
        $rendered | Should -Not -Match '/mnt/wslg/distro'
    }

    It 'should include the repository-relative canonical XML without duplicating it in Windows source' {
        $fixture = New-WslgFontRenderFixture
        $relative = 'dot_config/dotfiles/wslg-fontconfig.conf.tmpl'
        $rendered = Invoke-WslgFontRender -Fixture $fixture -Command @('execute-template', '--file', (Join-Path $fixture.Source $relative))
        ($rendered -replace "`r", '').TrimEnd() | Should -BeExactly $fixture.Canonical.TrimEnd()
        [void][xml]$rendered
    }

    It 'should render the actual canonical fontconfig file unchanged' {
        $fixture = New-WslgFontRenderFixture
        $canonical = Join-Path $script:repoRoot 'nix/modules/fonts/wsl-fontconfig.conf'
        $source = Join-Path $script:repoRoot 'chezmoi'
        $rendered = Invoke-WslgFontRender -Fixture $fixture -Source $source -Command @('execute-template', '--file', (Join-Path $source 'dot_config/dotfiles/wslg-fontconfig.conf.tmpl'))
        ($rendered -replace "`r", '').TrimEnd() | Should -BeExactly (([IO.File]::ReadAllText($canonical) -replace "`r", '').TrimEnd())
        [xml]$document = $rendered
        $document.DocumentElement.LocalName | Should -BeExactly 'fontconfig'
    }

    It 'should leave <Os> deployment to Nix instead of managing these Windows files' -ForEach @(@{ Os = 'linux' }, @{ Os = 'darwin' }) {
        $fixture = New-WslgFontRenderFixture
        $managed = Invoke-WslgFontRender -Fixture $fixture -Os $Os -HomeDir '/home/tester' -Command @('managed', '--path-style', 'relative')
        $managed.Trim() | Should -BeNullOrEmpty
    }
}
