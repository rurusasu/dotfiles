[CmdletBinding()]
param([string]$Action)

$ErrorActionPreference = 'Stop'

function Invoke-OmarchyOpen {
    param([Parameter(Mandatory)][string]$Target, [string[]]$Arguments = @())
    if ($Arguments.Count -gt 0) { Start-Process -FilePath $Target -ArgumentList $Arguments | Out-Null }
    else { Start-Process -FilePath $Target | Out-Null }
}

function Open-OmarchyApplication {
    param([Parameter(Mandatory)][string]$Command, [string[]]$Candidates = @())
    $resolved = Get-Command $Command -ErrorAction SilentlyContinue
    if ($resolved) { Invoke-OmarchyOpen -Target $resolved.Source; return }
    foreach ($candidate in $Candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { Invoke-OmarchyOpen -Target $candidate; return }
    }
    throw "Application was not found: $Command. Run the Windows dotfiles installer."
}

function Initialize-OmarchyNativeType {
    if ('Dotfiles.OmarchyNativeKeys' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Dotfiles {
    public static class OmarchyNativeKeys {
        [StructLayout(LayoutKind.Sequential)] private struct KeyboardInput { public ushort key, scan; public uint flags, time; public UIntPtr extra; }
        [StructLayout(LayoutKind.Sequential)] private struct MouseInput { public int x, y; public uint data, flags, time; public UIntPtr extra; }
        [StructLayout(LayoutKind.Explicit)] private struct InputUnion { [FieldOffset(0)] public KeyboardInput keyboard; [FieldOffset(0)] public MouseInput mouse; }
        [StructLayout(LayoutKind.Sequential)] private struct Input { public uint type; public InputUnion value; }
        [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool LockWorkStation();
        public static bool ModifiersDown() {
            foreach (int key in new[] { 0x10, 0x11, 0x12, 0x5B, 0x5C })
                if ((GetAsyncKeyState(key) & 0x8000) != 0) return true;
            return false;
        }
        public static void Send(byte key) {
            Input[] inputs = new Input[key == 0 ? 2 : 4];
            byte[] keys = key == 0 ? new byte[] { 0x5B, 0x5B } : new byte[] { 0x5B, key, key, 0x5B };
            for (int i = 0; i < inputs.Length; i++) {
                inputs[i].type = 1;
                inputs[i].value.keyboard.key = keys[i];
                inputs[i].value.keyboard.flags = i >= inputs.Length / 2 ? 2u : 0u;
            }
            if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(Input))) != inputs.Length)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
    }
}
'@
}

function Send-OmarchyWindowsShortcut {
    param([Parameter(Mandatory)][ValidateSet('START', 'V', 'OEM_PERIOD')][string]$Key)
    # Send native shell shortcuts without registering additional hotkeys.
    Initialize-OmarchyNativeType
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    while ([Dotfiles.OmarchyNativeKeys]::ModifiersDown()) {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Release shortcut modifiers to open the Windows panel.' }
        Start-Sleep -Milliseconds 20
    }
    $virtualKey = switch ($Key) { 'START' { 0 }; 'V' { 0x56 }; 'OEM_PERIOD' { 0xBE } }
    [Dotfiles.OmarchyNativeKeys]::Send([byte]$virtualKey)
}

function Invoke-OmarchyLockWorkstation {
    Initialize-OmarchyNativeType
    if (-not [Dotfiles.OmarchyNativeKeys]::LockWorkStation()) {
        throw [System.ComponentModel.Win32Exception]::new([Runtime.InteropServices.Marshal]::GetLastWin32Error())
    }
}

function Invoke-OmarchyWindowsAction {
    param([Parameter(Mandatory)][string]$Action)
    switch ($Action) {
        'terminal' { Open-OmarchyApplication -Command 'wezterm-gui.exe' -Candidates @((Join-Path $env:ProgramFiles 'WezTerm/wezterm-gui.exe')) }
        'browser' { Invoke-OmarchyOpen -Target 'https://www.google.com/' }
        'files' { Invoke-OmarchyOpen -Target 'explorer.exe' }
        'notes' { Open-OmarchyApplication -Command 'Obsidian.exe' -Candidates @((Join-Path $env:LOCALAPPDATA 'Obsidian/Obsidian.exe'), (Join-Path $env:LOCALAPPDATA 'Programs/Obsidian/Obsidian.exe'), (Join-Path $env:ProgramFiles 'Obsidian/Obsidian.exe')) }
        'ai' { Invoke-OmarchyOpen -Target 'https://chatgpt.com/' }
        'passwords' { Open-OmarchyApplication -Command '1Password.exe' -Candidates @((Join-Path $env:LOCALAPPDATA '1Password/app/8/1Password.exe'), (Join-Path $env:ProgramFiles '1Password/1Password.exe')) }
        'launcher' { Send-OmarchyWindowsShortcut -Key 'START' }
        'help' { Invoke-OmarchyOpen -Target 'notepad.exe' -Arguments @(('"{0}"' -f (Join-Path $PSScriptRoot 'keybindings.txt'))) }
        'capture' { Invoke-OmarchyOpen -Target 'ms-screenclip:' }
        'calculator' { Invoke-OmarchyOpen -Target 'calc.exe' }
        'activity' { Invoke-OmarchyOpen -Target 'taskmgr.exe' }
        'lock' { Invoke-OmarchyLockWorkstation }
        'clipboard' { Send-OmarchyWindowsShortcut -Key 'V' }
        'emoji' { Send-OmarchyWindowsShortcut -Key 'OEM_PERIOD' }
        'audio' { Invoke-OmarchyOpen -Target 'ms-settings:sound' }
        'bluetooth' { Invoke-OmarchyOpen -Target 'ms-settings:bluetooth' }
        'display' { Invoke-OmarchyOpen -Target 'ms-settings:display' }
        'network' { Invoke-OmarchyOpen -Target 'ms-settings:network' }
        'power' { Invoke-OmarchyOpen -Target 'ms-settings:powersleep' }
        default { throw "Unknown Omarchy action: $Action" }
    }
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-OmarchyWindowsAction -Action $Action }
