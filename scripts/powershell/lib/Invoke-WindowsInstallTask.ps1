# Bootstrap a private Task runtime so a fresh Windows host needs only PowerShell and WinGet.
function Resolve-WindowsInstallTask {
    [CmdletBinding()]
    param()

    $command = Get-Command task -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $cache = Join-Path $env:LOCALAPPDATA 'dotfiles/tools/task'
    $executable = Join-Path $cache 'task.exe'
    if (Test-Path -LiteralPath $executable -PathType Leaf) { return $executable }

    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'amd64' }
    $release = Invoke-RestMethodSafe -Uri 'https://api.github.com/repos/go-task/task/releases/latest' -Headers @{ 'User-Agent' = 'dotfiles-installer' }
    $asset = $release.assets | Where-Object { $_.name -eq "task_windows_$architecture.zip" } | Select-Object -First 1
    if (-not $asset) { throw "Task release has no Windows $architecture archive." }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    try {
        $archive = Join-Path $temporary 'task.zip'
        Invoke-WebRequestSafe -Uri $asset.browser_download_url -OutFile $archive
        Expand-Archive -LiteralPath $archive -DestinationPath $temporary
        New-Item -ItemType Directory -Path $cache -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $temporary 'task.exe') -Destination $executable
    }
    finally {
        # Only remove the exact GUID directory created above.
        $temporaryParent = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($temporary))
        if ($temporaryParent -ne [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')) {
            throw 'Installer temporary directory is outside the temporary root.'
        }
        Remove-Item -LiteralPath $temporary -Recurse -Force
    }
    return $executable
}

function Invoke-WindowsInstallTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Repository, [Parameter(Mandatory)][hashtable]$Configuration)

    $task = Resolve-WindowsInstallTask
    $previousConfiguration = $env:DOTFILES_INSTALL_CONFIGURATION
    $previousShell = $env:DOTFILES_INSTALL_POWERSHELL
    $resultPath = [IO.Path]::GetTempFileName()
    try {
        # A per-invocation result avoids treating the expected reboot as a Task error.
        $invocationConfiguration = $Configuration.Clone()
        $invocationConfiguration['ResultPath'] = $resultPath
        $env:DOTFILES_INSTALL_CONFIGURATION = $invocationConfiguration | ConvertTo-Json -Depth 20 -Compress
        $env:DOTFILES_INSTALL_POWERSHELL = (Join-Path $PSHOME $(if ($PSVersionTable.PSVersion.Major -lt 6) { 'powershell.exe' } else { 'pwsh.exe' })).Replace('\', '/')
        Invoke-WindowsInstallTaskCommand -Executable $task -Arguments @('--dir', $Repository, '--taskfile', (Join-Path $Repository 'Taskfile.yml'), 'install:windows') | Out-Host
        if ([IO.File]::ReadAllText($resultPath).Trim() -eq 'RestartRequired') { return $true }
        if ($LASTEXITCODE -ne 0) { throw "Windows setup failed (Task exit=$LASTEXITCODE)." }
        Invoke-WindowsInstallTaskCommand -Executable $task -Arguments @('--dir', $Repository, '--taskfile', (Join-Path $Repository 'Taskfile.yml'), 'install:windows:post') | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "Windows post-install setup failed (Task exit=$LASTEXITCODE)." }
        return $false
    }
    finally {
        $env:DOTFILES_INSTALL_CONFIGURATION = $previousConfiguration
        $env:DOTFILES_INSTALL_POWERSHELL = $previousShell
        Remove-Item -LiteralPath $resultPath -Force -ErrorAction SilentlyContinue
    }
}
