BeforeAll {
    $script:runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-DesktopAction.ps1'
    . $script:runtimePath -Action '__test_load_only__'
}

Describe 'WSL desktop launcher dispatch' {
    BeforeEach {
        $script:launches = [Collections.Generic.List[object]]::new()
        Mock Invoke-WslDesktopApplication {
            param([string]$Executable, [string[]]$Arguments)
            $script:launches.Add([pscustomobject]@{ Executable = $Executable; Arguments = @($Arguments) })
        }
        Mock Invoke-InstalledDesktopApp { throw 'Windows GUI fallback is not part of WSL application dispatch' }
        Mock Invoke-DesktopProcess { throw 'Direct Windows process launch is not part of WSL application dispatch' }
    }

    It 'should launch <Action> through the selected WSL application' -ForEach @(
        @{ Action = 'browser'; Executable = 'google-chrome'; Arguments = @('--new-window') },
        @{ Action = 'browser-private'; Executable = 'google-chrome'; Arguments = @('--incognito', '--new-window') },
        @{ Action = 'calendar'; Executable = 'google-chrome'; Arguments = @('--app=https://app.hey.com/calendar/weeks/') },
        @{ Action = 'email'; Executable = 'google-chrome'; Arguments = @('--app=https://app.hey.com/') },
        @{ Action = 'ai'; Executable = 'google-chrome'; Arguments = @('--app=https://chatgpt.com/') },
        @{ Action = 'messenger-google'; Executable = 'google-chrome'; Arguments = @('--app=https://messages.google.com/web/') },
        @{ Action = 'messenger-whatsapp'; Executable = 'google-chrome'; Arguments = @('--app=https://web.whatsapp.com/') },
        @{ Action = 'music'; Executable = 'spotify'; Arguments = @() },
        @{ Action = 'messenger-signal'; Executable = 'signal-desktop'; Arguments = @() },
        @{ Action = 'notes'; Executable = 'obsidian'; Arguments = @() },
        @{ Action = 'passwords'; Executable = '1password'; Arguments = @() }
    ) {
        Invoke-DesktopAction $Action
        $script:launches.Count | Should -Be 1
        $script:launches[0].Executable | Should -BeExactly $Executable
        ($script:launches[0].Arguments -join '|') | Should -BeExactly ($Arguments -join '|')
    }
}

Describe 'WSL shell argument quoting' {
    It 'should quote <Value> as one POSIX shell argument' -ForEach @(
        @{ Value = ''; Expected = "''" },
        @{ Value = 'ordinary'; Expected = "'ordinary'" },
        @{ Value = 'two words'; Expected = "'two words'" },
        @{ Value = 'a''b'; Expected = '''a''"''"''b''' },
        @{ Value = 'https://example.test/?a=1&b=$value;echo hello'; Expected = '''https://example.test/?a=1&b=$value;echo hello''' },
        @{ Value = 'literal $(echo unsafe) `echo unsafe`'; Expected = '''literal $(echo unsafe) `echo unsafe`''' }
    ) {
        ConvertTo-WslShellArgument -Value $Value | Should -BeExactly $Expected
    }

    It 'should preflight the executable and keep a hidden WSL exec session for the quoted application arguments' {
        $script:preflight = $null
        $script:launch = $null
        Mock Invoke-WslDesktopCommand { param([string]$ShellCommand) $script:preflight = $ShellCommand }
        Mock Invoke-DesktopProcess { param([string]$FilePath, [string[]]$Arguments, [switch]$Hidden) $script:launch = [pscustomobject]@{ FilePath = $FilePath; Arguments = $Arguments; Hidden = $Hidden.IsPresent } }
        Invoke-WslDesktopApplication -Executable 'google-chrome' -Arguments @('--new-window', 'https://example.test/?q=two words&name=O''Brien')
        $script:preflight | Should -Match 'command -v'
        $script:preflight.Contains("`r") | Should -BeFalse
        $script:launch.FilePath | Should -BeExactly (Join-Path $env:SystemRoot 'System32/wsl.exe')
        ($script:launch.Arguments[0..6] -join '|') | Should -Be '--distribution|NixOS|--cd|~|--exec|bash|-lc'
        $script:launch.Hidden | Should -BeTrue
        $script:shellCommand = $script:launch.Arguments[-1]
        $script:shellCommand | Should -Match '^exec '
        $script:shellCommand | Should -Match "'google-chrome'"
        $script:shellCommand | Should -Match "'--new-window'"
        $script:shellCommand | Should -Match ([regex]::Escape('''https://example.test/?q=two words&name=O''"''"''Brien'''))
        $script:shellCommand.Contains("`r") | Should -BeFalse
    }

    It 'should preserve a literal carriage return inside an application argument' {
        $script:shellCommand = $null
        Mock Invoke-WslDesktopCommand { }
        Mock Invoke-DesktopProcess { param([string]$FilePath, [string[]]$Arguments, [switch]$Hidden) $script:shellCommand = $Arguments[-1] }
        Invoke-WslDesktopApplication -Executable 'google-chrome' -Arguments @("first`rsecond")
        ([regex]::Matches($script:shellCommand, "`r")).Count | Should -Be 1
        $script:shellCommand.Contains("'first`rsecond'") | Should -BeTrue
    }

    It 'should stop before creating a persistent session when the WSL executable preflight fails' {
        $script:launches = 0
        Mock Invoke-WslDesktopCommand { throw 'Missing WSL application: google-chrome (127)' }
        Mock Invoke-DesktopProcess { $script:launches++ }
        { Invoke-WslDesktopApplication -Executable 'google-chrome' } | Should -Throw '*Missing WSL application*127*'
        $script:launches | Should -Be 0
    }

    It 'should avoid source carriage returns in preflight and exec scripts under Windows PowerShell 5.1' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 requires Windows'
            return
        }
        $probe = @'
param([string]$RuntimePath)
$ErrorActionPreference = 'Stop'
. $RuntimePath -Action '__test_load_only__'
function Invoke-WslDesktopCommand { param([string]$ShellCommand) $script:preflight = $ShellCommand }
function Invoke-DesktopProcess { param([string]$FilePath, [string[]]$Arguments, [switch]$Hidden) $script:captured = $Arguments[-1]; if (-not $Hidden) { throw 'WSL launch was not hidden' } }
Invoke-WslDesktopApplication -Executable google-chrome -Arguments @('--new-window', 'https://example.test/?x=1&y=two words')
if ($script:captured.Contains([string][char]13)) { throw 'A source CR leaked into the generated Bash script' }
if ($script:preflight.Contains([string][char]13)) { throw 'A source CR leaked into the generated preflight script' }
if (-not $script:preflight.Contains([string][char]10)) { throw 'Expected LF preflight separators' }
if (-not $script:captured.Contains("'https://example.test/?x=1&y=two words'")) { throw 'The URL was not preserved as a quoted shell argument' }
Write-Output 'WSL_LAUNCH_SCRIPT_OK'
'@
        $probePath = Join-Path $TestDrive 'wsl-launcher-probe.ps1'
        [IO.File]::WriteAllText($probePath, $probe, [Text.UTF8Encoding]::new($false))
        $exe = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $output = & $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probePath -RuntimePath $script:runtimePath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        $output -join [Environment]::NewLine | Should -Match 'WSL_LAUNCH_SCRIPT_OK'
    }
}

Describe 'WSLg browser and clipboard identity' {
    BeforeEach {
        Mock Initialize-DesktopNative { }
        Mock Get-DesktopWindowIdentity { $script:windowIdentity }
    }

    It 'should recognize a browser from its process and application identity instead of its title' -ForEach @(
        @{ ProcessName = 'chrome'; AppId = ''; Expected = $true },
        @{ ProcessName = 'msrdc'; AppId = 'Microsoft.WSLg.NixOS.google-chrome'; Expected = $true },
        @{ ProcessName = 'msrdc'; AppId = 'Microsoft.WSLg.NixOS.com.google.Chrome'; Expected = $true },
        @{ ProcessName = 'msrdc'; AppId = 'Microsoft.WSLg.NixOS.chrome-abcdefghijklmnopabcdefghijklmnop-Default'; Expected = $true },
        @{ ProcessName = 'msrdc'; AppId = 'Microsoft.WSLg.NixOS.com.mitchellh.ghostty'; Expected = $false },
        @{ ProcessName = 'msrdc'; AppId = ''; Expected = $false },
        @{ ProcessName = 'code'; AppId = 'com.google.Chrome'; Expected = $false }
    ) {
        $script:windowIdentity = [pscustomobject]@{ ProcessName = $ProcessName; AppId = $AppId; Title = 'Google Chrome - misleading title' }
        Test-DesktopBrowserWindow -Window ([IntPtr]42) | Should -Be $Expected
    }

    It 'should use ordinary clipboard keys for identified WSL GUI apps and terminal keys for Ghostty' -ForEach @(
        @{ AppId = 'Microsoft.WSLg.NixOS.google-chrome'; Expected = 'application' },
        @{ AppId = 'Microsoft.WSLg.NixOS.com.google.Chrome'; Expected = 'application' },
        @{ AppId = 'Microsoft.WSLg.NixOS.spotify'; Expected = 'application' },
        @{ AppId = 'Microsoft.WSLg.NixOS.signal-desktop'; Expected = 'application' },
        @{ AppId = 'Microsoft.WSLg.NixOS.obsidian'; Expected = 'application' },
        @{ AppId = 'Microsoft.WSLg.NixOS.1password'; Expected = 'application' },
        @{ AppId = 'Microsoft.WSLg.NixOS.com.onepassword.OnePassword'; Expected = 'application' },
        @{ AppId = 'Microsoft.WSLg.NixOS.com.mitchellh.ghostty'; Expected = 'ghostty' }
    ) {
        $script:windowIdentity = [pscustomobject]@{ ProcessName = 'msrdc'; AppId = $AppId }
        Get-DesktopClipboardContext -Window ([IntPtr]42) | Should -BeExactly $Expected
    }

    It 'should reject an unidentified WSLg clipboard target even when its title names Chrome' {
        $script:windowIdentity = [pscustomobject]@{ ProcessName = 'msrdc'; AppId = ''; Title = 'Google Chrome' }
        { Get-DesktopClipboardContext -Window ([IntPtr]42) } | Should -Throw '*Cannot safely identify*'
    }
}

Describe 'WSL desktop command process boundary' {
    BeforeEach {
        $script:startInfo = $null
        $script:commandResult = [pscustomobject]@{ ExitCode = 0; ErrorText = '' }
        Mock Invoke-WslDesktopProcess {
            param([Diagnostics.ProcessStartInfo]$StartInfo)
            $script:startInfo = $StartInfo
            $script:commandResult
        }
    }

    It 'should resolve the NixOS login environment and invoke WSL hidden without a shell association' {
        Invoke-WslDesktopCommand -ShellCommand "printf '%s' 'value with spaces'"
        $script:startInfo.FileName | Should -BeExactly (Join-Path $env:SystemRoot 'System32/wsl.exe')
        $script:startInfo.Arguments | Should -BeExactly '--distribution NixOS --cd ~ --exec bash -lc "printf ''%s'' ''value with spaces''"'
        $script:startInfo.UseShellExecute | Should -BeFalse
        $script:startInfo.CreateNoWindow | Should -BeTrue
        $script:startInfo.WindowStyle | Should -Be ([Diagnostics.ProcessWindowStyle]::Hidden)
        $script:startInfo.RedirectStandardError | Should -BeTrue
        $script:startInfo.StandardOutputEncoding.WebName | Should -Be 'utf-8'
        $script:startInfo.StandardErrorEncoding.WebName | Should -Be 'utf-8'
    }

    It 'should surface an immediate WSL application or distribution failure with stderr' {
        $script:commandResult = [pscustomobject]@{ ExitCode = 127; ErrorText = 'google-chrome is not available in the NixOS login PATH' }
        { Invoke-WslDesktopCommand -ShellCommand 'checked launch' } | Should -Throw '*127*google-chrome*'
    }

    It 'should retain WSL engine stdout diagnostics when stderr is null or empty' {
        $script:commandResult = [pscustomobject]@{ ExitCode = 1; ErrorText = $null; OutputText = 'WSL_E_DISTRO_NOT_FOUND: NixOS distribution is unavailable' }
        { Invoke-WslDesktopCommand -ShellCommand 'checked launch' } | Should -Throw '*WSL_E_DISTRO_NOT_FOUND*'
    }

    It 'should expose successful stdout only when the caller requests metadata' {
        $script:commandResult = [pscustomobject]@{ ExitCode = 0; ErrorText = ''; OutputText = 'metadata-line' }
        @(Invoke-WslDesktopCommand -ShellCommand 'metadata read').Count | Should -Be 0
        Invoke-WslDesktopCommand -ShellCommand 'metadata read' -PassThru | Should -BeExactly 'metadata-line'
    }
}

Describe 'WSLg server window metadata identity' {
    BeforeAll {
        $script:providerMetadata = @(
            '[21:45:38.082]     appListProviderName:NixOS'
            '[21:45:38.082]     appListProviderUniqueId:00000001-FACB-11E6-BD58-64006A7986D3'
        ) -join "`n"
        $script:serverWindowId = [uint64]4294967349 # provider 1, exact window 0x35
    }

    It 'should associate the observed Chrome app ID with both its exact provider and exact window' {
        $metadata = $script:providerMetadata + "`n[11:47:16.385] Client: ClientGetAppidReq: pid:0 appId:Google-chrome WindowId:0x35"
        ConvertFrom-DesktopWslgMetadata -Metadata $metadata -ServerWindowId $script:serverWindowId | Should -BeExactly 'Google-chrome'
    }

    It 'should reject another provider another window or incomplete provider metadata' -ForEach @(
        @{ Kind = 'provider' }, @{ Kind = 'window' }, @{ Kind = 'missing-provider' }, @{ Kind = 'provider-name' }
    ) {
        $metadata = $script:providerMetadata + "`n[11:47:16.385] Client: ClientGetAppidReq: pid:0 appId:Google-chrome WindowId:0x35"
        switch ($Kind) {
            'provider' { $metadata = $metadata.Replace('00000001-FACB', '00000002-FACB') }
            'window' { $metadata = $metadata.Replace('WindowId:0x35', 'WindowId:0x36') }
            'missing-provider' { $metadata = '[11:47:16.385] Client: ClientGetAppidReq: pid:0 appId:Google-chrome WindowId:0x35' }
            'provider-name' { $metadata = $metadata.Replace('appListProviderName:NixOS', 'appListProviderName:OtherDistro') }
        }
        ConvertFrom-DesktopWslgMetadata -Metadata $metadata -ServerWindowId $script:serverWindowId | Should -BeNullOrEmpty
    }

    It 'should use the latest exact window record without allowing another window to override it' {
        $metadata = $script:providerMetadata + "`n" + (@(
                '[11:47:16.385] Client: ClientGetAppidReq: pid:0 appId:Google-chrome WindowId:0x35'
                '[11:47:17.385] Client: ClientGetAppidReq: pid:0 appId:com.mitchellh.ghostty WindowId:0x35'
                '[11:47:18.385] Client: ClientGetAppidReq: pid:0 appId:Google-chrome WindowId:0x36'
            ) -join "`n")
        ConvertFrom-DesktopWslgMetadata -Metadata $metadata -ServerWindowId $script:serverWindowId | Should -BeExactly 'com.mitchellh.ghostty'
    }

    It 'should discard a prior match after malformed exact-window metadata or a new provider section' -ForEach @(
        @{ Kind = 'malformed' }, @{ Kind = 'new-provider' }
    ) {
        $metadata = $script:providerMetadata + "`n[11:47:16.385] Client: ClientGetAppidReq: pid:0 appId:Google-chrome WindowId:0x35`n"
        $metadata += if ($Kind -eq 'malformed') {
            '[11:47:17.385] Client: ClientGetAppidReq: pid:0 appId: WindowId:0x35'
        }
        else { '[11:47:17.385] appListProviderName:NixOS' }
        ConvertFrom-DesktopWslgMetadata -Metadata $metadata -ServerWindowId $script:serverWindowId | Should -BeNullOrEmpty
    }

    It 'should invalidate only the exact destroyed server window' -ForEach @(
        @{ Destroyed = '0x35'; Expected = '' }, @{ Destroyed = '0x36'; Expected = 'Google-chrome' }
    ) {
        $metadata = $script:providerMetadata + "`n[11:47:16.385] Client: ClientGetAppidReq: pid:0 appId:Google-chrome WindowId:0x35`n[11:47:17.385] WindowDestroy($Destroyed)"
        ConvertFrom-DesktopWslgMetadata -Metadata $metadata -ServerWindowId $script:serverWindowId | Should -BeExactly $Expected
    }
}

Describe 'WSLg pinned window metadata resolver' {
    BeforeEach {
        $script:windowIdReads = 0
        $script:serverWindowId = [uint64]4294967349
        $script:metadata = @(
            '[21:45:38.082] appListProviderName:NixOS'
            '[21:45:38.082] appListProviderUniqueId:00000001-FACB-11E6-BD58-64006A7986D3'
            '[11:47:16.385] Client: ClientGetAppidReq: pid:0 appId:Google-chrome WindowId:0x35'
        ) -join "`n"
        Mock Initialize-DesktopNative { }
        Mock Invoke-DesktopProcess { throw 'Metadata resolution must not launch a GUI session' }
        Mock Invoke-WslDesktopCommand { param([string]$ShellCommand, [switch]$PassThru) if (-not $PassThru) { throw 'Metadata reader did not request stdout' }; $script:metadata }
        if (Get-Command Get-DesktopWslgWindowId -ErrorAction SilentlyContinue) {
            Mock Get-DesktopWslgWindowId { param([IntPtr]$Window) if ($Window -ne [IntPtr]42) { throw 'Metadata lookup changed windows' }; $script:windowIdReads++; $script:serverWindowId }
        }
    }

    It 'should resolve the matching application without using a title or launching an app' {
        Resolve-DesktopWslgAppId -Window ([IntPtr]42) | Should -BeExactly 'Google-chrome'
        $script:windowIdReads | Should -BeGreaterOrEqual 2
    }

    It 'should reject a reused window after reading metadata' {
        Mock Get-DesktopWslgWindowId { $script:windowIdReads++; if ($script:windowIdReads -eq 1) { [uint64]4294967349 } else { [uint64]4294967350 } }
        Resolve-DesktopWslgAppId -Window ([IntPtr]42) | Should -BeNullOrEmpty
    }

    It 'should fail closed when WSL metadata is unavailable or the native property is absent' -ForEach @(
        @{ Kind = 'command-failure' }, @{ Kind = 'missing-property' }
    ) {
        if ($Kind -eq 'command-failure') { Mock Invoke-WslDesktopCommand { throw 'Weston metadata read failed' } }
        else { $script:serverWindowId = [uint64]0 }
        Resolve-DesktopWslgAppId -Window ([IntPtr]42) | Should -BeNullOrEmpty
        if ($Kind -eq 'missing-property') { Should -Invoke Invoke-WslDesktopCommand -Times 0 -Exactly }
    }

    It 'should normalize opaque remote identities once and preserve terminal safety under Windows PowerShell 5.1' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 requires Windows'
            return
        }
        $probe = @'
param([string]$RuntimePath)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
namespace DotfilesDesktop {
    public static class Native {
        public static string AppId = "Microsoft.RemoteApp." + new String('A', 43) + "=";
        public static uint GetWindowThreadProcessId(IntPtr window, out uint process) { process = 42; return 1; }
        public static string GetWindowAppId(IntPtr window) { return AppId; }
    }
}
"@
. $RuntimePath -Action '__test_load_only__'
function Get-Process { param([uint32]$Id, $ErrorAction) [pscustomobject]@{ ProcessName = $script:processName } }
function Resolve-DesktopWslgAppId { param([IntPtr]$Window) if ($Window -ne [IntPtr]42) { throw 'Resolver changed windows' }; $script:resolverCalls++; $script:linuxAppId }
$script:processName = 'msrdc'
$script:linuxAppId = 'Google-chrome'
$script:resolverCalls = 0
$identity = Get-DesktopWindowIdentity -Window ([IntPtr]42)
if ($identity.AppId -cne 'Google-chrome' -or $script:resolverCalls -ne 1) { throw 'Opaque AppID did not normalize from pinned metadata' }
$script:resolverCalls = 0
if ((Get-DesktopClipboardContext -Window ([IntPtr]42)) -ne 'application' -or $script:resolverCalls -ne 1) { throw 'Clipboard browser classification repeated the metadata read' }
$script:linuxAppId = 'com.mitchellh.ghostty'
if ((Get-DesktopClipboardContext -Window ([IntPtr]42)) -ne 'ghostty') { throw 'Terminal metadata lost its terminal clipboard keys' }
$script:linuxAppId = ''
$identity = Get-DesktopWindowIdentity -Window ([IntPtr]42)
if (Test-DesktopBrowserWindow -Window ([IntPtr]42) -Identity $identity) { throw 'Unresolved opaque identity was accepted as Chrome' }
$rejected = $false
try { [void](Get-DesktopClipboardContext -Window ([IntPtr]42)) } catch { if ($_.Exception.Message -notmatch 'Cannot safely identify') { throw }; $rejected = $true }
if (-not $rejected) { throw 'Unresolved remote clipboard target was accepted' }
$script:processName = 'chrome'
$script:resolverCalls = 0
[void](Get-DesktopWindowIdentity -Window ([IntPtr]42))
if ($script:resolverCalls -ne 0) { throw 'Native browser identity caused a WSL metadata read' }
Write-Output 'WSLG_IDENTITY_GUARD_OK'
'@
        $probePath = Join-Path $TestDrive 'wslg-identity-probe.ps1'
        [IO.File]::WriteAllText($probePath, $probe, [Text.UTF8Encoding]::new($false))
        $exe = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $output = & $exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probePath -RuntimePath $script:runtimePath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        $output -join [Environment]::NewLine | Should -Match 'WSLG_IDENTITY_GUARD_OK'
    }
}
