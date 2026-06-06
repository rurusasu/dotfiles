<#
.SYNOPSIS
    Repairs the minimum Windows environment expected by setup tools.
#>

function Repair-WindowsSetupEnvironment {
    [CmdletBinding()]
    param()

    $machineSystemRoot = [Environment]::GetEnvironmentVariable("SystemRoot", "Machine")
    if (-not $machineSystemRoot -or $machineSystemRoot -like "*%*") {
        $machineSystemRoot = "C:\WINDOWS"
    }

    if (-not $env:SystemRoot -or $env:SystemRoot -like "*%*") { $env:SystemRoot = $machineSystemRoot }
    if (-not $env:WINDIR -or $env:WINDIR -like "*%*") { $env:WINDIR = $machineSystemRoot }
    if (-not $env:ComSpec -or $env:ComSpec -like "*%*") { $env:ComSpec = Join-Path $machineSystemRoot "System32\cmd.exe" }

    if (-not $env:USERPROFILE) {
        $env:USERPROFILE = [Environment]::GetFolderPath("UserProfile")
    }
    if (-not $env:HOME) { $env:HOME = $env:USERPROFILE }
    if (-not $env:APPDATA) {
        $env:APPDATA = [Environment]::GetFolderPath("ApplicationData")
    }
    if (-not $env:LOCALAPPDATA) {
        $env:LOCALAPPDATA = [Environment]::GetFolderPath("LocalApplicationData")
    }
    if (-not $env:ProgramData) {
        $programData = [Environment]::GetFolderPath("CommonApplicationData")
        if (-not $programData) { $programData = "C:\ProgramData" }
        $env:ProgramData = $programData
    }
    if (-not $env:ProgramFiles) {
        $programFiles = [Environment]::GetFolderPath("ProgramFiles")
        if (-not $programFiles) { $programFiles = "C:\Program Files" }
        $env:ProgramFiles = $programFiles
    }
    if (-not ${env:ProgramFiles(x86)}) {
        $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")
        if (-not $programFilesX86) { $programFilesX86 = "C:\Program Files (x86)" }
        ${env:ProgramFiles(x86)} = $programFilesX86
    }
    if (-not $env:TEMP -or $env:TEMP -eq $env:USERPROFILE) {
        $env:TEMP = Join-Path $env:LOCALAPPDATA "Temp"
    }
    if (-not $env:TMP) { $env:TMP = $env:TEMP }
}
