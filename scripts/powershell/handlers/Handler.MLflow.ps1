<#
.SYNOPSIS
    Shared MLflow Gateway Docker service handler.

.DESCRIPTION
    Creates the shared local-ai-services network and reconciles the MLflow
    container to the compose definition.
#>

$libPath = Split-Path -Parent $PSScriptRoot
. (Join-Path $libPath 'lib\Invoke-ExternalCommand.ps1')

class MLflowHandler : SetupHandlerBase {
    [int]$DockerCheckTimeoutSeconds = 15
    [int]$DockerComposeTimeoutSeconds = 180

    MLflowHandler() {
        $this.Name = 'MLflow'
        $this.Description = 'Shared MLflow Gateway Docker service'
        $this.Order = 54
        $this.RequiresAdmin = $false
        $this.Phase = 2
        $this.DependsOn = @('Docker')
    }

    [bool] CanApply([SetupContext]$ctx) {
        if (-not (Get-Command -Name 'docker' -ErrorAction SilentlyContinue)) {
            $this.Log('docker command was not found.', 'Gray')
            return $false
        }
        if (-not (Test-DockerDaemon -TimeoutSeconds $this.DockerCheckTimeoutSeconds)) {
            $this.Log('Docker daemon is not ready; skipping MLflow.', 'Gray')
            return $false
        }
        return Test-Path -LiteralPath $this.GetComposeFilePath($ctx) -PathType Leaf
    }

    [SetupResult] Apply([SetupContext]$ctx) {
        $composeFile = $this.GetComposeFilePath($ctx)
        try {
            $network = $this.EnsureSharedNetwork()
            if (-not $network.Success) {
                return $this.CreateFailureResult("MLflow network setup failed: $($network.Message)")
            }

            $validation = $this.InvokeCompose($composeFile, @('config', '--quiet'))
            if (-not $validation.Success) {
                return $this.CreateFailureResult("MLflow Compose validation failed: $($validation.Message)")
            }

            $pull = $this.InvokeCompose($composeFile, @('pull', 'mlflow'))
            if (-not $pull.Success) {
                return $this.CreateFailureResult("MLflow image update failed: $($pull.Message)")
            }

            $start = $this.InvokeCompose($composeFile, @('up', '-d', '--force-recreate', '--remove-orphans', '--wait', 'mlflow'))
            if (-not $start.Success) {
                return $this.CreateFailureResult("MLflow startup failed: $($start.Message)")
            }

            return $this.CreateSuccessResult('MLflow Gateway started at http://127.0.0.1:5000')
        }
        catch {
            return $this.CreateFailureResult('MLflow setup failed.', $_.Exception)
        }
    }

    hidden [pscustomobject] EnsureSharedNetwork() {
        $null = @(Invoke-Docker -Arguments @('network', 'inspect', 'local-ai-services') -TimeoutSeconds $this.DockerComposeTimeoutSeconds)
        if ($LASTEXITCODE -eq 0) {
            return [PSCustomObject]@{ Success = $true; Message = '' }
        }

        $null = @(Invoke-Docker -Arguments @('network', 'create', 'local-ai-services') -TimeoutSeconds $this.DockerComposeTimeoutSeconds)
        if ($LASTEXITCODE -eq 0) {
            return [PSCustomObject]@{ Success = $true; Message = '' }
        }
        return [PSCustomObject]@{ Success = $false; Message = "exit code $LASTEXITCODE" }
    }

    hidden [pscustomobject] InvokeCompose([string]$composeFile, [string[]]$command) {
        $arguments = @('compose', '-f', $composeFile) + $command
        $output = @(Invoke-Docker -Arguments $arguments -TimeoutSeconds $this.DockerComposeTimeoutSeconds)
        $exitCode = $LASTEXITCODE
        if ($exitCode -eq 0) {
            return [PSCustomObject]@{ Success = $true; Message = '' }
        }

        $message = (($output -join "`n").Trim())
        if ([string]::IsNullOrWhiteSpace($message)) {
            $message = "exit code $exitCode"
        }
        elseif ($message.Length -gt 4096) {
            $message = "$($message.Substring(0, 4096))..."
        }
        return [PSCustomObject]@{ Success = $false; Message = $message }
    }

    hidden [string] GetComposeFilePath([SetupContext]$ctx) {
        return Join-Path $ctx.DotfilesPath 'docker\local-ai-services\compose.yml'
    }

}
