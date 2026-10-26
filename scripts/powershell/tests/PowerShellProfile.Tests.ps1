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
