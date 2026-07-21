<#!
.SYNOPSIS
    Streams the Hermes bootstrap 1Password payload to the container.
#>

if (-not ("HermesBootstrapBoundedDrain" -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public sealed class HermesBootstrapBoundedDrain : IDisposable
{
    private readonly object syncRoot = new object();
    private readonly StringBuilder buffer = new StringBuilder();
    private readonly int maximum;

    public HermesBootstrapBoundedDrain(int maximum) { this.maximum = maximum; }

    public async Task DrainAsync(StreamReader reader, CancellationToken cancellationToken)
    {
        var chars = new char[4096];
        try
        {
            int count;
            while ((count = await reader.ReadAsync(chars.AsMemory(0, chars.Length), cancellationToken).ConfigureAwait(false)) > 0)
            {
                lock (syncRoot)
                {
                    var remaining = maximum - buffer.Length;
                    if (remaining > 0) { buffer.Append(chars, 0, Math.Min(remaining, count)); }
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested) { }
        catch (ObjectDisposedException) when (cancellationToken.IsCancellationRequested) { }
    }

    public string Text { get { lock (syncRoot) { return buffer.ToString(); } } }

    public void Dispose()
    {
        lock (syncRoot) { buffer.Clear(); }
    }
}

public static class HermesBootstrapErrorHistory
{
    public static void Restore(ArrayList errors, object[] snapshot)
    {
        try
        {
            errors.Clear();
            if (snapshot == null) { return; }
            foreach (var errorRecord in snapshot) { errors.Add(errorRecord); }
        }
        catch { }
    }
}
'@
}

$script:HermesBootstrapProcessTimeoutMilliseconds = 30 * 60 * 1000
$script:HermesBootstrapTerminationTimeoutMilliseconds = 5000
$script:HermesBootstrapDrainTimeoutMilliseconds = 5000

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
    [System.Management.Automation.ErrorRecord[]]$errorHistoryBeforeProducer = @($global:Error)
    $process = $null
    $processStarted = $false
    $producerFailed = $false
    $secretValues = [System.Collections.Generic.List[string]]::new()
    $drain = [HermesBootstrapBoundedDrain]::new(65536)
    $drainCancellation = [System.Threading.CancellationTokenSource]::new()
    $stdoutDrain = $null
    $stderrDrain = $null
    $invokerOutput = $null
    $item = $null
    $record = $null

    try {
        try {
            $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = "docker"
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $utf8Encoding = [System.Text.UTF8Encoding]::new($false)
            $startInfo.StandardInputEncoding = $utf8Encoding
            $startInfo.StandardOutputEncoding = $utf8Encoding
            $startInfo.StandardErrorEncoding = $utf8Encoding
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
            $processStarted = $true
            $stdoutDrain = $drain.DrainAsync($process.StandardOutput, $drainCancellation.Token)
            $stderrDrain = $drain.DrainAsync($process.StandardError, $drainCancellation.Token)
            $process.StandardInput.NewLine = "`n"
            $process.StandardInput.WriteLine('{"type":"header","schema_version":1}')

            foreach ($planItem in @($plan.items)) {
                try {
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
                }
                finally {
                    if ($item -is [System.IDisposable]) { $item.Dispose() }
                    $record = $null
                    $item = $null
                    $invokerOutput = $null
                }
            }
            $process.StandardInput.WriteLine('{"type":"end"}')
        }
        catch {
            $producerFailed = $true
            Set-Variable -Name PSItem -Value $null -Scope Local
        }
        finally {
            if ($processStarted) {
                try { $process.StandardInput.Close() } catch { }
            }
        }

        if ($producerFailed) {
            $terminated = Stop-HermesBootstrapProcess `
                -Process $process `
                -TimeoutMilliseconds $script:HermesBootstrapTerminationTimeoutMilliseconds
            [void](Complete-HermesBootstrapProcessDrain `
                    -Process $process `
                    -StdoutDrain $stdoutDrain `
                    -StderrDrain $stderrDrain `
                    -Cancellation $drainCancellation `
                    -TimeoutMilliseconds $script:HermesBootstrapDrainTimeoutMilliseconds)
            $global:LASTEXITCODE = 1
            $message = if ($terminated) {
                "Hermes bootstrap secret retrieval failed."
            }
            else {
                "Hermes bootstrap process termination failed."
            }
            return [PSCustomObject]@{ Success = $false; Changed = $false; Message = $message }
        }

        $completed = Wait-HermesBootstrapProcess `
            -Process $process `
            -TimeoutMilliseconds $script:HermesBootstrapProcessTimeoutMilliseconds
        if (-not $completed) {
            [void](Stop-HermesBootstrapProcess `
                    -Process $process `
                    -TimeoutMilliseconds $script:HermesBootstrapTerminationTimeoutMilliseconds)
            [void](Complete-HermesBootstrapProcessDrain `
                    -Process $process `
                    -StdoutDrain $stdoutDrain `
                    -StderrDrain $stderrDrain `
                    -Cancellation $drainCancellation `
                    -TimeoutMilliseconds $script:HermesBootstrapDrainTimeoutMilliseconds)
            $global:LASTEXITCODE = 124
            return [PSCustomObject]@{
                Success = $false
                Changed = $false
                Message = "Hermes bootstrap timed out."
            }
        }

        $exitCode = $process.ExitCode
        $global:LASTEXITCODE = $exitCode
        $drainsCompleted = Complete-HermesBootstrapProcessDrain `
            -Process $process `
            -StdoutDrain $stdoutDrain `
            -StderrDrain $stderrDrain `
            -Cancellation $drainCancellation `
            -TimeoutMilliseconds $script:HermesBootstrapDrainTimeoutMilliseconds
        if (-not $drainsCompleted) {
            return [PSCustomObject]@{
                Success = $false
                Changed = $false
                Message = "Hermes bootstrap output drain timed out."
            }
        }
        if ($exitCode -eq 0) {
            return [PSCustomObject]@{
                Success = $true
                Changed = $true
                Message = "Hermes bootstrap completed."
            }
        }

        $diagnostics = ConvertTo-HermesBootstrapRedactedText -Text $drain.Text -Values $secretValues
        $message = "Hermes bootstrap failed (exit code $exitCode)."
        if (-not [string]::IsNullOrWhiteSpace($diagnostics)) {
            $message = "$message $diagnostics"
        }
        return [PSCustomObject]@{ Success = $false; Changed = $false; Message = $message }
    }
    finally {
        if ($item -is [System.IDisposable]) {
            try { $item.Dispose() } catch { }
        }
        if ($processStarted -and -not (Wait-HermesBootstrapProcess -Process $process -TimeoutMilliseconds 0)) {
            [void](Stop-HermesBootstrapProcess `
                    -Process $process `
                    -TimeoutMilliseconds $script:HermesBootstrapTerminationTimeoutMilliseconds)
        }
        if (($stdoutDrain -and -not $stdoutDrain.IsCompleted) -or
            ($stderrDrain -and -not $stderrDrain.IsCompleted)) {
            try { $drainCancellation.Cancel() } catch { }
        }
        if ($process) {
            try { $process.StandardInput.Dispose() } catch { }
            try { $process.StandardOutput.Dispose() } catch { }
            try { $process.StandardError.Dispose() } catch { }
        }
        if ($stdoutDrain -and $stdoutDrain.IsCompleted) {
            try { $stdoutDrain.Dispose() } catch { }
        }
        if ($stderrDrain -and $stderrDrain.IsCompleted) {
            try { $stderrDrain.Dispose() } catch { }
        }
        try { $drainCancellation.Dispose() } catch { }
        try { $drain.Dispose() } catch { }
        if ($process) {
            try { $process.Dispose() } catch { }
        }
        $record = $null
        $item = $null
        $invokerOutput = $null
        $value = $null
        $secretValues = $null
        Set-Variable -Name PSItem -Value $null -Scope Local
        [HermesBootstrapErrorHistory]::Restore($global:Error, $errorHistoryBeforeProducer)
        $errorHistoryBeforeProducer = $null
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
    param(
        [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)]
        [int]$TimeoutMilliseconds
    )

    if ($null -eq $Process) { return $true }
    if (Wait-HermesBootstrapProcess -Process $Process -TimeoutMilliseconds 0) { return $true }
    try {
        $Process.Kill($true)
    }
    catch {
        try { $Process.Kill() } catch { }
    }
    if (Wait-HermesBootstrapProcess -Process $Process -TimeoutMilliseconds $TimeoutMilliseconds) { return $true }

    try { $Process.Kill() } catch { }
    return Wait-HermesBootstrapProcess -Process $Process -TimeoutMilliseconds $TimeoutMilliseconds
}

function Wait-HermesBootstrapProcess {
    [CmdletBinding()]
    param(
        [System.Diagnostics.Process]$Process,
        [Parameter(Mandatory)]
        [int]$TimeoutMilliseconds
    )

    if ($null -eq $Process) { return $true }
    try {
        if ($Process.HasExited) { return $true }
        return $Process.WaitForExit($TimeoutMilliseconds)
    }
    catch {
        return $true
    }
}

function Complete-HermesBootstrapProcessDrain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Diagnostics.Process]$Process,
        [System.Threading.Tasks.Task]$StdoutDrain,
        [System.Threading.Tasks.Task]$StderrDrain,
        [Parameter(Mandatory)]
        [System.Threading.CancellationTokenSource]$Cancellation,
        [Parameter(Mandatory)]
        [int]$TimeoutMilliseconds
    )

    $completed = $true
    foreach ($task in @($StdoutDrain, $StderrDrain)) {
        if ($null -eq $task) { continue }
        try {
            if (-not $task.Wait($TimeoutMilliseconds)) { $completed = $false }
        }
        catch {
            $completed = $false
        }
    }
    if ($completed) { return $true }

    try { $Cancellation.Cancel() } catch { }
    if ($Process) {
        try { $Process.StandardOutput.Dispose() } catch { }
        try { $Process.StandardError.Dispose() } catch { }
    }
    foreach ($task in @($StdoutDrain, $StderrDrain)) {
        if ($null -eq $task -or $task.IsCompleted) { continue }
        try { [void]$task.Wait($TimeoutMilliseconds) } catch { }
    }
    return $false
}
