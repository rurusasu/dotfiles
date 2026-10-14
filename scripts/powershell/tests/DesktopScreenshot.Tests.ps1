BeforeAll {
    $script:runtimePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Invoke-DesktopAction.ps1'
    . $script:runtimePath -Action '__test_load_only__'
    function New-ScreenshotTestImage {
        $image = [pscustomobject]@{ Disposals = 0 }
        $image | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposals++ }
        $image
    }
}

Describe 'Desktop screenshot clipboard race' {
    BeforeEach {
        $script:sequences = [Collections.Generic.Queue[uint32]]::new()
        $script:sequences.Enqueue(20)
        $script:sequences.Enqueue(20)
        $script:ownerName = 'SnippingTool'
        $script:image = New-ScreenshotTestImage
        $script:imageReads = 0
        Mock Get-DesktopClipboardSequence { $script:sequences.Dequeue() }
        Mock Get-DesktopClipboardOwnerProcessName { $script:ownerName }
        Mock Get-DesktopClipboardImage { $script:imageReads++; $script:image }
    }

    It 'should accept an image only when both sequence samples match and the owner is the capture tool' {
        $result = Read-DesktopScreenshotClipboard -PreviousSequence 10
        $result.Sequence | Should -Be 20
        [object]::ReferenceEquals($result.Image, $script:image) | Should -BeTrue
        $script:image.Disposals | Should -Be 0
    }

    It 'should dispose and reject an image if the clipboard changes while reading it' {
        $script:sequences.Clear()
        $script:sequences.Enqueue(20)
        $script:sequences.Enqueue(21)
        Read-DesktopScreenshotClipboard -PreviousSequence 10 | Should -BeNullOrEmpty
        $script:image.Disposals | Should -Be 1
    }

    It 'should reject an unrelated clipboard owner without reading its image' {
        $script:ownerName = 'unrelated-editor'
        Read-DesktopScreenshotClipboard -PreviousSequence 10 | Should -BeNullOrEmpty
        $script:imageReads | Should -Be 0
        $script:image.Disposals | Should -Be 0
    }

    It 'should reject an unchanged sequence without reading an image' {
        Read-DesktopScreenshotClipboard -PreviousSequence 20 | Should -BeNullOrEmpty
        $script:imageReads | Should -Be 0
    }

    It 'should reject a null image even when its capture owner and sequence are valid' {
        $script:image = $null
        Read-DesktopScreenshotClipboard -PreviousSequence 10 | Should -BeNullOrEmpty
    }

    It 'should retry a busy clipboard without accepting or leaking an image' {
        Mock Get-DesktopClipboardImage { throw [Runtime.InteropServices.ExternalException]::new('clipboard busy', -2147221040) }
        Read-DesktopScreenshotClipboard -PreviousSequence 10 | Should -BeNullOrEmpty
        $script:image.Disposals | Should -Be 0
    }

    It 'should dispose an allocated image if the final clipboard sequence query fails' {
        $script:sequenceReads = 0
        Mock Get-DesktopClipboardSequence {
            $script:sequenceReads++
            if ($script:sequenceReads -gt 1) { throw [Runtime.InteropServices.ExternalException]::new('clipboard busy after image read', -2147221040) }
            20
        }
        Read-DesktopScreenshotClipboard -PreviousSequence 10 | Should -BeNullOrEmpty
        $script:image.Disposals | Should -Be 1
    }
}

Describe 'Desktop screenshot cancellation and cleanup' {
    BeforeEach {
        $script:observer = [pscustomobject]@{ Checks = 0; CancelAt = 0; Disposals = 0 }
        $script:observer | Add-Member -MemberType ScriptProperty -Name IsCancelled -Value { $this.Checks++; $this.CancelAt -gt 0 -and $this.Checks -ge $this.CancelAt }
        $script:observer | Add-Member -MemberType ScriptMethod -Name Dispose -Value { $this.Disposals++ }
        $script:image = New-ScreenshotTestImage
        $script:reads = 0
        $script:writes = 0
        $script:writtenImage = $null
        $script:paintPath = Join-Path $TestDrive 'Paint App/mspaint.exe'
        $script:launches = [Collections.Generic.List[object]]::new()
        Mock Initialize-DesktopNative { }
        Mock Get-DesktopClipboardSequence { 10 }
        Mock New-DesktopScreenshotCancellation { $script:observer }
        Mock Send-DesktopChord { }
        Mock Start-Sleep { }
        Mock Read-DesktopScreenshotClipboard { $script:reads++; [pscustomobject]@{ Sequence = 20; Image = $script:image } }
        Mock Write-DesktopScreenshotImage { param([object]$Image) $script:writes++; $script:writtenImage = $Image; Join-Path $TestDrive 'capture.png' }
        Mock Get-DesktopExecutable { $script:paintPath }
        Mock Invoke-DesktopProcess { param([string]$FilePath, [string[]]$Arguments) $script:launches.Add([pscustomobject]@{ FilePath = $FilePath; Arguments = $Arguments }) }
    }

    It 'should save one stable image open the editor and dispose both image and observer' {
        Invoke-DesktopScreenshot
        $script:reads | Should -Be 1
        $script:writes | Should -Be 1
        [object]::ReferenceEquals($script:writtenImage, $script:image) | Should -BeTrue
        $script:launches.Count | Should -Be 1
        $script:launches[0].FilePath | Should -Be $script:paintPath
        $script:launches[0].Arguments[0] | Should -Be (Join-Path $TestDrive 'capture.png')
        $script:image.Disposals | Should -Be 1
        $script:observer.Disposals | Should -Be 1
    }

    It 'should stop after Escape before or after the clipboard read without saving or opening an editor' -ForEach @(
        @{ CancelAt = 1; ExpectedReads = 0; ExpectedImageDisposals = 0 },
        @{ CancelAt = 2; ExpectedReads = 1; ExpectedImageDisposals = 1 }
    ) {
        $script:observer.CancelAt = $CancelAt
        Invoke-DesktopScreenshot
        $script:reads | Should -Be $ExpectedReads
        $script:writes | Should -Be 0
        $script:launches.Count | Should -Be 0
        $script:image.Disposals | Should -Be $ExpectedImageDisposals
        $script:observer.Disposals | Should -Be 1
    }

    It 'should dispose accepted image and cancellation observer when saving fails' {
        Mock Write-DesktopScreenshotImage { throw 'isolated image write failure' }
        { Invoke-DesktopScreenshot } | Should -Throw '*image write failure*'
        $script:image.Disposals | Should -Be 1
        $script:observer.Disposals | Should -Be 1
        $script:launches.Count | Should -Be 0
    }

    It 'should dispose the cancellation observer if opening capture fails' {
        Mock Send-DesktopChord { throw 'isolated capture chord failure' }
        { Invoke-DesktopScreenshot } | Should -Throw '*capture chord failure*'
        $script:observer.Disposals | Should -Be 1
        $script:reads | Should -Be 0
    }

    It 'should release the cancellation observer after capture times out without an image' {
        Mock Read-DesktopScreenshotClipboard { $null }
        Invoke-DesktopScreenshot -TimeoutSeconds 0
        $script:observer.Disposals | Should -Be 1
        $script:writes | Should -Be 0
        $script:launches.Count | Should -Be 0
        $script:image.Disposals | Should -Be 0
    }

    It 'should cancel before native input and during modifier release on Windows PowerShell 5.1' {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
            Set-ItResult -Skipped -Because 'Windows PowerShell 5.1 requires Windows'
            return
        }
        $probe = @'
param([string]$RuntimePath)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @"
using System;
namespace DotfilesDesktop {
    public static class Native {
        public static bool Held;
        public static int KeyPolls, ChordCalls;
        public static short GetAsyncKeyState(int key) { KeyPolls++; return Held && key == 16 ? (short)-1 : (short)0; }
        public static IntPtr GetForegroundWindow() { return new IntPtr(42); }
        public static void Chord(ushort[] keys) { ChordCalls++; }
    }
}
"@
. $RuntimePath -Action '__test_load_only__'
function Start-Sleep { param([int]$Milliseconds) }
Send-DesktopChord @(91, 16, 83) -Cancellation ([pscustomobject]@{ IsCancelled = $true })
if ([DotfilesDesktop.Native]::ChordCalls -ne 0) { throw 'Already cancelled screenshot still sent native input' }
[DotfilesDesktop.Native]::Held = $true
[DotfilesDesktop.Native]::KeyPolls = 0
$token = [pscustomobject]@{}
$token | Add-Member -MemberType ScriptProperty -Name IsCancelled -Value { [DotfilesDesktop.Native]::KeyPolls -gt 0 }
Send-DesktopChord @(91, 16, 83) -Cancellation $token
if ([DotfilesDesktop.Native]::KeyPolls -eq 0) { throw 'The modifier-wait cancellation case was not exercised' }
if ([DotfilesDesktop.Native]::ChordCalls -ne 0) { throw 'Cancellation during modifier release still sent native input' }
[DotfilesDesktop.Native]::Held = $false
Send-DesktopChord @(17, 67)
if ([DotfilesDesktop.Native]::ChordCalls -ne 1) { throw 'Default uncancelled chord was affected by screenshot cancellation' }
Write-Output 'SCREENSHOT_CANCELLATION_INPUT_GUARD_OK'
'@
        $probePath = Join-Path $TestDrive 'screenshot-input-probe.ps1'
        [IO.File]::WriteAllText($probePath, $probe, [Text.UTF8Encoding]::new($false))
        $exe = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $output = & $exe -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -File $probePath -RuntimePath $script:runtimePath 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        $output -join [Environment]::NewLine | Should -Match 'SCREENSHOT_CANCELLATION_INPUT_GUARD_OK'
    }
}

Describe 'Desktop screenshot editor resolution' {
    BeforeEach {
        $script:paintPath = $null
        $script:resolution = $null
        $script:launches = [Collections.Generic.List[object]]::new()
        Mock Get-DesktopExecutable {
            param([string]$Name, [string[]]$Candidates)
            $script:resolution = [pscustomobject]@{ Name = $Name; Candidates = $Candidates }
            $script:paintPath
        }
        Mock Invoke-DesktopProcess {
            param([string]$FilePath, [string[]]$Arguments)
            $script:launches.Add([pscustomobject]@{ FilePath = $FilePath; Arguments = $Arguments })
        }
    }

    It 'should open a saved screenshot with the resolved <Kind> Paint executable' -ForEach @(
        @{ Kind = 'app alias'; ResolvedPath = 'C:\Users\Test User\AppData\Local\Microsoft\WindowsApps\mspaint.exe' },
        @{ Kind = 'legacy'; ResolvedPath = 'C:\Windows\System32\mspaint.exe' }
    ) {
        $script:paintPath = $ResolvedPath
        $imagePath = Join-Path $TestDrive ('image with spaces ' + [char]0x753b + '.png')
        Open-DesktopScreenshotEditor -Path $imagePath
        $script:resolution.Name | Should -Be 'mspaint.exe'
        ($script:resolution.Candidates -join '|') | Should -Be '%LOCALAPPDATA%\Microsoft\WindowsApps\mspaint.exe|%WINDIR%\System32\mspaint.exe'
        $script:launches.Count | Should -Be 1
        $script:launches[0].FilePath | Should -Be $ResolvedPath
        $script:launches[0].Arguments.Count | Should -Be 1
        $script:launches[0].Arguments[0] | Should -Be $imagePath
    }

    It 'should report unavailable Paint without starting a process or installing a package' {
        { Open-DesktopScreenshotEditor -Path (Join-Path $TestDrive 'capture.png') } | Should -Throw '*Paint*unavailable*winget install*9PCFS5B6T72H*--source msstore*'
        $script:launches.Count | Should -Be 0
    }

    It 'should propagate a resolved Paint launch failure' {
        $script:paintPath = 'C:\Users\Test User\AppData\Local\Microsoft\WindowsApps\mspaint.exe'
        Mock Invoke-DesktopProcess { throw 'isolated Paint launch failure' }
        { Open-DesktopScreenshotEditor -Path (Join-Path $TestDrive 'capture.png') } | Should -Throw '*isolated Paint launch failure*'
    }
}
