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

    function New-WslgFontRenderFixture {
        $root = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $source = Join-Path $root 'repo/chezmoi'
        $destination = Join-Path $root 'destination'
        $templates = @('dot_wslgconfig.tmpl', 'dot_config/dotfiles/wslg-fontconfig.conf.tmpl')
        foreach ($relative in $templates) {
            $original = Join-Path $script:repoRoot ('chezmoi/' + $relative)
            Test-Path -LiteralPath $original -PathType Leaf | Should -BeTrue -Because ('the managed template must exist: ' + $relative)
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

Describe 'WSLg Windows font configuration rendering' {
    It 'should convert <HomeDir> to a stable Windows-backed fontconfig path' -ForEach @(
        @{ HomeDir = 'C:\Users\tester'; Expected = '/mnt/c/Users/tester/.config/dotfiles/wslg-fontconfig.conf' },
        @{ HomeDir = 'D:\Users\Test User'; Expected = '/mnt/d/Users/Test User/.config/dotfiles/wslg-fontconfig.conf' },
        @{ HomeDir = 'e:/Profiles/Another User'; Expected = '/mnt/e/Profiles/Another User/.config/dotfiles/wslg-fontconfig.conf' }
    ) {
        if (-not $script:chezmoi) { Set-ItResult -Skipped -Because 'Native chezmoi is not installed; isolated rendering requires its real template engine'; return }
        $fixture = New-WslgFontRenderFixture
        $rendered = Invoke-WslgFontRender -Fixture $fixture -HomeDir $HomeDir -Command @('execute-template', '--file', (Join-Path $fixture.Source 'dot_wslgconfig.tmpl'))
        ($rendered -replace "`r", '').TrimEnd() | Should -BeExactly ("[system-distro-env]`nFONTCONFIG_FILE=" + $Expected)
        $rendered | Should -Not -Match '/mnt/wslg/distro'
    }

    It 'should include the repository-relative canonical XML without duplicating it in Windows source' {
        if (-not $script:chezmoi) { Set-ItResult -Skipped -Because 'Native chezmoi is not installed; isolated rendering requires its real template engine'; return }
        $fixture = New-WslgFontRenderFixture
        $relative = 'dot_config/dotfiles/wslg-fontconfig.conf.tmpl'
        $rendered = Invoke-WslgFontRender -Fixture $fixture -Command @('execute-template', '--file', (Join-Path $fixture.Source $relative))
        ($rendered -replace "`r", '').TrimEnd() | Should -BeExactly $fixture.Canonical.TrimEnd()
        [void][xml]$rendered
    }

    It 'should render the actual canonical fontconfig file unchanged' {
        if (-not $script:chezmoi) { Set-ItResult -Skipped -Because 'Native chezmoi is not installed; isolated rendering requires its real template engine'; return }
        $fixture = New-WslgFontRenderFixture
        $canonical = Join-Path $script:repoRoot 'nix/modules/fonts/wsl-fontconfig.conf'
        Test-Path -LiteralPath $canonical -PathType Leaf | Should -BeTrue
        $source = Join-Path $script:repoRoot 'chezmoi'
        $rendered = Invoke-WslgFontRender -Fixture $fixture -Source $source -Command @('execute-template', '--file', (Join-Path $source 'dot_config/dotfiles/wslg-fontconfig.conf.tmpl'))
        ($rendered -replace "`r", '').TrimEnd() | Should -BeExactly (([IO.File]::ReadAllText($canonical) -replace "`r", '').TrimEnd())
        [xml]$document = $rendered
        $document.DocumentElement.LocalName | Should -BeExactly 'fontconfig'
    }

    It 'should exclude Python caches while keeping Windows font files and Python source managed' {
        if (-not $script:chezmoi) { Set-ItResult -Skipped -Because 'Native chezmoi is not installed; isolated rendering requires its real template engine'; return }
        $fixture = New-WslgFontRenderFixture
        foreach ($relative in @('dot_hindsight/__pycache__/dummy.cpython-313.pyc', 'dummy.pyo', 'dot_hindsight/sourcecache/nested.pyc', 'dot_hindsight/sourcecache/config.py')) {
            $path = Join-Path $fixture.Source $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
            [IO.File]::WriteAllText($path, '# isolated fixture')
        }
        $managed = Invoke-WslgFontRender -Fixture $fixture -Command @('managed', '--path-style', 'relative')
        $paths = @($managed -split "`n" | ForEach-Object { ($_ -replace '\\', '/').Trim() })
        $paths | Should -Contain '.wslgconfig'
        $paths | Should -Contain '.config/dotfiles/wslg-fontconfig.conf'
        $paths | Should -Contain '.hindsight/sourcecache/config.py'
        @($paths | Where-Object { $_ -match '(^|/)__pycache__(/|$)|\.py[co]$' }).Count | Should -Be 0
    }

    It 'should leave <Os> deployment to Nix instead of managing these Windows files' -ForEach @(@{ Os = 'linux' }, @{ Os = 'darwin' }) {
        if (-not $script:chezmoi) { Set-ItResult -Skipped -Because 'Native chezmoi is not installed; isolated rendering requires its real template engine'; return }
        $fixture = New-WslgFontRenderFixture
        $managed = Invoke-WslgFontRender -Fixture $fixture -Os $Os -HomeDir '/home/tester' -Command @('managed', '--path-style', 'relative')
        $managed.Trim() | Should -BeNullOrEmpty
    }
}
