BeforeAll {
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'lib/Invoke-ExternalCommand.ps1')
}

Describe 'Windows installer WSL foundation elevation' -Skip:($env:OS -ne 'Windows_NT') {
    It 'should preserve the script path and phase when launching UAC from a path with spaces' {
        Mock Test-IsAdminSession { return $false }
        $script:elevationArguments = @()
        $script:elevationRequest = @{}
        Mock Start-Process {
            param($FilePath, $ArgumentList, $Verb, $WindowStyle, $Wait, $PassThru)
            $script:elevationArguments = $ArgumentList
            $script:elevationRequest = @{ FilePath = $FilePath; Verb = $Verb; WindowStyle = $WindowStyle; Wait = $Wait; PassThru = $PassThru }
            return [pscustomobject]@{ ExitCode = 3010 }
        }
        $result = Invoke-WslBaseElevation -ScriptPath 'C:\checkout with spaces\Invoke-WindowsInstallPhase.ps1'
        $result | Should -Be 3010
        $script:elevationRequest.FilePath | Should -Match '(?:powershell|pwsh)\.exe$'
        $script:elevationRequest.Verb | Should -Be 'RunAs'
        $script:elevationRequest.WindowStyle | Should -Be 'Hidden'
        $script:elevationRequest.Wait | Should -BeTrue
        $script:elevationRequest.PassThru | Should -BeTrue
        $script:elevationArguments | Should -Be @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
            '"C:\checkout with spaces\Invoke-WindowsInstallPhase.ps1"', '-Phase', 'WslBase'
        )
    }
}
