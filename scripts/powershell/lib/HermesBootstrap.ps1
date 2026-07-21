<#!
.SYNOPSIS
    Streams the Hermes bootstrap 1Password payload to the container.
#>

if (-not ("HermesBootstrapDrain" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;

public sealed class HermesBootstrapDrain
{
    private readonly object syncRoot = new object();
    private readonly StringBuilder buffer = new StringBuilder();
    private readonly int maximum;

    public HermesBootstrapDrain(int maximum) { this.maximum = maximum; }

    public async Task DrainAsync(StreamReader reader)
    {
        var chars = new char[4096];
        int count;
        while ((count = await reader.ReadAsync(chars, 0, chars.Length).ConfigureAwait(false)) > 0)
        {
            lock (syncRoot)
            {
                var remaining = maximum - buffer.Length;
                if (remaining > 0) { buffer.Append(chars, 0, Math.Min(remaining, count)); }
            }
        }
    }

    public string Text { get { lock (syncRoot) { return buffer.ToString(); } } }
}
'@
}

function Get-HermesBootstrapSecretPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFile
    )

    $arguments = @(
        "compose", "-f", $ComposeFile,
        "run", "--rm", "--no-deps", "-T", "hermes-bootstrap", "secret-plan"
    )
    $output = @(Invoke-Docker -Arguments $arguments)
    if ($LASTEXITCODE -ne 0) {
        throw [System.InvalidOperationException]::new("Hermes bootstrap secret plan retrieval failed.")
    }

    try {
        $plan = (($output -join "`n") | ConvertFrom-Json -Depth 32 -ErrorAction Stop)
        if (-not (Test-HermesBootstrapSecretPlan -Plan $plan)) {
            throw [System.InvalidOperationException]::new("Hermes bootstrap secret plan is invalid.")
        }
        return $plan
    }
    catch {
        throw [System.InvalidOperationException]::new("Hermes bootstrap secret plan is invalid.")
    }
}

function Test-HermesBootstrapSecretPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    if (-not (Test-HermesBootstrapPropertySet -Value $Plan -Names @("schema_version", "items"))) { return $false }
    if ($Plan.schema_version -isnot [long] -and $Plan.schema_version -isnot [int]) { return $false }
    if ($Plan.schema_version -ne 1) { return $false }

    $items = @($Plan.items)
    if ($items.Count -ne 6) { return $false }

    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($item in $items) {
        if (-not (Test-HermesBootstrapPropertySet -Value $item -Names @("key", "account", "vault", "item", "fields"))) {
            return $false
        }
        foreach ($name in @("key", "account", "vault", "item")) {
            if ($item.$name -isnot [string] -or
                [string]::IsNullOrWhiteSpace($item.$name) -or
                $item.$name.Trim() -cne $item.$name) { return $false }
        }
        if (-not $keys.Add($item.key)) { return $false }

        if ($item.fields -is [string] -or $item.fields -isnot [System.Collections.IEnumerable]) { return $false }
        $fields = @($item.fields)
        if ($fields.Count -eq 0) { return $false }
        $fieldNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($field in $fields) {
            if (-not (Test-HermesBootstrapPropertySet -Value $field -Names @("canonical_name", "labels"))) { return $false }
            if ($field.canonical_name -isnot [string] -or
                [string]::IsNullOrWhiteSpace($field.canonical_name) -or
                $field.canonical_name.Trim() -cne $field.canonical_name) { return $false }
            if (-not $fieldNames.Add($field.canonical_name)) { return $false }
            if ($field.labels -is [string] -or $field.labels -isnot [System.Collections.IEnumerable]) { return $false }
            $labels = @($field.labels)
            if ($labels.Count -eq 0) { return $false }
            foreach ($label in $labels) {
                if ($label -isnot [string] -or
                    [string]::IsNullOrWhiteSpace($label) -or
                    $label.Trim() -cne $label) { return $false }
            }
        }
    }

    return $true
}

function Test-HermesBootstrapPropertySet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Value,
        [Parameter(Mandatory)]
        [string[]]$Names
    )

    if ($null -eq $Value) { return $false }
    $actual = @($Value.PSObject.Properties.Name | Sort-Object)
    $expected = @($Names | Sort-Object)
    return $actual.Count -eq $expected.Count -and $null -eq (Compare-Object -ReferenceObject $expected -DifferenceObject $actual)
}

$script:DefaultOnePasswordInvoker = {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Arguments
    )

    $output = @(& op @Arguments 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw [System.InvalidOperationException]::new("Hermes bootstrap 1Password retrieval failed.")
    }
    return $output
}

function Invoke-HermesBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComposeFile,
        [Parameter(Mandatory)]
        [string]$DataDir,
        [scriptblock]$InvokeOnePasswordItem = $script:DefaultOnePasswordInvoker
    )

    $plan = Get-HermesBootstrapSecretPlan -ComposeFile $ComposeFile
    $process = $null
    $producerFailed = $false
    $secretValues = [System.Collections.Generic.List[string]]::new()
    $drain = [HermesBootstrapDrain]::new(65536)
    $stdoutDrain = $null
    $stderrDrain = $null

    try {
        $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = "docker"
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardInput = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
        $startInfo.Environment["HERMES_DATA_DIR"] = $DataDir
        foreach ($argument in @(
                "compose", "-f", $ComposeFile,
                "run", "--rm", "--no-deps", "-T", "hermes-bootstrap", "apply"
            )) {
            [void]$startInfo.ArgumentList.Add($argument)
        }

        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $startInfo
        if (-not $process.Start()) {
            throw [System.InvalidOperationException]::new("Hermes bootstrap process could not be started.")
        }
        $stdoutDrain = $drain.DrainAsync($process.StandardOutput)
        $stderrDrain = $drain.DrainAsync($process.StandardError)
        $process.StandardInput.NewLine = "`n"
        $process.StandardInput.WriteLine('{"type":"header","schema_version":1}')

        foreach ($planItem in @($plan.items)) {
            $onePasswordArguments = @(
                "item", "get", $planItem.item,
                "--account", $planItem.account,
                "--vault", $planItem.vault,
                "--format", "json"
            )
            $invokerOutput = @(& $InvokeOnePasswordItem @onePasswordArguments)
            $item = ConvertTo-HermesBootstrapItemObject -Output $invokerOutput
            foreach ($value in Get-HermesBootstrapItemFieldValues -Item $item) {
                $secretValues.Add($value)
            }

            $record = [ordered]@{ type = "item"; key = $planItem.key; item = $item }
            $process.StandardInput.WriteLine(($record | ConvertTo-Json -Compress -Depth 64))
            if ($item -is [System.IDisposable]) { $item.Dispose() }
            $item = $null
        }
        $process.StandardInput.WriteLine('{"type":"end"}')
    }
    catch {
        $producerFailed = $true
    }
    finally {
        if ($process -and $process.StartInfo.RedirectStandardInput) {
            try { $process.StandardInput.Close() } catch { }
        }
    }

    if ($producerFailed) {
        Stop-HermesBootstrapProcess -Process $process
        Complete-HermesBootstrapProcessDrain -Process $process -StdoutDrain $stdoutDrain -StderrDrain $stderrDrain
        $global:LASTEXITCODE = 1
        return [PSCustomObject]@{
            Success = $false
            Changed = $false
            Message = "Hermes bootstrap secret retrieval failed."
        }
    }

    Complete-HermesBootstrapProcessDrain -Process $process -StdoutDrain $stdoutDrain -StderrDrain $stderrDrain
    $global:LASTEXITCODE = $process.ExitCode
    if ($process.ExitCode -eq 0) {
        return [PSCustomObject]@{
            Success = $true
            Changed = $true
            Message = "Hermes bootstrap completed."
        }
    }

    $diagnostics = ConvertTo-HermesBootstrapRedactedText -Text $drain.Text -Values $secretValues
    $message = "Hermes bootstrap failed (exit code $($process.ExitCode))."
    if (-not [string]::IsNullOrWhiteSpace($diagnostics)) {
        $message = "$message $diagnostics"
    }
    return [PSCustomObject]@{
        Success = $false
        Changed = $false
        Message = $message
    }
}

function ConvertTo-HermesBootstrapItemObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Output
    )

    if ($Output.Count -eq 1 -and $Output[0] -isnot [string]) {
        return $Output[0]
    }
    $json = @($Output | ForEach-Object { [string]$_ }) -join "`n"
    try {
        return ($json | ConvertFrom-Json -Depth 64 -ErrorAction Stop)
    }
    catch {
        throw [System.InvalidOperationException]::new("Hermes bootstrap 1Password retrieval failed.")
    }
}

function Get-HermesBootstrapItemFieldValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Item
    )

    if ($null -eq $Item -or $null -eq $Item.fields) { return @() }
    return @($Item.fields |
            ForEach-Object {
                if ($null -ne $_ -and $_.value -is [string] -and $_.value.Length -gt 0) {
                    $_.value
                }
            })
}

function ConvertTo-HermesBootstrapRedactedText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]]$Values
    )

    $redacted = $Text
    foreach ($value in @($Values | Sort-Object Length -Descending -Unique)) {
        $redacted = $redacted.Replace($value, "[REDACTED]")
    }
    return $redacted.Trim()
}

function Stop-HermesBootstrapProcess {
    [CmdletBinding()]
    param([System.Diagnostics.Process]$Process)

    if ($null -eq $Process) { return }
    try {
        if ($Process.HasExited) { return }
    }
    catch {
        return
    }
    try {
        $Process.Kill($true)
    }
    catch {
        try { $Process.Kill() } catch { }
    }
}

function Complete-HermesBootstrapProcessDrain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process,
        [System.Threading.Tasks.Task]$StdoutDrain,
        [System.Threading.Tasks.Task]$StderrDrain
    )

    try {
        if (-not $Process.HasExited) { $Process.WaitForExit() }
    }
    catch {
        return
    }
    if ($StdoutDrain) { $StdoutDrain.GetAwaiter().GetResult() }
    if ($StderrDrain) { $StderrDrain.GetAwaiter().GetResult() }
}
