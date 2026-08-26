<#
.SYNOPSIS
    Starts the host-level Hindsight service independently of Hermes.
#>

class HindsightHandler : SetupHandlerBase {
    HindsightHandler() {
        $this.Name = 'Hindsight'
        $this.Description = 'Shared Hindsight Docker memory service'
        $this.Order = 55
        $this.RequiresAdmin = $false
        $this.Phase = 2
    }

    [bool] CanApply([SetupContext]$ctx) {
        if (-not $this.IsTruthy($ctx.GetOption('WithHindsight', $false))) {
            $this.Log('Hindsight setup is disabled by option.', 'Gray')
            return $false
        }
        if (-not (Get-Command -Name 'docker' -ErrorAction SilentlyContinue)) {
            $this.Log('docker command was not found.', 'Gray')
            return $false
        }
        if (-not (Get-Command -Name 'ollama' -ErrorAction SilentlyContinue)) {
            $this.Log('ollama command was not found.', 'Gray')
            return $false
        }
        return Test-Path -LiteralPath $this.GetComposeFilePath($ctx) -PathType Leaf
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        $scriptPath = Join-Path $ctx.DotfilesPath 'scripts\powershell\hindsight.ps1'
        $composeFile = $this.GetComposeFilePath($ctx)
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
            return $this.CreateFailureResult("Hindsight launcher was not found: $scriptPath")
        }

        try {
            & $scriptPath -Action up -ComposeFile $composeFile
            return $this.CreateSuccessResult('Hindsight started at http://127.0.0.1:8888')
        }
        catch {
            return $this.CreateFailureResult('Hindsight setup failed.', $_.Exception)
        }
    }

    hidden [string] GetComposeFilePath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath 'docker\hindsight\compose.yml'
    }

    hidden [bool] IsTruthy([object]$value) {
        if ($null -eq $value) { return $false }
        if ($value -is [bool]) { return [bool]$value }
        return ([string]$value).Trim() -match '^(1|true|yes|on)$'
    }
}
