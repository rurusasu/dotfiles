// A per-user Win32 input adapter. UI Automation runs off the keyboard hook
// thread.
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading;
using System.Windows.Automation;
using System.Windows.Forms;

internal static class WslSuperKey {
  private static readonly string InstanceName =
      @"Local\Dotfiles.WslSuperKey." + InstanceId();
  private static readonly string StopName = InstanceName + ".Stop";
  private const string TerminalTitle = "[dotfiles:WSL]";
  private static readonly UIntPtr OwnInput = new UIntPtr(0x4457534B);
  private static readonly bool[] Down = new bool[256];
  private static readonly bool[] Consumed = new bool[256];
  private static readonly AutoResetEvent Query = new AutoResetEvent(false);
  private static readonly AutoResetEvent Answer = new AutoResetEvent(false);
  private static readonly HookProc Callback = OnKey;
  private static int request, response;
  private static IntPtr target, inspectedWindow, chordWindow, hook;
  private static bool focusKnown;
  private static Exception failure;
  private static int reset;

  private static string InstanceId() {
    using (SHA256 hash = SHA256.Create()) return BitConverter
        .ToString(hash.ComputeHash(System.Text.Encoding.UTF8.GetBytes(
            Path.GetFullPath(Application.ExecutablePath).ToUpperInvariant())))
        .Replace("-", "");
  }

  [STAThread]
  private static void Main(string[] args) {
    if (args.Length == 1 && args[0] == "--stop") {
      try {
        using (EventWaitHandle stop = EventWaitHandle.OpenExisting(StopName))
            stop.Set();
      } catch (WaitHandleCannotBeOpenedException) {
      }
      return;
    }
    try {
      bool created;
      using (Mutex single = new Mutex(true, InstanceName, out created)) {
        if (!created)
          return;
        using (EventWaitHandle stop = new EventWaitHandle(
                   false, EventResetMode.ManualReset,
                   StopName)) using (System.Windows.Forms.Timer timer =
                                         new System.Windows.Forms.Timer()) {
          for (int vk = 0; vk < Down.Length; vk++)
            Down[vk] = GetAsyncKeyState(vk) < 0;
          Thread worker = new Thread(InspectFocus);
          worker.IsBackground = true;
          worker.SetApartmentState(ApartmentState.MTA);
          worker.Start();
          Query.Set();
          Answer.WaitOne(2000);
          Answer.Reset();
          hook = SetWindowsHookEx(13, Callback, GetModuleHandle(null), 0);
          if (hook == IntPtr.Zero)
            throw new Win32Exception();
          timer.Interval = 100;
          Microsoft.Win32.SystemEvents.SessionSwitch += OnSessionSwitch;
          timer.Tick += delegate {
            if (Interlocked.Exchange(ref reset, 0) != 0) {
              Array.Clear(Down, 0, Down.Length);
              Array.Clear(Consumed, 0, Consumed.Length);
              chordWindow = IntPtr.Zero;
            }
            if (stop.WaitOne(0) || failure != null)
              Application.ExitThread();
          };
          timer.Start();
          try {
            Application.Run();
          } finally {
            UnhookWindowsHookEx(hook);
            Microsoft.Win32.SystemEvents.SessionSwitch -= OnSessionSwitch;
          }
          if (failure != null)
            throw failure;
        }
      }
    } catch (Exception error) {
      File.WriteAllText(
          Path.ChangeExtension(Application.ExecutablePath, ".log"),
          error.ToString());
      Environment.ExitCode = 1;
    }
  }

  private static void
  OnSessionSwitch(object sender, Microsoft.Win32.SessionSwitchEventArgs args) {
    Interlocked.Exchange(ref reset, 1);
  }

  private static void InspectFocus() {
    // Warm up UIA before installing the hook, including outside Terminal.
    try {
      AutomationElement focused = AutomationElement.FocusedElement;
      if (focused != null)
        focused.GetRuntimeId();
    } catch (Exception) {
    }
    while (true) {
      Query.WaitOne();
      int current = Volatile.Read(ref request);
      IntPtr found = IntPtr.Zero;
      IntPtr window = GetForegroundWindow();
      bool known = false;
      try {
        uint pid;
        GetWindowThreadProcessId(window, out pid);
        using (Process process = Process.GetProcessById((int)pid)) {
          if (process.ProcessName == "WindowsTerminal" &&
              !IsElevated(process)) {
            AutomationElement focused = AutomationElement.FocusedElement;
            known = focused != null && focused.Current.ProcessId == (int)pid;
            if (focused != null && focused.Current.ProcessId == (int)pid &&
                focused.Current.ClassName == "TermControl" &&
                focused.Current.Name == TerminalTitle &&
                GetForegroundWindow() == window)
              found = window;
          } else {
            known = true;
          }
        }
      }
      // Closed windows, inaccessible UIA providers and elevation fail open.
      catch (Exception) {
        known = false;
      }
      target = found;
      inspectedWindow = window;
      focusKnown = known;
      Volatile.Write(ref response, current);
      Answer.Set();
    }
  }

  private static IntPtr QueryTarget() {
    bool known;
    return QueryTarget(out known);
  }

  private static IntPtr QueryTarget(out bool known) {
    known = false;
    Answer.Reset();
    int current = Interlocked.Increment(ref request);
    Query.Set();
    // A stalled UIA provider must never stall or uninstall the low-level hook.
    if (!Answer.WaitOne(25) || Volatile.Read(ref response) != current)
      return IntPtr.Zero;
    if (GetForegroundWindow() != inspectedWindow)
      return IntPtr.Zero;
    known = focusKnown;
    return target;
  }

  private static IntPtr OnKey(int code, IntPtr message, IntPtr data) {
    if (code < 0)
      return CallNextHookEx(hook, code, message, data);
    Keyboard key = (Keyboard)Marshal.PtrToStructure(data, typeof(Keyboard));
    if (key.extra == OwnInput || key.vk >= Down.Length)
      return CallNextHookEx(hook, code, message, data);
    int vk = (int)key.vk;
    bool up = (key.flags & 0x80) != 0;
    bool winWasDown = Down[0x5B] || Down[0x5C];
    bool wasDown = Down[vk];
    Down[vk] = !up;
    if (up && Consumed[vk]) {
      Consumed[vk] = false;
      if (!Down[0x5B] && !Down[0x5C])
        chordWindow = IntPtr.Zero;
      return new IntPtr(1);
    }
    IntPtr focused = IntPtr.Zero;
    if (!up && chordWindow != IntPtr.Zero) {
      bool known;
      focused = QueryTarget(out known);
      // A timeout in the same window is not evidence that focus left WSL.
      if (!Consumed[vk] && !wasDown &&
          (GetForegroundWindow() != chordWindow ||
           (known && focused != chordWindow))) {
        if (focused != IntPtr.Zero) {
          chordWindow = focused;
        } else {
          chordWindow = IntPtr.Zero;
          return RestoreWindowsInput(key)
                     ? new IntPtr(1)
                     : CallNextHookEx(hook, code, message, data);
        }
      }
    }
    if (!up && (vk == 0x5B || vk == 0x5C)) {
      if (chordWindow == IntPtr.Zero && !winWasDown)
        chordWindow = QueryTarget();
      if (chordWindow != IntPtr.Zero) {
        Consumed[vk] = true;
        return new IntPtr(1);
      }
    }
    // Pair releases even when Win was released first or focus moved away.
    if (!up && (Consumed[vk] ||
                (chordWindow != IntPtr.Zero && !IsModifier(vk) && !wasDown))) {
      Consumed[vk] = true;
      if (chordWindow != IntPtr.Zero && focused == chordWindow) {
        try {
          string sequence = Encode(vk);
          if (sequence != null)
            SendText(sequence);
        } catch (Exception error) {
          failure = error;
        }
      }
      return new IntPtr(1);
    }
    return CallNextHookEx(hook, code, message, data);
  }

  private static bool RestoreWindowsInput(Keyboard key) {
    List<Input> inputs = new List<Input>();
    List<int> held = new List<int>();
    for (int vk = 0x5B; vk <= 0x5C; vk++)
      if (Down[vk] && Consumed[vk]) {
        held.Add(vk);
        inputs.Add(KeyInput(vk, false));
      }
    Input fresh = KeyInput((int)key.vk, false);
    fresh.key.scan = (ushort)key.scan;
    fresh.key.flags = key.flags & 1;
    if (key.vk == 0xE7) {
      fresh.key.vk = 0;
      fresh.key.flags = 4;
    }
    inputs.Add(fresh);
    // Restore swallowed Win downs before the fresh key in one ordered batch.
    uint sent = SendInput((uint)inputs.Count, inputs.ToArray(),
                          Marshal.SizeOf(typeof(Input)));
    for (int i = 0; i < held.Count && i < sent; i++)
      Consumed[held[i]] = false;
    // UIPI may reject injection into elevated apps. Let the original key pass.
    return sent == inputs.Count;
  }

  private static bool IsModifier(int vk) {
    return vk == 0x10 || vk == 0x11 || vk == 0x12 || (vk >= 0xA0 && vk <= 0xA5);
  }

  private static string Encode(int vk) {
    int modifiers = 9 + ((Down[0xA0] || Down[0xA1]) ? 1 : 0) +
                    ((Down[0xA4] || Down[0xA5]) ? 2 : 0) +
                    ((Down[0xA2] || Down[0xA3]) ? 4 : 0);
    string suffix = null;
    switch (vk) {
    case 0x25:
      suffix = "D";
      break;
    case 0x26:
      suffix = "A";
      break;
    case 0x27:
      suffix = "C";
      break;
    case 0x28:
      suffix = "B";
      break;
    case 0x24:
      suffix = "H";
      break;
    case 0x23:
      suffix = "F";
      break;
    }
    if (suffix != null)
      return "\x1b[1;" + modifiers + suffix;
    int tilde = 0;
    switch (vk) {
    case 0x2D:
      tilde = 2;
      break;
    case 0x2E:
      tilde = 3;
      break;
    case 0x21:
      tilde = 5;
      break;
    case 0x22:
      tilde = 6;
      break;
    }
    if (tilde != 0)
      return "\x1b[" + tilde + ";" + modifiers + "~";
    int character;
    if (vk >= 0x41 && vk <= 0x5A)
      character = vk + 32;
    else if (vk == 8)
      character = 127;
    else if (vk == 9 || vk == 13 || vk == 27 || vk == 32)
      character = vk;
    else {
      uint pid;
      uint thread = GetWindowThreadProcessId(chordWindow, out pid);
      character = (int)MapVirtualKeyEx((uint)vk, 2, GetKeyboardLayout(thread));
    }
    // Media keys, dead keys and unknown keys are consumed rather than becoming
    // unmodified input.
    if (character < 32 && character != 9 && character != 13 && character != 27)
      return null;
    if (character > 0xFFFF)
      return null;
    return "\x1b[" + character + ";" + modifiers + "u";
  }

  private static void SendText(string text) {
    List<Input> inputs = new List<Input>();
    List<int> held = new List<int>();
    for (int vk = 0xA0; vk <= 0xA5; vk++)
      if (GetAsyncKeyState(vk) < 0) {
        held.Add(vk);
        inputs.Add(KeyInput(vk, true));
      }
    foreach (char c in text) {
      Input input = new Input();
      input.type = 1;
      input.key.scan = c;
      input.key.flags = 4;
      input.key.extra = OwnInput;
      inputs.Add(input);
      input.key.flags |= 2;
      inputs.Add(input);
    }
    foreach (int vk in held)
      inputs.Add(KeyInput(vk, false));
    Input[] batch = inputs.ToArray();
    if (GetForegroundWindow() != chordWindow)
      return;
    if (SendInput((uint)batch.Length, batch, Marshal.SizeOf(typeof(Input))) !=
        batch.Length)
      throw new Win32Exception(
          Marshal.GetLastWin32Error(),
          "Could not forward Super input to Windows Terminal.");
  }

  private static Input KeyInput(int vk, bool up) {
    Input input = new Input();
    input.type = 1;
    input.key.vk = (ushort)vk;
    input.key.flags =
        (up ? 2u : 0u) |
        (vk == 0xA3 || vk == 0xA5 || vk == 0x5B || vk == 0x5C ? 1u : 0u);
    input.key.extra = OwnInput;
    return input;
  }

  private static bool IsElevated(Process process) {
    IntPtr token;
    if (!OpenProcessToken(process.Handle, 8, out token))
      return true;
    try {
      int elevated, size;
      return !GetTokenInformation(token, 20, out elevated, 4, out size) ||
             elevated != 0;
    } finally {
      CloseHandle(token);
    }
  }

  [StructLayout(LayoutKind.Sequential)]
  private struct Keyboard {
    public uint vk, scan, flags, time;
    public UIntPtr extra;
  }
  [StructLayout(LayoutKind.Sequential)]
  private struct Key {
    public ushort vk, scan;
    public uint flags, time;
    public UIntPtr extra;
  }
  [StructLayout(LayoutKind.Explicit)]
  private struct Input {
    [FieldOffset(0)]
    public uint type;
    [FieldOffset(8)]
    public Key key;
    // INPUT's native union includes a 32-byte MOUSEINPUT on Windows x64.
    [FieldOffset(32)]
    private long padding;
  }
  private delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);
  [DllImport("user32.dll", SetLastError = true)]
  private static extern IntPtr SetWindowsHookEx(int kind, HookProc callback,
                                                IntPtr module, uint thread);
  [DllImport("user32.dll")]
  private static extern bool UnhookWindowsHookEx(IntPtr handle);
  [DllImport("user32.dll")]
  private static extern IntPtr CallNextHookEx(IntPtr handle, int code,
                                              IntPtr message, IntPtr data);
  [DllImport("user32.dll")]
  private static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")]
  private static extern uint GetWindowThreadProcessId(IntPtr window,
                                                      out uint pid);
  [DllImport("user32.dll")]
  private static extern short GetAsyncKeyState(int key);
  [DllImport("user32.dll")]
  private static extern uint MapVirtualKeyEx(uint key, uint kind,
                                             IntPtr layout);
  [DllImport("user32.dll")]
  private static extern IntPtr GetKeyboardLayout(uint thread);
  [DllImport("user32.dll", SetLastError = true)]
  private static extern uint SendInput(uint count, Input[] inputs, int size);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
  private static extern IntPtr GetModuleHandle(string module);
  [DllImport("advapi32.dll", SetLastError = true)]
  private static extern bool OpenProcessToken(IntPtr process, uint access,
                                              out IntPtr token);
  [DllImport("advapi32.dll", SetLastError = true)]
  private static extern bool GetTokenInformation(IntPtr token, int kind,
                                                 out int info, int length,
                                                 out int size);
  [DllImport("kernel32.dll")]
  private static extern bool CloseHandle(IntPtr handle);
}
