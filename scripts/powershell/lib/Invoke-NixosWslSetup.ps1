# Windows owns checkout synchronization; Nix owns the host configuration.
function Install-NixosWsl {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [string]$DistroName = 'NixOS',
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$InstallDir,
        [string]$ReleaseTag = ''
    )

    if ([string]::IsNullOrWhiteSpace($InstallDir)) {
        throw 'The NixOS-WSL install directory must not be empty.'
    }
    $installPath = [IO.Path]::GetFullPath($InstallDir)
    $listOutput = @(Invoke-Wsl -TimeoutSeconds 5 -Arguments @('--list', '--quiet'))
    if ($LASTEXITCODE -ne 0) {
        throw "Could not list WSL distributions (exit=$LASTEXITCODE): $($listOutput -join [Environment]::NewLine)"
    }
    $distros = $listOutput | ForEach-Object {
        ([string]$_ -replace "`0", '' -replace [char]0xFEFF, '') -split '\r?\n'
    } | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    if ($distros -contains $DistroName) { return }

    if (Test-Path -LiteralPath $installPath) {
        if (-not (Test-Path -LiteralPath $installPath -PathType Container)) {
            throw "The NixOS-WSL install location is not a directory: $installPath"
        }
        $vhdPath = Join-Path $installPath 'ext4.vhdx'
        if (Test-Path -LiteralPath $vhdPath -PathType Leaf) {
            $output = @(Invoke-Wsl -Arguments @('--import-in-place', $DistroName, $vhdPath))
            if ($LASTEXITCODE -ne 0) {
                throw "WSL VHD registration failed (exit=$LASTEXITCODE): $($output -join [Environment]::NewLine)"
            }
            $output | Out-Host
            return
        }
        if (@(Get-ChildItem -LiteralPath $installPath -Force -ErrorAction Stop).Count -gt 0) {
            throw "The NixOS-WSL install directory is not empty: $installPath"
        }
    }

    $releaseBase = 'https://api.github.com/repos/nix-community/NixOS-WSL/releases'
    $releaseUri = if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
        "$releaseBase/latest"
    }
    else {
        "$releaseBase/tags/$([Uri]::EscapeDataString($ReleaseTag))"
    }
    $downloadPath = Join-Path ([IO.Path]::GetTempPath()) ('nixos-' + [Guid]::NewGuid().ToString('N') + '.wsl')
    $releasePath = "$downloadPath.json"
    # Windows includes curl.exe under both supported PowerShell runtimes.
    # Use its transient HTTP retry policy; never retry WSL registration.
    $curlArguments = @(
        '--fail', '--location', '--silent', '--show-error',
        '--proto', '=https', '--proto-redir', '=https',
        '--retry', '5', '--retry-delay', '15', '--retry-max-time', '300',
        '--connect-timeout', '30',
        '--user-agent', 'nixos-wsl-installer'
    )
    try {
        # File output lets curl discard an incomplete response before retrying.
        Invoke-NativeCommand -Command 'curl.exe' -Arguments ($curlArguments + @('--max-time', '120', '--output', $releasePath, $releaseUri)) | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "NixOS-WSL release query failed (exit=$LASTEXITCODE)." }
        $release = Get-Content -LiteralPath $releasePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $asset = $release.assets | Where-Object { $_.name -eq 'nixos.wsl' } | Select-Object -First 1
        if (-not $asset) {
            throw "Release $($release.tag_name) does not contain nixos.wsl. Use latest or a ReleaseTag that provides nixos.wsl."
        }
        Invoke-NativeCommand -Command 'curl.exe' -Arguments ($curlArguments + @('--max-time', '1800', '--output', $downloadPath, $asset.browser_download_url)) | Out-Host
        if ($LASTEXITCODE -ne 0) { throw "NixOS-WSL download failed (exit=$LASTEXITCODE)." }
        if (-not (Test-Path -LiteralPath $installPath)) {
            New-Item -ItemType Directory -Path $installPath -ErrorAction Stop | Out-Null
        }
        $output = @(Invoke-Wsl -Arguments @('--install', '--from-file', $downloadPath, '--name', $DistroName, '--location', $installPath, '--no-launch'))
        if ($LASTEXITCODE -ne 0) {
            throw "WSL installation from nixos.wsl failed (exit=$LASTEXITCODE): $($output -join [Environment]::NewLine)"
        }
        $output | Out-Host
    }
    finally {
        Remove-Item -LiteralPath $downloadPath, $releasePath -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-NixosWslSetup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Repository,
        [ValidateNotNullOrEmpty()]
        [string]$DistroName = 'NixOS',
        [ValidateSet('link', 'repo', 'nix', 'none')]
        [string]$SyncMode = 'link',
        [ValidateSet('repo', 'lock', 'none')]
        [string]$SyncBack = 'lock',
        [switch]$ForcePostInstall,
        [ValidateRange(0, 2147483647)]
        [int]$TimeoutSeconds = 1800,
        [string]$FlakeReference = '',
        [string]$SourceDirectory = '',
        [bool]$AllowBuilds = $true
    )
    function ConvertTo-WslArgument([string]$Value) {
        return "'" + $Value.Replace("'", "'\''") + "'"
    }
    if ($SourceDirectory -and ($SourceDirectory -notmatch '^/[^\r\n]*$' -or $SyncBack -ne 'none')) {
        throw 'A Linux source directory requires an absolute path and SyncBack none.'
    }
    if ($FlakeReference -and $FlakeReference -notmatch '^[^\r\n#]+#[A-Za-z0-9_-]+$') {
        throw 'FlakeReference must select a named configuration.'
    }
    $buildGuard = if ($AllowBuilds) { '' } else {
        'export NIX_CONFIG="${NIX_CONFIG-}"$''\nmax-jobs = 0\nbuilders =\nfallback = false''; '
    }
    function Invoke-SetupCommand([string]$Command) {
        # Bypass WSL's default shell and keep profile banners out of machine-readable output.
        $output = @(Invoke-Wsl -TimeoutSeconds $timeoutSeconds -Arguments @(
                '-d', $DistroName, '-u', 'root', '--exec', 'bash', '-c',
                ". /etc/profile >/dev/null || exit; set -euo pipefail; $buildGuard$Command"
            ))
        if ($LASTEXITCODE -ne 0) {
            $exitCode = $LASTEXITCODE
            # Keep the full output searchable without flooding the terminal with dependency failures.
            $plainOutput = @($output | ForEach-Object { [string]$_ -replace '\x1B\[[0-?]*[ -/]*[@-~]', '' })
            $firstError = $plainOutput | Select-String -Pattern '(?i)\berror:|\berror\[|\bfatal:|\bundefined:|hash mismatch|タイムアウト' | Select-Object -First 1
            $summaryLines = if ($firstError) { $plainOutput | Select-Object -Skip ([Math]::Max(0, $firstError.LineNumber - 4)) -First 24 } else { $plainOutput | Select-Object -Last 20 }
            $summary = $summaryLines -join [Environment]::NewLine
            $logPath = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-wsl-' + [Guid]::NewGuid().ToString('N') + '.log')
            try {
                [IO.File]::WriteAllLines($logPath, [string[]]$plainOutput, [Text.UTF8Encoding]::new($false))
            }
            catch {
                throw "NixOS-WSL setup failed (exit=$exitCode):`n$summary`nCould not save full log: $($_.Exception.Message)"
            }
            throw "NixOS-WSL setup failed (exit=$exitCode):`n$summary`nFull log: $logPath"
        }
        return $output
    }

    if ($syncMode -eq 'nix' -and $syncBack -eq 'repo') {
        throw 'SyncMode nix requires SyncBack lock or none.'
    }

    if ($SourceDirectory) {
        # A prepared immutable deployment can synchronize its exact Linux store
        # snapshot without converting it through a Windows working tree.
        $source = $SourceDirectory
    }
    else {
        $sourceOutput = @(Invoke-Wsl -TimeoutSeconds $TimeoutSeconds -Arguments @(
                '-d', $DistroName, '-u', 'root', '--exec', 'wslpath', '-a',
                ([IO.Path]::GetFullPath($Repository).Replace('\', '/'))
            ))
        $source = $sourceOutput | ForEach-Object { ([string]$_ -replace "`0", '' -replace [char]0xFEFF, '').Trim() } |
            Where-Object { $_ -match '^/' } | Select-Object -First 1
        if ($LASTEXITCODE -ne 0 -or -not $source) {
            throw 'Could not resolve the Windows checkout inside WSL.'
        }

    }

    $currentUserOutput = @(Invoke-Wsl -TimeoutSeconds $TimeoutSeconds -Arguments @('-d', $DistroName, '--exec', '/run/current-system/sw/bin/id', '-un'))
    $currentUser = [string]($currentUserOutput | Where-Object { [string]$_ -match '^[a-zA-Z_][a-zA-Z0-9_.-]*[$]?$' } | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0 -or -not $currentUser) { throw 'Could not resolve the current WSL default user.' }
    $accountOutput = @(Invoke-SetupCommand "getent passwd $(ConvertTo-WslArgument $currentUser)")
    $accountLine = $accountOutput | Where-Object { $_ -match '^[^:]+:[^:]*:[0-9]+:[0-9]+:' } | Select-Object -First 1
    if (-not $accountLine) { throw 'Could not resolve the NixOS-WSL user account.' }
    $account = ([string]$accountLine).Split(':')
    $user = $account[0]
    $userHome = $account[5]
    if ($userHome -notmatch '^/') { throw 'The NixOS user home must be an absolute path.' }
    $repo = "$userHome/.dotfiles"

    # Validate the declaration being applied; none retains the independent WSL checkout.
    $userFlake = if ($syncMode -eq 'none') { $repo } else { $source }
    $selectedFlake = if ($FlakeReference) { $FlakeReference } else { 'path:' + $userFlake + '#wsl' }
    $selection = $selectedFlake.LastIndexOf('#')
    $configurationRoot = $selectedFlake.Substring(0, $selection)
    $configurationName = $selectedFlake.Substring($selection + 1)
    $userAttribute = ConvertTo-WslArgument ($configurationRoot + '#nixosConfigurations.' + $configurationName + '.config.wsl.defaultUser')
    $userOutput = @(Invoke-SetupCommand "nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw $userAttribute --impure --no-update-lock-file")
    $declaredUser = [string]($userOutput | Where-Object { [string]$_ -match '^[a-zA-Z_][a-zA-Z0-9_.-]*[$]?$' } | Select-Object -Last 1)
    if (-not $declaredUser) { throw 'Could not resolve the declared wsl.defaultUser.' }
    if ($currentUser -ne $declaredUser) {
        throw "WSL user '$currentUser' differs from declared wsl.defaultUser '$declaredUser'. Change it using nixos-rebuild boot and the official WSL restart procedure before running setup: https://nix-community.github.io/NixOS-WSL/how-to/change-username.html"
    }

    $group = @(Invoke-SetupCommand "id -gn $(ConvertTo-WslArgument $user)") | Select-Object -Last 1
    $qRepo = ConvertTo-WslArgument $repo
    $qSource = ConvertTo-WslArgument $source
    $qOwner = ConvertTo-WslArgument "${user}:$group"

    # Preserve conflicting checkouts even when ForcePostInstall is requested.
    $backup = if ($ForcePostInstall) {
        "mv -- $qRepo $(ConvertTo-WslArgument ($repo + '.backup-' + [Guid]::NewGuid().ToString('N')))"
    }
    else {
        'echo "Existing checkout conflicts with the requested sync mode; use ForcePostInstall to back it up." >&2; exit 1'
    }
    switch ($syncMode) {
        'link' {
            Invoke-SetupCommand "if [ -L $qRepo ] && [ `"`$(readlink -f -- $qRepo)`" = $qSource ]; then :; else if [ -e $qRepo ] || [ -L $qRepo ]; then $backup; fi; ln -s -- $qSource $qRepo; fi; chown -h -- $qOwner $qRepo" | Out-Host
        }
        'repo' {
            Invoke-SetupCommand "if [ -L $qRepo ] || { [ -d $qRepo ] && [ -n `"`$(ls -A -- $qRepo)`" ]; } || [ -f $qRepo ]; then $backup; fi; mkdir -p -- $qRepo; (cd $qSource && tar --exclude=.git --exclude=.direnv --exclude=result -cf - .) | (cd $qRepo && tar -xf -); chown -R -- $qOwner $qRepo" | Out-Host
        }
        'nix' {
            Invoke-SetupCommand "test -f $qRepo/flake.nix; test -f $qRepo/flake.lock; test -d $qRepo/scripts; cp -a -- $qSource/nix/. $qRepo/nix/; chown -R -- $qOwner $qRepo/nix" | Out-Host
        }
    }
    $target = if ($syncMode -eq 'link') { $source } else { $repo }
    $qTarget = ConvertTo-WslArgument $target
    Invoke-SetupCommand "test -f $qTarget/flake.nix; test -f $qTarget/flake.lock" | Out-Host

    $deploymentFlake = if ($FlakeReference) { $FlakeReference } else { 'path:' + $target + '#wsl' }
    Invoke-SetupCommand "nixos-rebuild switch --flake $(ConvertTo-WslArgument $deploymentFlake) --impure --no-update-lock-file --option accept-flake-config true --option experimental-features 'nix-command flakes'" | Out-Host

    if ($target -ne $source) {
        switch ($syncBack) {
            'lock' { Invoke-SetupCommand "cp -- $qTarget/flake.lock $qSource/flake.lock" | Out-Host }
            'repo' { Invoke-SetupCommand "(cd $qTarget && tar --exclude=.git --exclude=.direnv --exclude=result -cf - .) | (cd $qSource && tar -xf -)" | Out-Host }
        }
    }
}
