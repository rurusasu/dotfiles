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
    $stateVersion = [string]$Context.GetOption('StateVersion', '')
    if ($stateVersion -and $stateVersion -notmatch '^\d{2}\.\d{2}$') {
        throw 'StateVersion must use YY.MM format.'
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

    # Reuse the previously selected account; rootfs images initially provide UID 1000.
    $accountOutput = @(Invoke-SetupCommand 'user=$(cat /var/lib/dotfiles/user 2>/dev/null || true); if [ -n "$user" ]; then getent passwd "$user"; else getent passwd 1000; fi')
    $accountLine = $accountOutput | Where-Object { $_ -match '^[^:]+:[^:]*:[0-9]+:[0-9]+:' } | Select-Object -First 1
    if (-not $accountLine) { throw 'Could not resolve the NixOS-WSL user account.' }
    $account = ([string]$accountLine).Split(':')
    $user = $account[0]
    $userHome = $account[5]
    if ($userHome -notmatch '^/') { throw 'The NixOS user home must be an absolute path.' }
    $group = @(Invoke-SetupCommand "id -gn $(ConvertTo-WslArgument $user)") | Select-Object -Last 1
    $repo = "$userHome/.dotfiles"
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
    Invoke-SetupCommand "test -f $qTarget/flake.nix; test -f $qTarget/flake.lock" | Out-Host

    $settings = @{
        user = $user; home = $userHome; uid = $account[2]; gid = $account[3]
        group = [string]$group; repository = $target
    }
    if ($stateVersion) { $settings.stateVersion = $stateVersion }
    # Preserve any prior explicit stateVersion if this invocation omits it.
    $existing = @(Invoke-SetupCommand 'if [ -f /etc/nixos/dotfiles.json ]; then cat /etc/nixos/dotfiles.json; fi')
    if ($existing.Count -gt 0) {
        $prior = ($existing -join "`n") | ConvertFrom-Json -ErrorAction Stop
        $settings = @{}
        foreach ($property in $prior.PSObject.Properties) { $settings[$property.Name] = $property.Value }
        $settings.user = $user; $settings.home = $userHome
        $settings.uid = $account[2]; $settings.gid = $account[3]
        $settings.group = [string]$group; $settings.repository = $target
        if ($stateVersion) { $settings.stateVersion = $stateVersion }
    }
    $json = ConvertTo-WslArgument ($settings | ConvertTo-Json -Compress)
    Invoke-SetupCommand "install -d -m 0755 /etc/nixos; printf '%s\n' $json > /etc/nixos/dotfiles.json; chmod 0644 /etc/nixos/dotfiles.json" | Out-Host
    Invoke-SetupCommand "nix --accept-flake-config --extra-experimental-features 'nix-command flakes' flake update --flake $qTarget" | Out-Host
    Invoke-SetupCommand "nixos-rebuild switch --flake $(ConvertTo-WslArgument ('path:' + $target + '#nixos')) --impure --option accept-flake-config true --option experimental-features 'nix-command flakes'" | Out-Host

    if ($target -ne $source) {
        switch ($syncBack) {
            'lock' { Invoke-SetupCommand "cp -- $qTarget/flake.lock $qSource/flake.lock" | Out-Host }
            'repo' { Invoke-SetupCommand "(cd $qTarget && tar --exclude=.git --exclude=.direnv --exclude=result -cf - .) | (cd $qSource && tar -xf -)" | Out-Host }
        }
    }
}
