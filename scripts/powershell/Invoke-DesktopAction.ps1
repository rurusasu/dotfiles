#Requires -Version 5.1
<#
.SYNOPSIS
    Execute an action from the exported Nix desktop key allocation.
.DESCRIPTION
    Invoked by PowerToys with Windows PowerShell -STA. No hotkeys are defined
    here: nix/home/keybindings owns the key allocation. Shell UI automation
    supports the English and Japanese Windows 11 accessibility labels and
    fails explicitly if a Windows update removes the required control.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Action
)

$ErrorActionPreference = 'Stop'
$script:DesktopActionScriptPath = $PSCommandPath

function Initialize-DesktopNative {
    if ('DotfilesDesktop.Native' -as [type]) { return }
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $compilerParameters = @{}
    if ($PSEdition -eq 'Desktop') {
        # CodeDom otherwise resolves bare System.dll against the inherited
        # working directory. PowerToys ships a .NET Core facade with that name.
        $compilerParameters.ReferencedAssemblies = @([System.ComponentModel.Win32Exception].Assembly.Location)
    }
    Add-Type @compilerParameters -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
namespace DotfilesDesktop {
    // The Windows SDK UIAutomationClient.h IUnknown vtable prefixes. CUIAutomation8
    // supplies the modern UIA client; the .NET Framework UIA2 HWND proxy cannot
    // traverse all current Windows shell XAML providers.
    [ComImport, Guid("30cbe57d-d9d0-452a-ab13-7ac5ac4825ee"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IUiAutomation {
        [return: MarshalAs(UnmanagedType.Bool)] bool CompareElements(IUiElement first, IUiElement second);
        void UnusedCompareRuntimeIds();
        IUiElement GetRootElement();
        IUiElement ElementFromHandle(IntPtr window);
        void UnusedElementFromPoint(); void UnusedGetFocusedElement();
        void UnusedGetRootElementBuildCache(); void UnusedElementFromHandleBuildCache();
        void UnusedElementFromPointBuildCache(); void UnusedGetFocusedElementBuildCache();
        void UnusedCreateTreeWalker(); void UnusedControlViewWalker();
        void UnusedContentViewWalker(); void UnusedRawViewWalker();
        void UnusedRawViewCondition(); void UnusedControlViewCondition();
        void UnusedContentViewCondition(); void UnusedCreateCacheRequest();
        IUiCondition CreateTrueCondition();
    }
    [ComImport, Guid("352ffba8-0973-437c-a61f-f64cafd81df9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IUiCondition { }
    [ComImport, Guid("d22108aa-8ac5-49a5-837b-37bbb3d7591e"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IUiElement {
        void SetFocus(); void UnusedGetRuntimeId(); void UnusedFindFirst();
        IUiElementArray FindAll(int scope, IUiCondition condition);
        void UnusedFindFirstBuildCache(); void UnusedFindAllBuildCache(); void UnusedBuildUpdatedCache();
        [return: MarshalAs(UnmanagedType.Struct)] object GetCurrentPropertyValue(int propertyId);
        void UnusedGetCurrentPropertyValueEx(); void UnusedGetCachedPropertyValue();
        void UnusedGetCachedPropertyValueEx(); void UnusedGetCurrentPatternAs(); void UnusedGetCachedPatternAs();
        [return: MarshalAs(UnmanagedType.IUnknown)] object GetCurrentPattern(int patternId);
    }
    [ComImport, Guid("14314595-b4bc-4055-95f2-58f2e42c9855"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IUiElementArray { int GetLength(); IUiElement GetElement(int index); }
    [ComImport, Guid("fb377fbe-8ea6-46d5-9c73-6499642d3059"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IUiInvoke { void Invoke(); }
    [ComImport, Guid("94cf8058-9b8d-4ab9-8bfd-4cd0a33c8c70"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IUiToggle { void Toggle(); int GetToggleState(); }
    [ComImport, Guid("88f4d42a-e881-459d-a77c-73bbbb7e02dc"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IUiScroll {
        void Scroll(int horizontalAmount, int verticalAmount);
        void SetScrollPercent(double horizontalPercent, double verticalPercent);
        double GetHorizontalScrollPercent(); double GetVerticalScrollPercent();
        double GetHorizontalViewSize(); double GetVerticalViewSize();
        [return: MarshalAs(UnmanagedType.Bool)] bool GetHorizontallyScrollable();
        [return: MarshalAs(UnmanagedType.Bool)] bool GetVerticallyScrollable();
    }
    [ComImport, Guid("a8efa66a-0fda-421a-9194-38021f3578ea"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IUiSelectionItem {
        void Select(); void UnusedAddToSelection(); void UnusedRemoveFromSelection();
        [return: MarshalAs(UnmanagedType.Bool)] bool GetIsSelected();
        IUiElement GetSelectionContainer();
    }
    public sealed class UiClient {
        [ThreadStatic] private static UiClient current;
        internal readonly IUiAutomation Automation;
        internal readonly IUiCondition TrueCondition;
        private UiClient() {
            Automation = (IUiAutomation)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("e22ad333-b25f-460c-83d0-0581107395c9")));
            TrueCondition = Automation.CreateTrueCondition();
        }
        public static UiElement FromHandle(IntPtr window) {
            if (current == null) current = new UiClient();
            IUiElement element = current.Automation.ElementFromHandle(window);
            return element == null ? null : new UiElement(current, element);
        }
        public static bool Same(UiElement first, UiElement second) {
            return first != null && second != null && first.Client.Automation.CompareElements(first.Element, second.Element);
        }
    }
    public sealed class UiElement {
        internal readonly UiClient Client;
        internal readonly IUiElement Element;
        internal UiElement(UiClient client, IUiElement element) { Client = client; Element = element; }
        public UiElement Current { get { return this; } }
        public string Name { get { return Convert.ToString(Element.GetCurrentPropertyValue(30005)); } }
        public string AutomationId { get { return Convert.ToString(Element.GetCurrentPropertyValue(30011)); } }
        public string ClassName { get { return Convert.ToString(Element.GetCurrentPropertyValue(30012)); } }
        public int ProcessId { get { return Convert.ToInt32(Element.GetCurrentPropertyValue(30002)); } }
        public bool IsEnabled { get { return Convert.ToBoolean(Element.GetCurrentPropertyValue(30010)); } }
        public bool HasKeyboardFocus { get { return Convert.ToBoolean(Element.GetCurrentPropertyValue(30008)); } }
        public void SetFocus() { Element.SetFocus(); }
        public UiElement[] FindAll(object scope, object ignoredCondition) {
            IUiElementArray found = Element.FindAll(Convert.ToInt32(scope), Client.TrueCondition);
            try {
                int length = found.GetLength();
                UiElement[] result = new UiElement[length];
                for (int i = 0; i < length; i++) result[i] = new UiElement(Client, found.GetElement(i));
                return result;
            }
            finally { Marshal.ReleaseComObject(found); }
        }
        public bool TryGetCurrentPattern(object pattern, out object result) {
            result = null;
            int id = pattern is int ? (int)pattern : Convert.ToInt32(pattern.GetType().GetProperty("Id").GetValue(pattern, null));
            object native;
            try { native = Element.GetCurrentPattern(id); }
            catch (COMException error) {
                if (error.ErrorCode == unchecked((int)0x80040204) || error.ErrorCode == unchecked((int)0x80004002)) return false;
                throw;
            }
            if (native == null) return false;
            switch (id) {
                case 10000: result = new UiInvoke((IUiInvoke)native); break;
                case 10004: result = new UiScroll((IUiScroll)native); break;
                case 10010: result = new UiSelectionItem(Client, (IUiSelectionItem)native); break;
                case 10015: result = new UiToggle((IUiToggle)native); break;
                default: Marshal.ReleaseComObject(native); return false;
            }
            return true;
        }
    }
    public sealed class UiInvoke {
        private readonly IUiInvoke value;
        internal UiInvoke(IUiInvoke pattern) { value = pattern; }
        public void Invoke() { value.Invoke(); }
    }
    public sealed class UiToggle {
        private readonly IUiToggle value;
        internal UiToggle(IUiToggle pattern) { value = pattern; }
        public UiToggle Current { get { return this; } }
        public int ToggleState { get { return value.GetToggleState(); } }
        public void Toggle() { value.Toggle(); }
    }
    public sealed class UiScroll {
        private readonly IUiScroll value;
        internal UiScroll(IUiScroll pattern) { value = pattern; }
        public UiScroll Current { get { return this; } }
        public bool VerticallyScrollable { get { return value.GetVerticallyScrollable(); } }
        public double VerticalScrollPercent { get { return value.GetVerticalScrollPercent(); } }
        public void Scroll(object horizontal, object vertical) { value.Scroll(Convert.ToInt32(horizontal), Convert.ToInt32(vertical)); }
        public void SetScrollPercent(double horizontal, double vertical) { value.SetScrollPercent(horizontal, vertical); }
    }
    public sealed class UiSelectionItem {
        private readonly UiClient client;
        private readonly IUiSelectionItem value;
        internal UiSelectionItem(UiClient owner, IUiSelectionItem pattern) { client = owner; value = pattern; }
        public UiSelectionItem Current { get { return this; } }
        public bool IsSelected { get { return value.GetIsSelected(); } }
        public UiElement SelectionContainer { get { IUiElement item = value.GetSelectionContainer(); return item == null ? null : new UiElement(client, item); } }
        public void Select() { value.Select(); }
    }
    // Observe only Escape while a capture is pending. A dedicated message
    // pump avoids GetAsyncKeyState's shared, consumable "pressed since" bit
    // and keeps the hook responsive while the STA reads the OLE clipboard.
    // https://learn.microsoft.com/windows/win32/winmsg/lowlevelkeyboardproc
    public sealed class EscapeCancellation : IDisposable {
        private delegate IntPtr HookProcedure(int code, IntPtr message, IntPtr data);
        [StructLayout(LayoutKind.Sequential)] private struct MSG {
            public IntPtr window; public uint message; public UIntPtr wParam;
            public IntPtr lParam; public uint time; public int x, y; public uint reserved;
        }
        [DllImport("user32.dll", SetLastError=true)] private static extern IntPtr SetWindowsHookEx(int id, HookProcedure callback, IntPtr module, uint thread);
        [DllImport("user32.dll")] private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
        [DllImport("user32.dll")] private static extern bool PeekMessage(out MSG message, IntPtr window, uint minimum, uint maximum, uint remove);
        [DllImport("user32.dll")] private static extern bool TranslateMessage(ref MSG message);
        [DllImport("user32.dll")] private static extern IntPtr DispatchMessage(ref MSG message);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string module);
        private readonly System.Threading.ManualResetEvent ready = new System.Threading.ManualResetEvent(false);
        private readonly System.Threading.ManualResetEvent stop = new System.Threading.ManualResetEvent(false);
        private readonly System.Threading.Thread worker;
        private HookProcedure callback;
        private IntPtr hook;
        private Exception startupError;
        private volatile bool cancelled;
        private int disposed;
        public EscapeCancellation() {
            worker = new System.Threading.Thread(Run);
            worker.IsBackground = true;
            worker.Start();
            ready.WaitOne();
            if (startupError != null) {
                Dispose();
                throw new InvalidOperationException("Cannot observe Escape while taking a screenshot.", startupError);
            }
        }
        public bool IsCancelled { get { return cancelled; } }
        private IntPtr Observe(int code, IntPtr message, IntPtr data) {
            try {
                long kind = message.ToInt64();
                if (code >= 0 && (kind == 0x100 || kind == 0x104) && data != IntPtr.Zero && Marshal.ReadInt32(data) == 27)
                    cancelled = true;
            }
            catch { /* Observation must never prevent forwarding keyboard input. */ }
            return CallNextHookEx(hook, code, message, data);
        }
        private void Run() {
            bool initialized = false;
            try {
                callback = Observe;
                hook = SetWindowsHookEx(13, callback, GetModuleHandle(null), 0);
                if (hook == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                initialized = true;
                ready.Set();
                while (!stop.WaitOne(10)) {
                    MSG message;
                    while (PeekMessage(out message, IntPtr.Zero, 0, 0, 1)) {
                        TranslateMessage(ref message);
                        DispatchMessage(ref message);
                    }
                }
            }
            catch (Exception error) {
                if (!initialized) startupError = error;
                cancelled = true;
            }
            finally {
                if (hook != IntPtr.Zero) { UnhookWindowsHookEx(hook); hook = IntPtr.Zero; }
                GC.KeepAlive(callback);
                ready.Set();
            }
        }
        public void Dispose() {
            if (System.Threading.Interlocked.Exchange(ref disposed, 1) != 0) return;
            stop.Set();
            worker.Join();
            ready.Dispose();
            stop.Dispose();
        }
    }
    public static class Native {
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] public struct APPBARDATA {
            public uint cbSize; public IntPtr hWnd; public uint uCallbackMessage;
            public uint uEdge; public RECT rc; public IntPtr lParam;
        }
        [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {
            public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo;
        }
        [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT {
            public ushort wVk, wScan; public uint dwFlags, time; public IntPtr dwExtraInfo;
        }
        [StructLayout(LayoutKind.Explicit)] public struct INPUTUNION {
            [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki;
        }
        [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public INPUTUNION data; }
        [StructLayout(LayoutKind.Sequential)] private struct PROPERTYKEY { public Guid format; public uint id; }
        [StructLayout(LayoutKind.Sequential)] private struct PROPVARIANT {
            public ushort type, reserved1, reserved2, reserved3;
            public IntPtr pointer, secondPointer;
        }
        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore {
            [PreserveSig] int GetCount(out uint count);
            [PreserveSig] int GetAt(uint index, out PROPERTYKEY key);
            [PreserveSig] int GetValue(ref PROPERTYKEY key, out PROPVARIANT value);
            [PreserveSig] int SetValue(ref PROPERTYKEY key, ref PROPVARIANT value);
            [PreserveSig] int Commit();
        }
        [DllImport("shell32.dll")] private static extern int SHGetPropertyStoreForWindow(IntPtr window, ref Guid iid, [MarshalAs(UnmanagedType.Interface)] out IPropertyStore store);
        [DllImport("ole32.dll")] private static extern int PropVariantClear(ref PROPVARIANT value);
        [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint count, INPUT[] inputs, int size);
        [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
        [DllImport("user32.dll")] public static extern IntPtr GetClipboardOwner();
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string className, string title);
        [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder className, int maximum);
        [DllImport("user32.dll", EntryPoint="GetPropW", CharSet=CharSet.Unicode)] public static extern IntPtr GetWindowProperty(IntPtr window, string name);
        [DllImport("shell32.dll")] public static extern UIntPtr SHAppBarMessage(uint message, ref APPBARDATA data);
        [DllImport("kernel32.dll", SetLastError=true)] public static extern uint SetThreadExecutionState(uint state);
        [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool SystemParametersInfo(uint action, uint parameter, string value, uint flags);
        [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
        [DllImport("user32.dll", EntryPoint="GetWindowLongW", SetLastError=true)] public static extern int GetWindowLong(IntPtr window, int index);
        [DllImport("user32.dll", EntryPoint="SetWindowLongW", SetLastError=true)] public static extern int SetWindowLong(IntPtr window, int index, int value);
        [DllImport("user32.dll", SetLastError=true)] public static extern bool GetLayeredWindowAttributes(IntPtr window, out uint color, out byte alpha, out uint flags);
        [DllImport("user32.dll", SetLastError=true)] public static extern bool SetLayeredWindowAttributes(IntPtr window, uint color, byte alpha, uint flags);
        public static string GetWindowAppId(IntPtr window) { return GetWindowAppProperty(window, 5); }
        public static string GetWindowAppProperty(IntPtr window, uint propertyId) {
            Guid iid = new Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99");
            IPropertyStore store;
            if (SHGetPropertyStoreForWindow(window, ref iid, out store) < 0 || store == null) return String.Empty;
            try {
                PROPERTYKEY key = new PROPERTYKEY { format = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), id = propertyId };
                PROPVARIANT value;
                int result = store.GetValue(ref key, out value);
                try {
                    if (result < 0 || value.pointer == IntPtr.Zero) return String.Empty;
                    if (value.type == 31) return Marshal.PtrToStringUni(value.pointer) ?? String.Empty;
                    if (value.type == 8) return Marshal.PtrToStringBSTR(value.pointer) ?? String.Empty;
                    return String.Empty;
                }
                finally { PropVariantClear(ref value); }
            }
            finally { Marshal.ReleaseComObject(store); }
        }
        public static void Chord(ushort[] keys) {
            INPUT[] inputs = new INPUT[keys.Length * 2];
            for (int i = 0; i < keys.Length; i++) {
                inputs[i].type = 1; inputs[i].data.ki.wVk = keys[i];
                inputs[keys.Length + i].type = 1;
                inputs[keys.Length + i].data.ki.wVk = keys[keys.Length - i - 1];
                inputs[keys.Length + i].data.ki.dwFlags = 2;
            }
            if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT))) != inputs.Length)
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Cannot send keyboard input. The target may be running as administrator.");
        }
    }
}
'@
}

function ConvertTo-DesktopArgument {
    param([AllowEmptyString()][string]$Value)
    # Windows CommandLineToArgvW quoting, including trailing backslashes.
    if ($Value -ne '' -and $Value -notmatch '[\s"]') { return $Value }
    '"' + (($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1') + '"'
}

function Invoke-DesktopProcess {
    param([Parameter(Mandatory = $true)][string]$FilePath, [string[]]$Arguments = @(), [switch]$Hidden)
    $parameters = @{ FilePath = $FilePath; ErrorAction = 'Stop' }
    if ($Arguments.Count) { $parameters.ArgumentList = ($Arguments | ForEach-Object { ConvertTo-DesktopArgument $_ }) -join ' ' }
    if ($Hidden) { $parameters.WindowStyle = 'Hidden' }
    Start-Process @parameters | Out-Null
}

function Get-DesktopExecutable {
    param([string]$Name, [string[]]$Candidates = @())
    foreach ($root in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths')) {
        $path = Join-Path $root $Name
        if (Test-Path -LiteralPath $path) {
            $executable = [Environment]::ExpandEnvironmentVariables((Get-Item -LiteralPath $path).GetValue(''))
            if ($executable -and (Test-Path -LiteralPath $executable -PathType Leaf)) { return $executable }
        }
    }
    foreach ($candidate in $Candidates) {
        $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
        $match = @(Get-Item -Path $expanded -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Sort-Object FullName -Descending)
        if ($match.Count) { return $match[0].FullName }
    }
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
    $null
}

function Invoke-InstalledDesktopApp {
    param([string]$Name, [string]$Executable, [string[]]$Candidates, [string]$StartMenuPattern, [string]$FallbackUrl, [string]$PackageId)
    $path = Get-DesktopExecutable -Name $Executable -Candidates $Candidates
    if ($path) { Invoke-DesktopProcess $path; return }
    if (Get-Command Get-StartApps -ErrorAction SilentlyContinue) {
        $app = Get-StartApps | Where-Object { $_.Name -match $StartMenuPattern } | Select-Object -First 1
        if ($app) { Invoke-DesktopProcess (Join-Path $env:WINDIR 'explorer.exe') @('shell:AppsFolder\' + $app.AppID); return }
    }
    if ($FallbackUrl) { Invoke-DesktopProcess $FallbackUrl; return }
    throw "$Name is not installed. Install it with: winget install --id $PackageId --exact"
}

function Invoke-WslDesktopTerminal {
    param([ValidateSet('', 'btop', 'nvim', 'lazydocker')][string]$Command = '')
    $shellCommand = 'exec ghostty'
    if ($Command) { $shellCommand += ' -e ' + $Command }
    Invoke-DesktopProcess (Join-Path $env:SystemRoot 'System32\wsl.exe') @('--distribution', 'NixOS', '--cd', '~', '--exec', 'bash', '-lc', $shellCommand) -Hidden
}

function ConvertTo-WslShellArgument {
    param([AllowEmptyString()][string]$Value)
    $quote = [string][char]39
    $quote + $Value.Replace($quote, ($quote + '"' + $quote + '"' + $quote)) + $quote
}

function Invoke-WslDesktopProcess {
    param([Parameter(Mandatory = $true)][Diagnostics.ProcessStartInfo]$StartInfo)
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $StartInfo
    try {
        if (-not $process.Start()) { throw 'Windows could not start the WSL application launcher.' }
        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) {
            $process.Kill()
            throw 'The WSL application launcher did not respond within 30 seconds.'
        }
        [pscustomobject]@{ ExitCode = $process.ExitCode; ErrorText = $standardError.GetAwaiter().GetResult(); OutputText = $standardOutput.GetAwaiter().GetResult() }
    }
    finally { $process.Dispose() }
}

function Invoke-WslDesktopCommand {
    param([Parameter(Mandatory = $true)][string]$ShellCommand, [switch]$PassThru)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = Join-Path $env:SystemRoot 'System32\wsl.exe'
    $startInfo.Arguments = (@('--distribution', 'NixOS', '--cd', '~', '--exec', 'bash', '-lc', $ShellCommand) | ForEach-Object { ConvertTo-DesktopArgument $_ }) -join ' '
    $startInfo.WorkingDirectory = [IO.Path]::GetDirectoryName($script:DesktopActionScriptPath)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $startInfo.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $result = Invoke-WslDesktopProcess -StartInfo $startInfo
    if ($result.ExitCode -ne 0) {
        $errorText = [string]$result.ErrorText
        if ([string]::IsNullOrWhiteSpace($errorText)) { $errorText = [string]$result.OutputText }
        throw ('WSL application launch failed (exit ' + $result.ExitCode + '): ' + $errorText.Trim())
    }
    if ($PassThru) { [string]$result.OutputText }
}

function Invoke-WslDesktopApplication {
    param([Parameter(Mandatory = $true)][ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._+-]*$')][string]$Executable, [string[]]$Arguments = @())
    $quotedExecutable = ConvertTo-WslShellArgument $Executable
    $command = (@($quotedExecutable) + @($Arguments | ForEach-Object { ConvertTo-WslShellArgument $_ })) -join ' '
    $missing = ConvertTo-WslShellArgument ("Missing WSL application: $Executable. Apply the NixOS dotfiles configuration with nrs.")
    # Source files use CRLF on Windows. Construct shell lines explicitly so
    # bash receives LF separators while argument data keeps its original bytes.
    $preflightCommand = @(
        'set -e'
        "command -v $quotedExecutable >/dev/null 2>&1 || { printf '%s\n' $missing >&2; exit 127; }"
    ) -join "`n"
    Invoke-WslDesktopCommand -ShellCommand $preflightCommand
    # WSLg applications need their foreground WSL session to stay alive. Let
    # Windows own the hidden wsl.exe process, as for the Ghostty launcher, and
    # replace bash with the application instead of detaching its Linux child.
    Invoke-DesktopProcess (Join-Path $env:SystemRoot 'System32\wsl.exe') @('--distribution', 'NixOS', '--cd', '~', '--exec', 'bash', '-lc', ('exec ' + $command)) -Hidden
}

function Invoke-PrivateDesktopBrowser {
    Invoke-WslDesktopApplication -Executable 'google-chrome' -Arguments @('--incognito', '--new-window')
}

function Send-DesktopChord {
    param([uint16[]]$Keys, [IntPtr]$ExpectedWindow = [IntPtr]::Zero, [AllowNull()][object]$Cancellation = $null, [AllowNull()][object]$ExpectedControl = $null)
    Initialize-DesktopNative
    # The original PowerToys chord must be released before synthesizing another.
    $deadline = [DateTime]::UtcNow.AddSeconds(3)
    do {
        if ($null -ne $Cancellation -and $Cancellation.IsCancelled) { return }
        $held = @(@(16, 17, 18, 91, 92) | Where-Object { [DotfilesDesktop.Native]::GetAsyncKeyState($_) -lt 0 })
        if (-not $held.Count) { break }
        Start-Sleep -Milliseconds 25
    } while ([DateTime]::UtcNow -lt $deadline)
    if ($null -ne $Cancellation -and $Cancellation.IsCancelled) { return }
    if ($held.Count) { throw 'Release the shortcut modifiers and try again.' }
    if ($ExpectedWindow -ne [IntPtr]::Zero -and [DotfilesDesktop.Native]::GetForegroundWindow() -ne $ExpectedWindow) { throw 'Focus changed before keyboard input could be sent. Try again.' }
    if ($null -ne $Cancellation -and $Cancellation.IsCancelled) { return }
    if ($null -ne $ExpectedControl -and -not $ExpectedControl.Current.HasKeyboardFocus) { throw 'Control focus changed before keyboard input could be sent. Try again.' }
    [DotfilesDesktop.Native]::Chord($Keys)
}

function Get-DesktopWindowIdentity {
    param([IntPtr]$Window)
    Initialize-DesktopNative
    $processId = [uint32]0
    [void][DotfilesDesktop.Native]::GetWindowThreadProcessId($Window, [ref]$processId)
    $process = Get-Process -Id $processId -ErrorAction Stop
    $appId = [DotfilesDesktop.Native]::GetWindowAppId($Window)
    if ($process.ProcessName -match '^(msrdc|mstsc|wslg|wslhost)$' -and ($appId -eq '' -or $appId -match '^Microsoft\.RemoteApp\.[A-Za-z0-9+/]{43}=$')) {
        $linuxAppId = Resolve-DesktopWslgAppId -Window $Window
        if ($linuxAppId) { $appId = $linuxAppId }
    }
    [pscustomobject]@{ ProcessName = $process.ProcessName; AppId = $appId }
}

function Get-DesktopWslgWindowId {
    param([IntPtr]$Window)
    Initialize-DesktopNative
    $value = [DotfilesDesktop.Native]::GetWindowProperty($Window, 'WslgServerWindowId').ToInt64()
    [BitConverter]::ToUInt64([BitConverter]::GetBytes($value), 0)
}

function ConvertFrom-DesktopWslgMetadata {
    param([AllowEmptyString()][string]$Metadata, [uint64]$ServerWindowId)
    if ($ServerWindowId -eq 0) { return '' }
    $providerId = [uint32]($ServerWindowId -shr 32)
    $windowId = [uint32]($ServerWindowId -band [uint64]4294967295)
    if ($providerId -eq 0 -or $windowId -eq 0) { return '' }
    $providerName = ''
    $currentProviderId = [uint32]0
    $appId = ''
    foreach ($line in ($Metadata -split '\r?\n')) {
        if ($line -match 'appListProviderName:') {
            # A new provider handshake starts a new peer/session. Do not carry
            # a previous peer's reused numeric window ID into this session.
            $providerName = ''
            $currentProviderId = [uint32]0
            $appId = ''
            if ($line -match '^\[\d{2}:\d{2}:\d{2}\.\d{3}\]\s+appListProviderName:(?<provider>[A-Za-z0-9._-]+)\s*$') { $providerName = $Matches.provider }
            continue
        }
        if ($line -match 'appListProviderUniqueId:') {
            $currentProviderId = [uint32]0
            $appId = ''
            if ($line -match '^\[\d{2}:\d{2}:\d{2}\.\d{3}\]\s+appListProviderUniqueId:(?<id>[A-Fa-f0-9]{8})-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}\s*$') {
                $currentProviderId = [uint32]::Parse($Matches.id, [Globalization.NumberStyles]::HexNumber)
            }
            continue
        }
        if ($providerName -cne 'NixOS' -or $currentProviderId -ne $providerId) { continue }
        if ($line -match 'WindowDestroy\(0x(?<id>[A-Fa-f0-9]{1,8})\)') {
            if ([uint32]::Parse($Matches.id, [Globalization.NumberStyles]::HexNumber) -eq $windowId) { $appId = '' }
            continue
        }
        if ($line -notmatch 'ClientGetAppidReq:') { continue }
        if ($line -notmatch 'WindowId:0x(?<id>[A-Fa-f0-9]{1,8})\s*$') { $appId = ''; continue }
        if ([uint32]::Parse($Matches.id, [Globalization.NumberStyles]::HexNumber) -ne $windowId) { continue }
        $appId = ''
        if ($line -match '^\[\d{2}:\d{2}:\d{2}\.\d{3}\] Client: ClientGetAppidReq: pid:\d+ appId:(?<app>[A-Za-z0-9._+-]{1,128}) WindowId:0x[A-Fa-f0-9]{1,8}\s*$') { $appId = $Matches.app }
    }
    $appId
}

function Resolve-DesktopWslgAppId {
    param([IntPtr]$Window)
    $serverWindowId = Get-DesktopWslgWindowId -Window $Window
    if ($serverWindowId -eq 0) { return '' }
    try {
        # WSLg's RDP client hashes AppUserModelID. Its native window property
        # carries provider/window IDs; join those to current Weston metadata.
        # Return only identity records, never browser titles or document text.
        $metadata = Invoke-WslDesktopCommand -ShellCommand 'LC_ALL=C grep -E ''appListProvider(Name|UniqueId):|Client: ClientGetAppidReq:|WindowDestroy\(0x[[:xdigit:]]+\)'' /mnt/wslg/weston.log' -PassThru
        if ((Get-DesktopWslgWindowId -Window $Window) -ne $serverWindowId) { return '' }
        ConvertFrom-DesktopWslgMetadata -Metadata $metadata -ServerWindowId $serverWindowId
    }
    catch { '' }
}

function Test-DesktopBrowserWindow {
    param([IntPtr]$Window, [AllowNull()][object]$Identity = $null)
    if ($null -eq $Identity) { $Identity = Get-DesktopWindowIdentity -Window $Window }
    if ($Identity.ProcessName -match '^(chrome|msedge|firefox|brave|vivaldi|arc|opera)$') { return $true }
    if ($Identity.ProcessName -notmatch '^(msrdc|mstsc|wslg|wslhost)$') { return $false }
    # Chromium's Linux desktop IDs include google-chrome(-stable) and web-app
    # shortcut IDs chrome-<extension-id>-<profile>. Neither uses window titles.
    $Identity.AppId -match '(?i)(?:^|[.!_\\/])(?:(?:(?:google[-_.])?chrome|chromium)(?:[-_.](?:stable|beta|dev|browser)|-[a-p]{32}-(?:Default|Profile[-_]?\d+))?|crx_[a-p]{32})(?:$|[.!_\\/])'
}

function Get-DesktopClipboardContext {
    param([IntPtr]$Window)
    $identity = Get-DesktopWindowIdentity -Window $Window
    if ($identity.ProcessName -ieq 'ghostty' -or $identity.AppId -match '(?i)(?:^|[.!_\\/])ghostty(?:$|[.!_\\/])') { return 'ghostty' }
    if ($identity.ProcessName -match '^(msrdc|mstsc|wslg|wslhost)$') {
        # WSLg hosts many applications in one Windows process. A window title
        # or its host process cannot distinguish a terminal from a normal GUI.
        # Fail closed when identity is missing; Ctrl+C could interrupt a job.
        if (Test-DesktopBrowserWindow -Window $Window -Identity $identity) { return 'application' }
        if ($identity.AppId -match '(?i)(?:^|[.!_\\/])(firefox|brave|nautilus|thunar|obsidian|signal(?:-desktop)?|spotify|1password|onepassword|gimp|inkscape)(?:$|[.!_\\/])') { return 'application' }
        throw ('Cannot safely identify this WSLg/Remote Desktop application for clipboard input. AppUserModelID: ' + $identity.AppId + '. Use its own copy/paste shortcut.')
    }
    'application'
}

function Invoke-DesktopClipboard {
    param([ValidateSet('copy', 'cut', 'paste')][string]$Operation)
    Initialize-DesktopNative
    $window = [DotfilesDesktop.Native]::GetForegroundWindow()
    if ($window -eq [IntPtr]::Zero) { throw 'No foreground application is available for clipboard input.' }
    $context = Get-DesktopClipboardContext -Window $window
    if ($context -eq 'ghostty') {
        # Terminal output is read-only: cut copies the selected text rather
        # than injecting Ctrl+X into the running shell or terminal program.
        $key = if ($Operation -eq 'paste') { [uint16]86 } else { [uint16]67 }
        Send-DesktopChord @(17, 16, $key) -ExpectedWindow $window
    }
    else {
        $key = switch ($Operation) { 'copy' { [uint16]67 }; 'cut' { [uint16]88 }; 'paste' { [uint16]86 } }
        Send-DesktopChord @(17, $key) -ExpectedWindow $window
    }
}

function Get-DesktopUiRoot {
    param([IntPtr]$Window = [IntPtr]::Zero)
    Initialize-DesktopNative
    if ($Window -eq [IntPtr]::Zero) { $Window = [DotfilesDesktop.Native]::GetForegroundWindow() }
    [DotfilesDesktop.UiClient]::FromHandle($Window)
}

function Assert-DesktopShellPanel {
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        $processId = [uint32]0
        $window = [DotfilesDesktop.Native]::GetForegroundWindow()
        [void][DotfilesDesktop.Native]::GetWindowThreadProcessId($window, [ref]$processId)
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        $className = New-Object Text.StringBuilder 256
        [void][DotfilesDesktop.Native]::GetClassName($window, $className, $className.Capacity)
        if ($process -and $process.ProcessName -match '^(explorer|ShellExperienceHost|ShellHost)$' -and $className.ToString() -in @('ControlCenterWindow', 'Windows.UI.Core.CoreWindow')) { return $window }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'The Windows shell panel did not open. Close another active popup and try again.'
}

function Assert-DesktopPanelFocus {
    param([IntPtr]$Window)
    if ([DotfilesDesktop.Native]::GetForegroundWindow() -ne $Window) { throw 'Focus changed while operating the Windows panel. Try the shortcut again.' }
}

function Test-DesktopElementUnavailable {
    param([Parameter(Mandatory = $true)][System.Exception]$Exception)
    # COM8 reports the UIA HRESULT directly; PowerShell and reflection can
    # wrap it in invocation exceptions before it reaches the UI search.
    $current = $Exception
    while ($null -ne $current) {
        # UIA_E_ELEMENTNOTAVAILABLE (0x80040201) as a signed HRESULT.
        if ($current.GetType().FullName -eq 'System.Windows.Automation.ElementNotAvailableException' -or
            ($current -is [Runtime.InteropServices.COMException] -and $current.HResult -eq -2147220991)) {
            return $true
        }
        $current = $current.InnerException
    }
    $false
}

function Get-DesktopUiControls {
    param([Parameter(Mandatory = $true)][IntPtr]$Window)
    Assert-DesktopPanelFocus $Window
    try { $root = Get-DesktopUiRoot -Window $Window }
    catch {
        if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
        $script:DesktopUiDiagnostics = 'UIA pinned panel became unavailable before enumeration.'
        return
    }
    if ($root) {
        $controls = New-Object 'Collections.Generic.List[object]'
        $controls.Add($root)
        try {
            foreach ($control in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) { $controls.Add($control) }
        }
        catch {
            if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
            $script:DesktopUiDiagnostics = 'UIA pinned panel became unavailable during enumeration.'
            return
        }
        $identities = @($controls | ForEach-Object {
                try { 'class=' + $_.Current.ClassName + ';id=' + $_.Current.AutomationId }
                catch {
                    if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
                    'unavailable-element'
                }
            } | Select-Object -Unique -First 12)
        try { $rootIdentity = 'rootClass=' + $root.Current.ClassName + ';rootId=' + $root.Current.AutomationId + ';rootPid=' + $root.Current.ProcessId }
        catch {
            if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
            $rootIdentity = 'root=unavailable-element'
        }
        $script:DesktopUiDiagnostics = ('UIA view=com8;count=' + $controls.Count + ';' + $rootIdentity + ';elements=' + ($identities -join ' | '))
        $controls.ToArray()
    }
    else { $script:DesktopUiDiagnostics = 'UIA root unavailable for the pinned panel.' }
}

function Move-DesktopUiGrid {
    param([Parameter(Mandatory = $true)][IntPtr]$Window, [switch]$Reset)
    Assert-DesktopPanelFocus $Window
    $className = New-Object Text.StringBuilder 256
    [void][DotfilesDesktop.Native]::GetClassName($Window, $className, $className.Capacity)
    if ($className.ToString() -ne 'ControlCenterWindow') { throw 'Quick Settings scrolling requires the pinned ControlCenterWindow panel.' }
    $script:DesktopGridDiagnostics = @()
    foreach ($control in @(Get-DesktopUiControls -Window $Window)) {
        $pattern = $null
        try {
            $hasScroll = $control.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern, [ref]$pattern)
            if ($hasScroll -or $control.Current.ClassName -match 'Scroll|Grid|ItemsRepeater') {
                $script:DesktopGridDiagnostics += ('class=' + $control.Current.ClassName + ';id=' + $control.Current.AutomationId + ';scroll=' + $hasScroll)
            }
            if (-not $hasScroll -or -not $pattern.Current.VerticallyScrollable) { continue }
            $before = $pattern.Current.VerticalScrollPercent
            Assert-DesktopPanelFocus $Window
            if ($Reset) { $pattern.SetScrollPercent([System.Windows.Automation.ScrollPattern]::NoScroll, 0) }
            elseif ($before -ge 100) { continue }
            else { $pattern.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount, [System.Windows.Automation.ScrollAmount]::LargeIncrement) }
            # Give virtualized tiles time to enter the accessibility tree.
            Start-Sleep -Milliseconds 250
            Assert-DesktopPanelFocus $Window
            return ($pattern.Current.VerticalScrollPercent -ne $before)
        }
        catch {
            if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
        }
    }
    $false
}

function Find-DesktopUiControl {
    param([Parameter(Mandatory = $true)][IntPtr]$Window, [string[]]$Names = @(), [string[]]$Ids = @(), [int]$TimeoutSeconds = 5, [switch]$Scroll)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $scrollReset = $false
    $script:DesktopGridDiagnostics = @()
    $script:DesktopUiDiagnostics = ''
    do {
        Assert-DesktopPanelFocus $Window
        foreach ($control in @(Get-DesktopUiControls -Window $Window)) {
            try {
                $nameMatches = $Names -contains $control.Current.Name
                foreach ($name in $Names) {
                    if ($control.Current.Name.StartsWith($name + ',') -or $control.Current.Name.StartsWith($name + ':')) { $nameMatches = $true; break }
                }
                if ($control.Current.IsEnabled -and (($Ids -contains $control.Current.AutomationId) -or $nameMatches)) {
                    foreach ($patternId in @([System.Windows.Automation.TogglePattern]::Pattern, [System.Windows.Automation.InvokePattern]::Pattern, [System.Windows.Automation.SelectionItemPattern]::Pattern)) {
                        $pattern = $null
                        if ($control.TryGetCurrentPattern($patternId, [ref]$pattern)) { return $control }
                    }
                }
            }
            catch {
                if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
            }
        }
        if ($Scroll) {
            if (-not $scrollReset) {
                [void](Move-DesktopUiGrid -Window $Window -Reset)
                $scrollReset = $true
            }
            else { [void](Move-DesktopUiGrid -Window $Window) }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    $diagnostics = if ($Scroll -and $script:DesktopGridDiagnostics.Count) { ' Scroll containers: ' + (($script:DesktopGridDiagnostics | Select-Object -Unique) -join ' | ') } else { '' }
    throw ('Windows did not expose the required control: ' + (($Names + $Ids) -join ', ') + '. This action supports the English and Japanese Windows 11 shell.' + $diagnostics + ' ' + $script:DesktopUiDiagnostics)
}

function Invoke-DesktopUiControl {
    param([object]$Control, [Parameter(Mandatory = $true)][IntPtr]$Window, [switch]$Toggle, [string]$ActionName = '', [ValidateRange(1, 10000)][int]$ToggleTimeoutMilliseconds = 3000)
    Assert-DesktopPanelFocus $Window
    $pattern = $null
    if ($Toggle) {
        if (-not $Control.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)) { throw 'The Windows control does not expose a verifiable toggle state.' }
        $before = [int]$pattern.Current.ToggleState
        $pattern.Toggle()
        $deadline = [DateTime]::UtcNow.AddMilliseconds($ToggleTimeoutMilliseconds)
        do {
            Assert-DesktopPanelFocus $Window
            $after = [int]$pattern.Current.ToggleState
            if ($after -ne $before) {
                if ($ActionName) { Write-DesktopActionEvidence -Name $ActionName -Details @{ operation = 'toggle'; before = $before; after = $after } }
                return
            }
            Start-Sleep -Milliseconds 50
        } while ([DateTime]::UtcNow -lt $deadline)
        throw ('The Windows toggle state did not change (state=' + $before + ').')
    }
    if ($Control.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
        $pattern.Invoke()
        if ($ActionName) { Write-DesktopActionEvidence -Name $ActionName -Status 'submitted' -Details @{ operation = 'invoke'; requestSubmitted = $true } }
        return
    }
    if ($Control.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
        $pattern.Select()
        if ($ActionName) { Write-DesktopActionEvidence -Name $ActionName -Status 'submitted' -Details @{ operation = 'select'; requestSubmitted = $true } }
        return
    }
    throw 'The required Windows control is not invokable through UI Automation.'
}

function Write-DesktopActionEvidence {
    param([Parameter(Mandatory = $true)][string]$Name, [Parameter(Mandatory = $true)][hashtable]$Details, [ValidateSet('verified', 'submitted')][string]$Status = 'verified')
    # Only callers' static operation names, numeric states and booleans belong
    # here. Do not record control names, network names or audio device labels.
    $directory = Join-Path $env:LOCALAPPDATA 'dotfiles\keybindings'
    [void][IO.Directory]::CreateDirectory($directory)
    $line = [DateTime]::Now.ToString('o') + ' ' + $Name + ': ' + $Status + ' ' + ($Details | ConvertTo-Json -Compress -Depth 5) + [Environment]::NewLine
    [IO.File]::AppendAllText((Join-Path $directory 'actions.log'), $line, (New-Object Text.UTF8Encoding($false)))
}

function Test-DesktopUiSameElement {
    param([object]$First, [object]$Second)
    if ($First -is [DotfilesDesktop.UiElement] -and $Second -is [DotfilesDesktop.UiElement]) { return [DotfilesDesktop.UiClient]::Same($First, $Second) }
    [System.Windows.Automation.Automation]::Compare($First, $Second)
}

function Get-DesktopJapaneseLabel {
    param([string]$Escaped)
    ('"' + $Escaped + '"') | ConvertFrom-Json
}

function Get-DesktopNotificationDiagnostics {
    param([Parameter(Mandatory = $true)][IntPtr]$Window, [string[]]$ActionNames = @())
    $candidates = @()
    $containers = @()
    foreach ($control in @(Get-DesktopUiControls -Window $Window)) {
        try {
            $className = ([string]$control.Current.ClassName).Replace("`r", ' ').Replace("`n", ' ')
            $automationId = ([string]$control.Current.AutomationId).Replace("`r", ' ').Replace("`n", ' ')
            $name = [string]$control.Current.Name
            $staticActionName = $ActionNames -contains $name
            if (($className + ';' + $automationId) -match 'Close|Dismiss|Clear|Notification' -or $staticActionName) {
                $identity = 'class=' + $className + ';id=' + $automationId + ';enabled=' + [bool]$control.Current.IsEnabled
                # Notification bodies/senders can be UIA names. Only an exact
                # match to our static action vocabulary may enter diagnostics.
                if ($staticActionName) { $identity += ';actionLabel=' + $name }
                if (($className + ';' + $automationId) -match 'Close|Dismiss|Clear' -or $staticActionName) { $candidates += $identity }
                else { $containers += $identity }
            }
        }
        catch {
            if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
        }
    }
    if ($candidates.Count -eq 0 -and $containers.Count -eq 0) { return 'none' }
    (@($candidates) + @($containers) | Select-Object -Unique -First 40) -join ' | '
}

function Get-DesktopNotificationDismissNames {
    @('Dismiss notification', 'Clear notification', 'Close notification', 'Dismiss', 'Close',
        (Get-DesktopJapaneseLabel '\u3053\u306e\u901a\u77e5\u3092\u9589\u3058\u308b'),
        (Get-DesktopJapaneseLabel '\u901a\u77e5\u306e\u30af\u30ea\u30a2'),
        (Get-DesktopJapaneseLabel '\u901a\u77e5\u3092\u30af\u30ea\u30a2'),
        (Get-DesktopJapaneseLabel '\u3053\u306e\u901a\u77e5\u3092\u30af\u30ea\u30a2'),
        (Get-DesktopJapaneseLabel '\u3053\u306e\u901a\u77e5\u3092\u6d88\u53bb'),
        (Get-DesktopJapaneseLabel '\u901a\u77e5\u3092\u6d88\u53bb'),
        (Get-DesktopJapaneseLabel '\u9589\u3058\u308b'))
}

function Get-DesktopNotificationControls {
    param([Parameter(Mandatory = $true)][IntPtr]$Window)
    $areas = @()
    foreach ($control in @(Get-DesktopUiControls -Window $Window)) {
        try {
            if ($control.Current.AutomationId -eq 'NotificationCenterGrid') { $areas += $control }
        }
        catch {
            if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
            return
        }
    }
    # Calendar and notification controls share a shell window. The anchor
    # must be unique before a same-label control can be selected or counted.
    if ($areas.Count -ne 1) { return }
    try {
        $descendants = @($areas[0].FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))
    }
    catch {
        if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
        return
    }
    @($areas[0]) + $descendants
}

function Find-DesktopNotificationControl {
    param([Parameter(Mandatory = $true)][IntPtr]$Window, [string[]]$Names = @(), [string[]]$Ids = @(), [int]$TimeoutSeconds = 5, [switch]$Toggle)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $patternId = if ($Toggle) { [System.Windows.Automation.TogglePattern]::Pattern } else { [System.Windows.Automation.InvokePattern]::Pattern }
    do {
        Assert-DesktopPanelFocus $Window
        foreach ($control in @(Get-DesktopNotificationControls -Window $Window)) {
            try {
                $id = [string]$control.Current.AutomationId
                # An app action can also be labelled Close. It does not
                # dismiss the notification card through the shell button.
                if ($id -eq 'VerbButton') { continue }
                $name = [string]$control.Current.Name
                $matches = $Names -contains $name
                foreach ($actionName in $Names) {
                    if ($name.StartsWith($actionName + ',') -or $name.StartsWith($actionName + ':')) { $matches = $true; break }
                }
                if ($control.Current.IsEnabled -and (($Ids -contains $id) -or $matches)) {
                    $pattern = $null
                    if ($control.TryGetCurrentPattern($patternId, [ref]$pattern)) { return $control }
                }
            }
            catch {
                if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
            }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw ('Windows did not expose the required notification control: ' + (($Names + $Ids) -join ', ') + '. ' + $script:DesktopUiDiagnostics)
}

function Get-DesktopNotificationState {
    param([Parameter(Mandatory = $true)][IntPtr]$Window, [string[]]$Names = (Get-DesktopNotificationDismissNames))
    $controls = @(Get-DesktopNotificationControls -Window $Window)
    # A root-only COM skeleton is not evidence of an empty notification center.
    $complete = $controls.Count -gt 1
    $targets = @()
    $dismissControls = @()
    $notificationArea = $false
    $clearAllPresent = $false
    $clearAllEnabled = $false
    $emptyAnchor = $false
    foreach ($control in $controls) {
        try {
            $id = [string]$control.Current.AutomationId
            if ($id -eq 'VerbButton') { continue }
            $enabled = [bool]$control.Current.IsEnabled
            if ($id -eq 'NotificationCenterGrid') { $notificationArea = $true }
            if ($id -eq 'NoNotificationsTextBlock') { $emptyAnchor = $true; continue }
            if ($id -eq 'ClearAllButton') {
                $clearAllPresent = $true
                $clearAllEnabled = $enabled
                continue
            }
            $name = [string]$control.Current.Name
            $matches = $Names -contains $name
            foreach ($actionName in $Names) {
                if ($name.StartsWith($actionName + ',') -or $name.StartsWith($actionName + ':')) { $matches = $true; break }
            }
            if (-not $matches) { continue }
            $pattern = $null
            if ($control.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
                # Keep disabled targets in the identity/count baseline: becoming
                # disabled while a request is pending does not prove removal.
                $targets += $control
                if ($enabled) { $dismissControls += $control }
            }
        }
        catch {
            if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
            $complete = $false
        }
    }
    # Calendar/scaffold nodes alone do not prove the notification subtree was
    # observed. Require its known container and an action/empty-state anchor.
    # Windows removes the actionable ClearAllButton after the last dismissal.
    $emptyState = $emptyAnchor -and $targets.Count -eq 0 -and -not $clearAllEnabled
    $complete = $complete -and $notificationArea -and ($clearAllPresent -or $targets.Count -gt 0 -or $emptyState)
    [pscustomobject]@{
        Complete = $complete; Controls = $controls; DismissTargets = $targets; DismissControls = $dismissControls
        ClearAllPresent = $clearAllPresent; ClearAllEnabled = $clearAllEnabled
        Empty = $complete -and $emptyState
    }
}

function Get-DesktopNotificationRemovalTarget {
    param([Parameter(Mandatory = $true)][object]$Control, [object[]]$Controls = @())
    $closest = @()
    $closestSize = [int]::MaxValue
    foreach ($candidate in $Controls) {
        if ($candidate.Current.ClassName -ne 'ListViewItem') { continue }
        $descendants = @($candidate.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))
        $containsControl = $false
        foreach ($descendant in $descendants) {
            if (Test-DesktopUiSameElement -First $descendant -Second $Control) { $containsControl = $true; break }
        }
        if (-not $containsControl) { continue }
        if ($descendants.Count -lt $closestSize) {
            $closest = @($candidate)
            $closestSize = $descendants.Count
        }
        elseif ($descendants.Count -eq $closestSize) { $closest += $candidate }
    }
    if ($closest.Count -gt 1) { throw 'Windows exposed ambiguous notification items for the selected dismiss control.' }
    # The shell can reuse a dismiss button for the next notification. Follow
    # its original card rather than the small control when a card is exposed.
    if ($closest.Count -eq 1) { return $closest[0] }
    $Control
}

function Get-DesktopNotificationTargetPresence {
    param([Parameter(Mandatory = $true)][object]$Control, [object[]]$Controls)
    foreach ($candidate in $Controls) {
        try {
            if (Test-DesktopUiSameElement -First $candidate -Second $Control) { return [pscustomobject]@{ Complete = $true; Present = $true } }
        }
        catch {
            if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
            # A stale comparison alone might come from the fresh candidate.
            # Probe the original element before treating it as removed.
            try { [void]$Control.Current.IsEnabled }
            catch {
                if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
                return [pscustomobject]@{ Complete = $true; Present = $false }
            }
            return [pscustomobject]@{ Complete = $false; Present = $false }
        }
    }
    [pscustomobject]@{ Complete = $true; Present = $false }
}

function Wait-DesktopNotificationRemoval {
    param(
        [Parameter(Mandatory = $true)][IntPtr]$Window,
        [Parameter(Mandatory = $true)][object]$Control,
        [Parameter(Mandatory = $true)][ValidateSet('dismiss', 'dismiss-all')][string]$Operation,
        [string[]]$Names = (Get-DesktopNotificationDismissNames),
        [int]$BeforeCount,
        [object[]]$BeforeControls = @(),
        [ValidateRange(0, 15000)][int]$TimeoutMilliseconds = 3000
    )
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
    $lastCount = -1
    do {
        Assert-DesktopPanelFocus $Window
        $state = Get-DesktopNotificationState -Window $Window -Names $Names
        if ($state.Complete) {
            if ($Operation -eq 'dismiss-all') {
                $lastCount = @($state.DismissControls).Count
                if ($lastCount -eq 0 -and (-not $state.ClearAllPresent -or -not $state.ClearAllEnabled)) {
                    $baselineRemoved = $true
                    foreach ($original in $BeforeControls) {
                        $presence = Get-DesktopNotificationTargetPresence -Control $original -Controls @($state.Controls)
                        if (-not $presence.Complete -or $presence.Present) { $baselineRemoved = $false; break }
                    }
                    if ($BeforeControls.Count -eq 0 -and $BeforeCount -gt 0 -and @($state.DismissTargets).Count -gt 0) { $baselineRemoved = $false }
                    if ($baselineRemoved) {
                        return @{ operation = $Operation; completed = $true; beforeCount = $BeforeCount; afterCount = 0; clearAllEnabled = $state.ClearAllEnabled }
                    }
                }
            }
            else {
                $lastCount = @($state.DismissTargets).Count
                $presence = Get-DesktopNotificationTargetPresence -Control $Control -Controls @($state.Controls)
                if ($presence.Complete -and -not $presence.Present) {
                    return @{ operation = $Operation; completed = $true; beforeCount = $BeforeCount; afterCount = $lastCount; targetRemoved = $true; countDecreased = $lastCount -lt $BeforeCount }
                }
            }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw ('Windows did not confirm notification removal (operation=' + $Operation + ';beforeCount=' + $BeforeCount + ';lastCount=' + $lastCount + ').')
}

function Invoke-DesktopNotificationDismissControl {
    param(
        [Parameter(Mandatory = $true)][object]$Control,
        [Parameter(Mandatory = $true)][IntPtr]$Window,
        [ValidateRange(0, 5000)][int]$FocusTimeoutMilliseconds = 1000
    )
    Assert-DesktopPanelFocus $Window
    [void]$Control.SetFocus()
    $deadline = [DateTime]::UtcNow.AddMilliseconds($FocusTimeoutMilliseconds)
    do {
        Assert-DesktopPanelFocus $Window
        if ($Control.Current.HasKeyboardFocus) {
            # The shell's notification Invoke provider can return without
            # dismissing. Activate the focused button once, then let the
            # caller verify removal; never also queue an Invoke request.
            Send-DesktopChord @(32) -ExpectedWindow $Window -ExpectedControl $Control
            return
        }
        Start-Sleep -Milliseconds 50
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Windows did not focus the notification dismiss control; no removal key was sent.'
}

function Invoke-DesktopNotification {
    param([ValidateSet('dismiss', 'dismiss-all', 'toggle', 'history')][string]$Operation)
    $panel = [IntPtr]::Zero
    $keepOpen = $Operation -eq 'history'
    Send-DesktopChord @(91, 78) # Windows 11 notification center.
    try {
        Start-Sleep -Milliseconds 250
        $panel = Assert-DesktopShellPanel
        if ($keepOpen) {
            Write-DesktopActionEvidence -Name 'notification-history' -Details @{ operation = 'history'; completed = $true }
            return
        }
        $names = switch ($Operation) {
            'dismiss' { Get-DesktopNotificationDismissNames }
            'dismiss-all' { @('Clear all notifications', 'Clear all', (Get-DesktopJapaneseLabel '\u3059\u3079\u3066\u30af\u30ea\u30a2'), (Get-DesktopJapaneseLabel '\u3059\u3079\u3066\u306e\u901a\u77e5\u3092\u30af\u30ea\u30a2')) }
            'toggle' { @('Do not disturb', (Get-DesktopJapaneseLabel '\u5fdc\u7b54\u4e0d\u53ef')) }
        }
        # ClearAllButton was observed on this Windows 11 notification panel.
        $ids = if ($Operation -eq 'dismiss-all') { @('ClearAllButton') } else { @() }
        try { $control = Find-DesktopNotificationControl -Window $panel -Names $names -Ids $ids -Toggle:($Operation -eq 'toggle') }
        catch {
            $failure = $_
            if ((Get-DesktopForegroundWindow) -eq $panel) {
                $diagnostics = Get-DesktopNotificationDiagnostics -Window $panel -ActionNames $names
                throw ($failure.Exception.Message + ' Notification candidate controls: ' + $diagnostics)
            }
            throw
        }
        if ($Operation -eq 'toggle') {
            Invoke-DesktopUiControl -Control $control -Window $panel -Toggle -ActionName 'notification-toggle'
        }
        else {
            $dismissNames = @(Get-DesktopNotificationDismissNames)
            $before = Get-DesktopNotificationState -Window $panel -Names $dismissNames
            if (-not $before.Complete) { throw 'Windows did not expose a complete notification state before removal.' }
            $beforeCount = if ($Operation -eq 'dismiss-all') { @($before.DismissControls).Count } else { @($before.DismissTargets).Count }
            $removalTarget = if ($Operation -eq 'dismiss') { Get-DesktopNotificationRemovalTarget -Control $control -Controls @($before.Controls) } else { $control }
            Invoke-DesktopNotificationDismissControl -Control $control -Window $panel
            $beforeControls = if ($Operation -eq 'dismiss-all') { @($before.DismissControls) } else { @($removalTarget) }
            $details = Wait-DesktopNotificationRemoval -Window $panel -Control $removalTarget -Operation $Operation -Names $dismissNames -BeforeCount $beforeCount -BeforeControls $beforeControls
            if ($details -isnot [hashtable]) { $details = @{ operation = $Operation; completed = $true; beforeCount = $beforeCount } }
            Write-DesktopActionEvidence -Name ('notification-' + $Operation) -Status 'verified' -Details $details
        }
    }
    finally {
        if (-not $keepOpen -and $panel -ne [IntPtr]::Zero -and (Get-DesktopForegroundWindow) -eq $panel) {
            Send-DesktopChord @(27) -ExpectedWindow $panel
        }
    }
}

function Switch-DesktopNightMode {
    Send-DesktopChord @(91, 65) # Quick Settings: invoke the actual Night light tile.
    Start-Sleep -Milliseconds 250
    $panel = Assert-DesktopShellPanel
    try {
        $control = Find-DesktopUiControl -Window $panel -Names @('Night light', (Get-DesktopJapaneseLabel '\u591c\u9593\u30e2\u30fc\u30c9')) -Ids @('Microsoft.QuickAction.BlueLightReduction') -Scroll
        Invoke-DesktopUiControl -Control $control -Window $panel -Toggle -ActionName 'night-mode-toggle'
    }
    finally {
        if ([DotfilesDesktop.Native]::GetForegroundWindow() -eq $panel) { Send-DesktopChord @(27) -ExpectedWindow $panel }
    }
}

function Get-DesktopAudioDiagnostics {
    param([Parameter(Mandatory = $true)][IntPtr]$Window)
    $index = 0
    foreach ($control in @(Get-DesktopUiControls -Window $Window)) {
        try {
            $row = [ordered]@{
                Index = $index; ClassName = $control.Current.ClassName; AutomationId = $control.Current.AutomationId
                IsEnabled = $control.Current.IsEnabled
                InvokeAvailable = $false; ToggleAvailable = $false; ToggleState = $null
                SelectionAvailable = $false; IsSelected = $null
                ContainerClassName = $null; ContainerAutomationId = $null
            }
            $pattern = $null
            $row.InvokeAvailable = $control.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)
            $pattern = $null
            $row.ToggleAvailable = $control.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$pattern)
            if ($row.ToggleAvailable) { $row.ToggleState = [int]$pattern.Current.ToggleState }
            $pattern = $null
            $row.SelectionAvailable = $control.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)
            if ($row.SelectionAvailable) {
                $row.IsSelected = [bool]$pattern.Current.IsSelected
                $container = $pattern.Current.SelectionContainer
                if ($null -ne $container) {
                    $row.ContainerClassName = $container.Current.ClassName
                    $row.ContainerAutomationId = $container.Current.AutomationId
                }
            }
            [pscustomobject]$row
        }
        catch {
            if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
        }
        $index++
    }
}

function Switch-DesktopAudioOutput {
    # Win+Ctrl+V belongs to the shared clipboard action. Open the selector from
    # Quick Settings instead of injecting a chord that PowerToys remaps.
    Send-DesktopChord @(91, 65)
    Start-Sleep -Milliseconds 250
    $panel = Assert-DesktopShellPanel
    $selector = Find-DesktopUiControl -Window $panel -Names @('Select a sound output', (Get-DesktopJapaneseLabel '\u30b5\u30a6\u30f3\u30c9\u51fa\u529b\u306e\u9078\u629e'), (Get-DesktopJapaneseLabel '\u30b5\u30a6\u30f3\u30c9\u51fa\u529b\u3092\u9078\u629e'))
    Invoke-DesktopUiControl -Control $selector -Window $panel
    $panel = Assert-DesktopShellPanel
    $deadline = [DateTime]::UtcNow.AddSeconds(5)
    do {
        Assert-DesktopPanelFocus $panel
        $items = @()
        $staleEndpoints = $false
        foreach ($control in @(Get-DesktopUiControls -Window $panel)) {
            $pattern = $null
            try {
                if ($control.Current.IsEnabled -and $control.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
                    $container = $pattern.Current.SelectionContainer
                    # The Sound output page also exposes a separate selected
                    # spatial-sound group. Only this list contains endpoints.
                    if ($null -eq $container -or $container.Current.AutomationId -ne 'ListWithOutputGroupTitle') { continue }
                    # Read the endpoint state before any Select call so a stale
                    # search can retry without cycling the output twice.
                    $items += [pscustomobject]@{
                        Control = $control; Pattern = $pattern
                        Selected = $pattern.Current.IsSelected; Container = $container
                    }
                }
            }
            catch {
                if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
                $staleEndpoints = $true
            }
        }
        if ($staleEndpoints) {
            Start-Sleep -Milliseconds 100
            continue
        }
        $selected = @($items | Where-Object { $_.Selected })
        if ($selected.Count -eq 1) {
            # Only cycle siblings in the selected endpoint's selection container.
            $container = $selected[0].Container
            try { $devices = @($items | Where-Object { Test-DesktopUiSameElement -First $_.Container -Second $container }) }
            catch {
                if (-not (Test-DesktopElementUnavailable -Exception $_.Exception)) { throw }
                Start-Sleep -Milliseconds 100
                continue
            }
            if ($devices.Count -gt 0) {
                $index = 0
                for ($i = 0; $i -lt $devices.Count; $i++) { if ($devices[$i].Selected) { $index = $i; break } }
                Assert-DesktopPanelFocus $panel
                $nextIndex = ($index + 1) % $devices.Count
                if ($devices.Count -eq 1) { throw 'Windows exposes only one active audio output; there is no other output to select.' }
                $devices[$nextIndex].Pattern.Select()
                $selectionDeadline = [DateTime]::UtcNow.AddSeconds(3)
                do {
                    Assert-DesktopPanelFocus $panel
                    if ($devices[$nextIndex].Pattern.Current.IsSelected) {
                        Write-DesktopActionEvidence -Name 'audio-output-cycle' -Details @{ operation = 'select'; beforeIndex = $index; afterIndex = $nextIndex; count = $devices.Count }
                        if ([DotfilesDesktop.Native]::GetForegroundWindow() -eq $panel) { Send-DesktopChord @(27) -ExpectedWindow $panel }
                        return
                    }
                    Start-Sleep -Milliseconds 50
                } while ([DateTime]::UtcNow -lt $selectionDeadline)
                throw 'Windows did not select the next audio output.'
            }
        }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw 'Windows did not expose selectable audio endpoints. Choose an output in the open sound output panel and update Windows 11.'
}

function Switch-DesktopBar {
    Initialize-DesktopNative
    $bar = New-Object DotfilesDesktop.Native+APPBARDATA
    $bar.cbSize = [Runtime.InteropServices.Marshal]::SizeOf($bar)
    $bar.hWnd = [DotfilesDesktop.Native]::FindWindow('Shell_TrayWnd', $null)
    if ($bar.hWnd -eq [IntPtr]::Zero) { throw 'Windows taskbar was not found.' }
    $state = [DotfilesDesktop.Native]::SHAppBarMessage(4, [ref]$bar).ToUInt64()
    $bar.lParam = [IntPtr]([long]($state -bxor 1))
    [void][DotfilesDesktop.Native]::SHAppBarMessage(10, [ref]$bar)
}

function Switch-DesktopTheme {
    Initialize-DesktopNative
    $path = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $settings = Get-ItemProperty -LiteralPath $path
    $light = if ($settings.AppsUseLightTheme -eq 0) { 1 } else { 0 }
    foreach ($property in @('AppsUseLightTheme', 'SystemUsesLightTheme')) { Set-ItemProperty -LiteralPath $path -Name $property -Type DWord -Value $light }
    $result = [UIntPtr]::Zero
    [void][DotfilesDesktop.Native]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'ImmersiveColorSet', 2, 2000, [ref]$result)
}

function Switch-DesktopBackground {
    Initialize-DesktopNative
    $folder = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Wallpapers'
    if (-not (Test-Path -LiteralPath $folder -PathType Container)) { $folder = Join-Path $env:WINDIR 'Web\Wallpaper' }
    $images = @(Get-ChildItem -LiteralPath $folder -Recurse -File | Where-Object { $_.Extension -match '^\.(jpg|jpeg|png|bmp)$' } | Sort-Object FullName)
    if (-not $images.Count) { throw "No wallpapers found. Add images to $folder." }
    $current = (Get-ItemProperty -LiteralPath 'HKCU:\Control Panel\Desktop' -Name WallPaper).WallPaper
    $index = -1
    for ($i = 0; $i -lt $images.Count; $i++) { if ($images[$i].FullName -eq $current) { $index = $i; break } }
    $next = $images[($index + 1) % $images.Count].FullName
    if (-not [DotfilesDesktop.Native]::SystemParametersInfo(20, 0, $next, 3)) { throw 'Windows could not apply the next wallpaper.' }
}

function Switch-DesktopTransparency {
    Initialize-DesktopNative
    $window = [DotfilesDesktop.Native]::GetForegroundWindow()
    if ($window -eq [IntPtr]::Zero) { throw 'No foreground window is available.' }
    $style = [DotfilesDesktop.Native]::GetWindowLong($window, -20)
    $color = [uint32]0; $alpha = [byte]255; $flags = [uint32]0
    if (($style -band 0x80000) -ne 0) {
        if (-not [DotfilesDesktop.Native]::GetLayeredWindowAttributes($window, [ref]$color, [ref]$alpha, [ref]$flags)) { throw 'This application manages its own layered rendering and cannot safely have its opacity changed.' }
    }
    else { [void][DotfilesDesktop.Native]::SetWindowLong($window, -20, ($style -bor 0x80000)) }
    $nextAlpha = if ($alpha -lt 255) { [byte]255 } else { [byte]230 }
    if (-not [DotfilesDesktop.Native]::SetLayeredWindowAttributes($window, $color, $nextAlpha, ($flags -bor 2))) { throw 'Windows could not change this window opacity. Run the application without administrator elevation.' }
}

function Get-DesktopIdleEventName {
    'Local\dotfiles.keybindings.idle.' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Invoke-DesktopIdleHold {
    Initialize-DesktopNative
    $created = $false
    $event = New-Object Threading.EventWaitHandle($false, [Threading.EventResetMode]::ManualReset, (Get-DesktopIdleEventName), [ref]$created)
    if (-not $created) { $event.Dispose(); return }
    try {
        if ([DotfilesDesktop.Native]::SetThreadExecutionState([uint32]2147483651) -eq 0) { throw 'Windows rejected the keep-awake request.' }
        [void]$event.WaitOne()
    }
    finally { [void][DotfilesDesktop.Native]::SetThreadExecutionState([uint32]2147483648); $event.Dispose() }
}

function Switch-DesktopIdle {
    $mutex = New-Object Threading.Mutex($false, ((Get-DesktopIdleEventName) + '.toggle'))
    if (-not $mutex.WaitOne(5000)) { $mutex.Dispose(); throw 'Another idle toggle is still starting. Try again.' }
    try {
        try { $event = [Threading.EventWaitHandle]::OpenExisting((Get-DesktopIdleEventName)) }
        catch [Threading.WaitHandleCannotBeOpenedException] { $event = $null }
        if ($event) { try { [void]$event.Set() } finally { $event.Dispose() }; return }
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        Invoke-DesktopProcess $powershell @('-NoLogo', '-NoProfile', '-STA', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', $script:DesktopActionScriptPath, '-Action', 'idle-hold') -Hidden
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        do {
            try { $event = [Threading.EventWaitHandle]::OpenExisting((Get-DesktopIdleEventName)); $event.Dispose(); return }
            catch [Threading.WaitHandleCannotBeOpenedException] { Start-Sleep -Milliseconds 100 }
        } while ([DateTime]::UtcNow -lt $deadline)
        throw 'The keep-awake helper did not start.'
    }
    finally { $mutex.ReleaseMutex(); $mutex.Dispose() }
}

function Get-DesktopForegroundWindow {
    Initialize-DesktopNative
    [DotfilesDesktop.Native]::GetForegroundWindow()
}

function Get-DesktopClipboardSnapshot {
    Initialize-DesktopNative
    # Materialize the data before the browser replaces the OLE clipboard.
    $sourceClipboard = [Windows.Forms.Clipboard]::GetDataObject()
    $clipboard = New-Object Windows.Forms.DataObject
    if ($sourceClipboard) {
        foreach ($format in $sourceClipboard.GetFormats($false)) {
            $data = $sourceClipboard.GetData($format, $false)
            if ($data -is [ICloneable]) { $data = $data.Clone() }
            elseif ($data -is [IO.MemoryStream]) { $data = New-Object IO.MemoryStream(, $data.ToArray()) }
            if ($null -ne $data) { $clipboard.SetData($format, $false, $data) }
        }
    }
    $clipboard
}

function Get-DesktopClipboardSequence {
    Initialize-DesktopNative
    [DotfilesDesktop.Native]::GetClipboardSequenceNumber()
}

function Get-DesktopClipboardText {
    Initialize-DesktopNative
    if ([Windows.Forms.Clipboard]::ContainsText()) { return [Windows.Forms.Clipboard]::GetText() }
    $null
}

function Restore-DesktopClipboardSnapshot {
    param([AllowNull()][object]$Snapshot)
    Initialize-DesktopNative
    if ($Snapshot) { [Windows.Forms.Clipboard]::SetDataObject($Snapshot, $true) } else { [Windows.Forms.Clipboard]::Clear() }
}

function Write-DesktopBrowserBookmark {
    param([Parameter(Mandatory = $true)][Uri]$Url)
    $directory = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Bookmarks'
    [void][IO.Directory]::CreateDirectory($directory)
    $entry = [pscustomobject]@{ savedAt = [DateTime]::UtcNow.ToString('o'); url = $Url.AbsoluteUri }
    [IO.File]::AppendAllText((Join-Path $directory 'saved-urls.jsonl'), ($entry | ConvertTo-Json -Compress) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}

function Save-DesktopBrowserUrl {
    $window = Get-DesktopForegroundWindow
    if (-not (Test-DesktopBrowserWindow -Window $window)) { throw 'Focus WSL Chrome or a supported native web browser before saving its URL.' }
    $clipboard = Get-DesktopClipboardSnapshot
    $sequence = Get-DesktopClipboardSequence
    $writtenSequence = $null
    try {
        Send-DesktopChord @(17, 76) -ExpectedWindow $window
        Send-DesktopChord @(17, 67) -ExpectedWindow $window
        $deadline = [DateTime]::UtcNow.AddSeconds(3)
        do {
            Start-Sleep -Milliseconds 50
            if ((Get-DesktopForegroundWindow) -ne $window) { throw 'Browser focus changed while saving the URL; try again.' }
            $candidateSequence = Get-DesktopClipboardSequence
            $text = Get-DesktopClipboardText
            if ($candidateSequence -ne $sequence -and $null -ne $text) { $writtenSequence = $candidateSequence; break }
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($null -eq $writtenSequence) { throw 'The browser did not copy its current URL.' }
        $url = $text.Trim()
        $uri = $null
        if (-not [Uri]::TryCreate($url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http', 'https')) { throw 'The copied address is not an HTTP or HTTPS URL.' }
        Write-DesktopBrowserBookmark -Url $uri
    }
    finally {
        try { if ((Get-DesktopForegroundWindow) -eq $window) { Send-DesktopChord @(27) -ExpectedWindow $window } }
        finally {
            # Do not overwrite clipboard data the user copied during this action.
            if ($null -ne $writtenSequence -and (Get-DesktopClipboardSequence) -eq $writtenSequence) { Restore-DesktopClipboardSnapshot -Snapshot $clipboard }
        }
    }
}

function New-DesktopScreenshotCancellation {
    Initialize-DesktopNative
    New-Object DotfilesDesktop.EscapeCancellation
}

function Get-DesktopClipboardOwnerProcessName {
    Initialize-DesktopNative
    $ownerProcess = [uint32]0
    [void][DotfilesDesktop.Native]::GetWindowThreadProcessId([DotfilesDesktop.Native]::GetClipboardOwner(), [ref]$ownerProcess)
    if ($ownerProcess -ne 0) {
        $owner = Get-Process -Id $ownerProcess -ErrorAction SilentlyContinue
        if ($owner) { return $owner.ProcessName }
    }
    $null
}

function Get-DesktopClipboardImage {
    Initialize-DesktopNative
    if ([Windows.Forms.Clipboard]::ContainsImage()) { return [Windows.Forms.Clipboard]::GetImage() }
    $null
}

function Read-DesktopScreenshotClipboard {
    param([uint32]$PreviousSequence)
    $image = $null
    $accepted = $false
    try {
        $before = Get-DesktopClipboardSequence
        if ($before -eq $PreviousSequence) { return }
        $owner = Get-DesktopClipboardOwnerProcessName
        if (-not $owner -or $owner -notmatch '^(SnippingTool|ScreenClippingHost|ScreenSketch|ShellExperienceHost)$') { return }
        $image = Get-DesktopClipboardImage
        $after = Get-DesktopClipboardSequence
        # Owner, format and image must belong to one stable clipboard update.
        if ($null -eq $image -or $after -ne $before) { return }
        $candidate = [pscustomobject]@{ Sequence = $after; Image = $image }
        $accepted = $true
        $candidate
    }
    catch [Runtime.InteropServices.ExternalException] {
        # Another app can briefly own the clipboard lock; retry this sample.
    }
    finally { if ($null -ne $image -and -not $accepted) { $image.Dispose() } }
}

function Write-DesktopScreenshotImage {
    param([Parameter(Mandatory = $true)][object]$Image)
    $directory = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Screenshots'
    [void][IO.Directory]::CreateDirectory($directory)
    $path = Join-Path $directory ('Screenshot-' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff') + '.png')
    $Image.Save($path, [Drawing.Imaging.ImageFormat]::Png)
    $path
}

function Open-DesktopScreenshotEditor {
    param([Parameter(Mandatory = $true)][string]$Path)
    # Current Paint is a packaged app. Its execution alias can exist even
    # when WindowsApps is absent from PATH and System32 has no mspaint.exe.
    $paint = Get-DesktopExecutable -Name mspaint.exe -Candidates @('%LOCALAPPDATA%\Microsoft\WindowsApps\mspaint.exe', '%WINDIR%\System32\mspaint.exe')
    if (-not $paint) { throw 'Paint is unavailable. Enable its mspaint.exe app execution alias or install it with: winget install --id 9PCFS5B6T72H --source msstore --exact' }
    Invoke-DesktopProcess -FilePath $paint -Arguments @($Path)
}

function Invoke-DesktopScreenshot {
    param([ValidateRange(0, 90)][int]$TimeoutSeconds = 90)
    $sequence = Get-DesktopClipboardSequence
    $cancellation = New-DesktopScreenshotCancellation
    try {
        Send-DesktopChord @(91, 16, 83) -Cancellation $cancellation
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        do {
            Start-Sleep -Milliseconds 100
            if ($cancellation.IsCancelled) { return }
            $candidate = Read-DesktopScreenshotClipboard -PreviousSequence $sequence
            if ($candidate) {
                try {
                    if ($cancellation.IsCancelled) { return }
                    $path = Write-DesktopScreenshotImage -Image $candidate.Image
                }
                finally { $candidate.Image.Dispose() }
                Open-DesktopScreenshotEditor -Path $path
                return
            }
        } while ([DateTime]::UtcNow -lt $deadline)
        # Cancelling the interactive capture leaves no file and is not an error.
    }
    finally { $cancellation.Dispose() }
}

function Invoke-DesktopMtaScript {
    param([Parameter(Mandatory = $true)][scriptblock]$ScriptBlock, [object[]]$Arguments = @())
    # UI Automation providers require a non-window-owning MTA client thread.
    # Clipboard actions keep the caller's STA and never enter this runspace.
    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.ApartmentState = [Threading.ApartmentState]::MTA
    $runspace.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
    $pipeline = $null
    try {
        $runspace.Open()
        $pipeline = [PowerShell]::Create()
        $pipeline.Runspace = $runspace
        [void]$pipeline.AddScript($ScriptBlock.ToString())
        foreach ($argument in $Arguments) { [void]$pipeline.AddArgument($argument) }
        $result = $pipeline.Invoke()
        if ($pipeline.HadErrors) { throw $pipeline.Streams.Error[0].Exception }
        $result
    }
    finally {
        if ($pipeline) { $pipeline.Dispose() }
        $runspace.Dispose()
    }
}

function Invoke-DesktopUiAction {
    param([Parameter(Mandatory = $true)][string]$Name)
    if ([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::MTA) {
        Invoke-DesktopMtaScript -ScriptBlock {
            param([string]$Path, [string]$ActionName)
            $ErrorActionPreference = 'Stop'
            . $Path -Action unused
            Invoke-DesktopUiAction -Name $ActionName
        } -Arguments @($script:DesktopActionScriptPath, $Name)
        return
    }
    switch ($Name) {
        'notification-dismiss' { Invoke-DesktopNotification 'dismiss' }
        'notification-dismiss-all' { Invoke-DesktopNotification 'dismiss-all' }
        'notification-toggle' { Invoke-DesktopNotification 'toggle' }
        'notification-history' { Invoke-DesktopNotification 'history' }
        'night-mode-toggle' { Switch-DesktopNightMode }
        'audio-output-cycle' { Switch-DesktopAudioOutput }
        default { throw "Unknown UI Automation desktop action: $Name" }
    }
}

function Invoke-DesktopAction {
    param([string]$Name)
    switch ($Name) {
        'terminal' { Invoke-WslDesktopTerminal }
        'browser' { Invoke-WslDesktopApplication -Executable 'google-chrome' -Arguments @('--new-window') }
        'browser-private' { Invoke-PrivateDesktopBrowser }
        'files' { Invoke-WslDesktopApplication -Executable 'nautilus' -Arguments @('--new-window') }
        'activity' { Invoke-WslDesktopTerminal 'btop' }
        'editor' { Invoke-WslDesktopTerminal 'nvim' }
        'docker' { Invoke-WslDesktopTerminal 'lazydocker' }
        'music' { Invoke-WslDesktopApplication -Executable 'spotify' }
        'passwords' { Invoke-WslDesktopApplication -Executable '1password' }
        'notes' { Invoke-WslDesktopApplication -Executable 'obsidian' }
        'ai' { Invoke-WslDesktopApplication -Executable 'google-chrome' -Arguments @('--app=https://chatgpt.com/') }
        'calendar' { Invoke-WslDesktopApplication -Executable 'google-chrome' -Arguments @('--app=https://app.hey.com/calendar/weeks/') }
        'email' { Invoke-WslDesktopApplication -Executable 'google-chrome' -Arguments @('--app=https://app.hey.com/') }
        'messenger-signal' { Invoke-WslDesktopApplication -Executable 'signal-desktop' }
        'messenger-google' { Invoke-WslDesktopApplication -Executable 'google-chrome' -Arguments @('--app=https://messages.google.com/web/') }
        'messenger-whatsapp' { Invoke-WslDesktopApplication -Executable 'google-chrome' -Arguments @('--app=https://web.whatsapp.com/') }
        'copy' { Invoke-DesktopClipboard 'copy' }
        'cut' { Invoke-DesktopClipboard 'cut' }
        'paste' { Invoke-DesktopClipboard 'paste' }
        'screenshot' { Invoke-DesktopScreenshot }
        'screenshot-clipboard' { Send-DesktopChord @(91, 16, 83) }
        'record' { Send-DesktopChord @(91, 16, 82) }
        'save-browser-url' { Save-DesktopBrowserUrl }
        'notification-dismiss' { Invoke-DesktopUiAction $Name }
        'notification-dismiss-all' { Invoke-DesktopUiAction $Name }
        'notification-toggle' { Invoke-DesktopUiAction $Name }
        'notification-history' { Invoke-DesktopUiAction $Name }
        'theme-cycle' { Switch-DesktopTheme }
        'background-cycle' { Switch-DesktopBackground }
        'transparency-toggle' { Switch-DesktopTransparency }
        'idle-toggle' { Switch-DesktopIdle }
        'idle-hold' { Invoke-DesktopIdleHold }
        'night-mode-toggle' { Invoke-DesktopUiAction $Name }
        'bar-toggle' { Switch-DesktopBar }
        'audio-output-cycle' { Invoke-DesktopUiAction $Name }
        default { throw "Unknown desktop action: $Name" }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try { Invoke-DesktopAction -Name $Action }
    catch {
        $directory = Join-Path $env:LOCALAPPDATA 'dotfiles\keybindings'
        [void][IO.Directory]::CreateDirectory($directory)
        [IO.File]::AppendAllText((Join-Path $directory 'actions.log'), ([DateTime]::Now.ToString('o') + ' ' + $Action + ': ' + $_.Exception.Message + [Environment]::NewLine))
        Add-Type -AssemblyName System.Windows.Forms
        [void][Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Desktop shortcut: ' + $Action, [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Error)
        throw
    }
}
