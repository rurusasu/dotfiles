# Prepare the declared PowerShell runtime before the production WinGet launcher.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) {
    throw 'Run the installer supervisor from stable Windows PowerShell 5.1.'
}
Set-Location -LiteralPath $env:GITHUB_WORKSPACE
. .\scripts\powershell\lib\Invoke-ExternalCommand.ps1

# Finish any PowerShell MSI update before launching the runtime it can terminate.
$master = Get-Content -LiteralPath windows/winget/packages.json -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = @(
    foreach ($source in $master.Sources) {
        foreach ($package in $source.Packages) {
            if ($package.PackageIdentifier -eq 'Microsoft.PowerShell') { @{ Source = $source; Package = $package } }
        }
    }
)
if ($runtime.Count -ne 1 -or $runtime[0].Source.SourceDetails.Name -ne 'winget') {
    throw 'Expected exactly one Microsoft.PowerShell declaration from winget.'
}
$master.Sources = @($runtime[0].Source.PSObject.Copy())
$master.Sources[0].Packages = @($runtime[0].Package)
$temporaryManifest = [IO.Path]::GetTempFileName()
try {
    [IO.File]::WriteAllText($temporaryManifest, ($master | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
    Import-WindowsPackage -ManifestPath $temporaryManifest
}
finally { Remove-Item -LiteralPath $temporaryManifest -Force -ErrorAction Stop }

$pwsh = Get-Command pwsh.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
$pwshMajor = @(Invoke-NativeCommand -Command $pwsh.Source -Arguments @('-NoLogo', '-NoProfile', '-Command', '$PSVersionTable.PSVersion.Major'))
if ($LASTEXITCODE -ne 0 -or ($pwshMajor -join '').Trim() -ne '7') {
    throw 'Selected pwsh.exe must report PowerShell 7 with exit code 0.'
}
$env:DOTFILES_PS7_DIR = Split-Path -Parent $pwsh.Source
$isWindowsPowerShell = $env:DOTFILES_E2E_POWERSHELL_VERSION -eq '5.1'
if ($isWindowsPowerShell) { $env:DOTFILES_FORCE_WINDOWS_POWERSHELL = '1' }
else { Remove-Item Env:\DOTFILES_FORCE_WINDOWS_POWERSHELL -ErrorAction SilentlyContinue }
$originalPath = @($env:PATH -split ';')
$output = @(Invoke-NativeCommand -Command cmd.exe -Arguments @('/d', '/c', 'install.cmd -Phase Winget') | ForEach-Object {
        $line = [string]$_
        Write-Host $line
        $line
    })
$exitCode = $LASTEXITCODE
if ($exitCode -ne 0) { exit $exitCode }
if (@($output | Where-Object { $_ -ceq '[Winget] WINGET_IMPORT_COMPLETED' }).Count -ne 1) {
    throw 'Windows installer must report exactly one native WinGet import completion marker.'
}
$text = $output -join [Environment]::NewLine
if (($isWindowsPowerShell -and $text -notmatch 'Using Windows PowerShell') -or
    (-not $isWindowsPowerShell -and $text -match 'Using Windows PowerShell|Falling back to Windows PowerShell')) {
    throw 'Windows installer did not use the selected runtime.'
}
Update-ProcessEnvironmentPath
$env:PATH -split ';' | Where-Object { $_ -and $originalPath -notcontains $_ } |
    Add-Content -LiteralPath $env:GITHUB_PATH -Encoding UTF8
