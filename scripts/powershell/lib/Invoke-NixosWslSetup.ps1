# Windows owns checkout synchronization; Nix owns the host configuration.
function Invoke-NixosWslSetup {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Context)

    $timeoutSeconds = [int]$Context.GetOption('PostInstallTimeoutSeconds', 1800)
    function ConvertTo-WslArgument([string]$Value) {
        return "'" + $Value.Replace("'", "'\''") + "'"
    }
    function Invoke-SetupCommand([string]$Command) {
        # Bypass WSL's default shell and keep profile banners out of machine-readable output.
        $output = @(Invoke-Wsl -TimeoutSeconds $timeoutSeconds -Arguments @(
                '-d', $Context.DistroName, '-u', 'root', '--exec', 'bash', '-c',
                ". /etc/profile >/dev/null || exit; set -euo pipefail; $Command"
            ))
        if ($LASTEXITCODE -ne 0) {
            throw "NixOS-WSL setup failed (exit=$LASTEXITCODE): $($output -join [Environment]::NewLine)"
        }
        return $output
    }

    $syncMode = [string]$Context.GetOption('SyncMode', 'link')
    $syncBack = [string]$Context.GetOption('SyncBack', 'lock')
    if ($syncMode -notin @('link', 'repo', 'nix', 'none') -or $syncBack -notin @('repo', 'lock', 'none')) {
        throw 'Invalid WSL checkout synchronization mode.'
    }
    if ($syncMode -eq 'nix' -and $syncBack -eq 'repo') {
        throw 'SyncMode nix requires SyncBack lock or none.'
    }

    $sourceOutput = @(Invoke-Wsl -Arguments @(
            '-d', $Context.DistroName, '-u', 'root', '--', 'wslpath', '-a',
            ([IO.Path]::GetFullPath($Context.DotfilesPath).Replace('\', '/'))
        ))
    $source = $sourceOutput | ForEach-Object { ([string]$_ -replace "`0", '' -replace [char]0xFEFF, '').Trim() } |
        Where-Object { $_ -match '^/' } | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or -not $source) {
        throw 'Could not resolve the Windows checkout inside WSL.'
    }

    $currentUserOutput = @(Invoke-Wsl -Arguments @('-d', $Context.DistroName, '--exec', 'id', '-un'))
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
    $userAttribute = ConvertTo-WslArgument ('path:' + $userFlake + '#nixosConfigurations.nixos.config.wsl.defaultUser')
    $userOutput = @(Invoke-SetupCommand "nix --accept-flake-config --extra-experimental-features 'nix-command flakes' eval --raw $userAttribute --impure --no-write-lock-file")
    $declaredUser = [string]($userOutput | Where-Object { [string]$_ -match '^[a-zA-Z_][a-zA-Z0-9_.-]*[$]?$' } | Select-Object -Last 1)
    if (-not $declaredUser) { throw 'Could not resolve the declared wsl.defaultUser.' }
    if ($currentUser -ne $declaredUser) {
        throw "WSL user '$currentUser' differs from declared wsl.defaultUser '$declaredUser'. Change it using nixos-rebuild boot and the official WSL restart procedure before running setup: https://nix-community.github.io/NixOS-WSL/how-to/change-username.html"
    }

    $group = @(Invoke-SetupCommand "id -gn $(ConvertTo-WslArgument $user)") | Select-Object -Last 1
    $qRepo = ConvertTo-WslArgument $repo
    $qSource = ConvertTo-WslArgument $source
    $qOwner = ConvertTo-WslArgument "${user}:$group"
    $force = [bool]$Context.GetOption('ForcePostInstall', $false)

    # Preserve conflicting checkouts even when ForcePostInstall is requested.
    $backup = if ($force) {
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
    $qFlakeTarget = ConvertTo-WslArgument ('path:' + $target)
    Invoke-SetupCommand "test -f $qTarget/flake.nix; test -f $qTarget/flake.lock" | Out-Host

    $updateFlakeInputs = [bool]$Context.GetOption('UpdateFlakeInputs', $true)
    if ($updateFlakeInputs) {
        Invoke-SetupCommand "nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake update --flake $qFlakeTarget" | Out-Host
    }
    $lockOption = if ($updateFlakeInputs) { '' } else { ' --no-update-lock-file' }
    Invoke-SetupCommand "nixos-rebuild switch --flake $(ConvertTo-WslArgument ('path:' + $target + '#nixos')) --impure$lockOption --option accept-flake-config true --option experimental-features 'nix-command flakes'" | Out-Host

    if ($target -ne $source) {
        switch ($syncBack) {
            'lock' { Invoke-SetupCommand "cp -- $qTarget/flake.lock $qSource/flake.lock" | Out-Host }
            'repo' { Invoke-SetupCommand "(cd $qTarget && tar --exclude=.git --exclude=.direnv --exclude=result -cf - .) | (cd $qSource && tar -xf -)" | Out-Host }
        }
    }
}
