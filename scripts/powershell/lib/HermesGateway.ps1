function Invoke-HermesGatewayConvergence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFile
    )

    $null = @(Invoke-Docker -Arguments @(
            'compose', '-f', $ComposeFile,
            'exec', '-T', 'hermes', '/usr/local/bin/hermes-gateway-converge'
        ))
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw [System.InvalidOperationException]::new(
            "Hermes profile Gateway convergence failed with exit code $exitCode."
        )
    }
}
