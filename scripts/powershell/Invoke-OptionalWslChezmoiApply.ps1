param(
    [Parameter(Mandatory)]
    [string] $Distro
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib/OptionalWslChezmoiApply.ps1')

$exitCode = Invoke-OptionalWslChezmoiApply -Distro $Distro
exit $exitCode
