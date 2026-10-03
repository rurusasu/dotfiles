function Assert-WezTermInstallEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Output,
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$VersionOutput,
        [Parameter(Mandatory)][int]$VersionExitCode
    )

    # Require the successful common install -> PATH -> verifier route in order.
    # A pre-existing executable or an installer returning success alone is insufficient.
    $packagePattern = [regex]::Escape($PackageId)
    $phasePattern = '(?s)PACKAGE_PHASE: package=' + $packagePattern +
    ' phase=install status=started[^\r\n]*\r?\n.*?' +
    'PACKAGE_PHASE: package=' + $packagePattern +
    ' phase=install status=completed elapsedMs=\d+ exitCode=0(?:\s|$).*?' +
    'PACKAGE_PHASE: package=' + $packagePattern +
    ' phase=path status=completed elapsedMs=\d+.*?' +
    'PACKAGE_PHASE: command=wezterm phase=verify status=completed elapsedMs=\d+ exitCode=0(?:\s|$)'
    if ($Output -notmatch $phasePattern) {
        throw "WezTerm install phase evidence is missing or unsuccessful for $PackageId"
    }
    if ($VersionExitCode -ne 0 -or $VersionOutput -notmatch '(?m)^wezterm \d') {
        throw "WezTerm fresh PATH command failed (exit=$VersionExitCode): $VersionOutput"
    }
}
