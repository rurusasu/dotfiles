<#
.SYNOPSIS
    Routes the Windows Hermes option to the NixOS WSL rebuild.
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath 'lib\Invoke-ExternalCommand.ps1')

class HermesAgentHandler : SetupHandlerBase {
    HermesAgentHandler() {
        $this.Name = 'HermesAgent'
        $this.Description = 'Hermes Agent NixOS WSL setup validation'
        $this.Order = 56
        $this.RequiresAdmin = $false
        $this.Phase = 2
    }

    [bool] CanApply([SetupContext]$ctx) {
        if ($this.IsSkipped($ctx)) {
            $this.Log('Hermes Agent setup is disabled by option.', 'Gray')
            return $false
        }

        if ($this.IsNixRebuildApplied($ctx)) { return $true }

        if (-not (Get-Command -Name 'wsl' -ErrorAction SilentlyContinue)) {
            throw "WithHermes on Windows requires WSL and the '$($ctx.DistroName)' NixOS distribution. Enable the WSL/NixOS setup and do not skip NixRebuild."
        }

        $distros = @(Invoke-Wsl -TimeoutSeconds (Get-WslCheckTimeoutSecond) -Arguments @('--list', '--quiet'))
        $wslExitCode = $LASTEXITCODE
        if ($wslExitCode -ne 0) {
            throw "Unable to inspect WSL distributions (exit code: $wslExitCode); refusing to start a Docker Hermes Agent."
        }

        $nixDistroExists = @($distros | Where-Object {
            ($_ -replace "`0", '' -replace [char]0xFEFF, '').Trim() -eq $ctx.DistroName
            }).Count -gt 0
        if (-not $nixDistroExists) {
            throw "WithHermes on Windows requires the '$($ctx.DistroName)' NixOS WSL distribution. It is not registered; complete NixOS WSL setup and rerun the installer."
        }

        throw "The '$($ctx.DistroName)' WSL distribution is registered, but its Hermes Nix rebuild did not complete. Fix NixRebuild (and do not skip it) before rerunning; Docker fallback is disabled."
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        if ($this.IsNixRebuildApplied($ctx)) {
            try {
                $output = Invoke-Wsl -TimeoutSeconds 60 -Arguments @(
                    '-d', $ctx.DistroName, '-u', 'nixos', '--',
                    'bash', '-lc', 'systemctl --user is-active --quiet hermes-agent.service && command -v hermes >/dev/null && hermes --version'
                )
                $exitCode = $LASTEXITCODE
                if ($exitCode -ne 0) {
                    $details = if ($output) { ": $($output -join '; ')" } else { '' }
                    return $this.CreateFailureResult("Hermes Agent Nix service validation failed (exit code: $exitCode)$details")
                }

                return $this.CreateSuccessResult('Hermes Agent Nix service is active and its CLI is available.')
            }
            catch {
                return $this.CreateFailureResult("Hermes Agent Nix service validation failed: $($_.Exception.Message)", $_.Exception)
            }
        }

        return $this.CreateFailureResult('Hermes Agent on Windows requires a successful NixOS WSL rebuild; Docker fallback is disabled.')
    }

    hidden [bool] IsSkipped([SetupContext]$ctx) {
        if ($this.IsTruthy($ctx.GetOption('SkipHermesAgent', $false))) {
            return $true
        }

        return -not $this.IsTruthy($ctx.GetOption('WithHermes', $false))
    }

    hidden [bool] IsNixRebuildApplied([SetupContext]$ctx) {
        return $this.IsTruthy($ctx.GetOption('NixRebuildApplied', $false))
    }

    hidden [bool] IsTruthy([object]$value) {
        if ($null -eq $value) { return $false }
        if ($value -is [bool]) { return [bool]$value }

        return ([string]$value).Trim() -in @('1', 'true', 'TRUE', 'True', 'yes', 'YES', 'Yes', 'on', 'ON', 'On')
    }
}
