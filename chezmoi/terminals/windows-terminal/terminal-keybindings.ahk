#Requires AutoHotkey v2.0
#SingleInstance Force

global TerminalInputHook := ""
global TerminalPrefixPending := false
global TerminalSuffixActions := Map(
    "n|", "{F13}",
    "q|", "{F14}",
    "tab|", "{F15}",
    "tab|shift", "{F16}",
    "h|", "{F17}",
    "j|", "{F18}",
    "k|", "{F19}",
    "l|", "{F20}",
    "v|", "{F21}",
    "-|", "{F22}",
    "x|", "{F23}"
)

if A_Args.Length > 0 && A_Args[1] = "--check"
    ExitApp 0

IsExactTerminalPrefix() {
    return !GetKeyState("Shift", "P")
        && !GetKeyState("Alt", "P")
        && !GetKeyState("LWin", "P")
        && !GetKeyState("RWin", "P")
}

StartTerminalPrefix() {
    global TerminalInputHook, TerminalPrefixPending

    if TerminalPrefixPending {
        TerminalInputHook.Stop()
        TerminalPrefixPending := false
        TerminalInputHook := ""
        SendEvent "{Ctrl down}{Space}{Ctrl up}"
        return
    }

    if IsObject(TerminalInputHook)
        TerminalInputHook.Stop()

    TerminalPrefixPending := true
    TerminalInputHook := InputHook("T1")
    TerminalInputHook.KeyOpt("{All}", "NS")
    TerminalInputHook.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-S")
    TerminalInputHook.OnKeyDown := HandleTerminalSuffix
    TerminalInputHook.OnEnd := HandleTerminalPrefixEnd
    TerminalInputHook.Start()
}

HandleTerminalSuffix(input, vk, sc) {
    global TerminalInputHook, TerminalPrefixPending

    key := StrLower(GetKeyName(Format("vk{:x}sc{:x}", vk, sc)))
    if IsTerminalModifierKey(key)
        return

    if !WinActive("ahk_exe WindowsTerminal.exe") {
        TerminalPrefixPending := false
        input.Stop()
        if TerminalInputHook == input
            TerminalInputHook := ""
        SendEvent(Format("{{Blind}}{{vk{:x}sc{:x}}}", vk, sc))
        return
    }

    action := ResolveTerminalSuffix(key)
    TerminalPrefixPending := false
    input.Stop()
    if TerminalInputHook == input
        TerminalInputHook := ""

    if action != ""
        SendEvent action
}

ResolveTerminalSuffix(key) {
    global TerminalSuffixActions

    if GetKeyState("Ctrl", "P")
        || GetKeyState("Alt", "P")
        || GetKeyState("LWin", "P")
        || GetKeyState("RWin", "P")
        return ""

    shifted := GetKeyState("Shift", "P")
    if shifted && key != "tab"
        return ""

    signature := shifted ? "shift" : ""
    return TerminalSuffixActions.Get(key "|" signature, "")
}

IsTerminalModifierKey(key) {
    return RegExMatch(key, "i)^(?:l|r)?(?:shift|control|alt|win)$")
}

HandleTerminalPrefixEnd(input) {
    global TerminalInputHook, TerminalPrefixPending

    if IsObject(TerminalInputHook) && TerminalInputHook == input {
        TerminalPrefixPending := false
        TerminalInputHook := ""
    }
}

#HotIf WinActive("ahk_exe WindowsTerminal.exe") && IsExactTerminalPrefix()
$^Space::StartTerminalPrefix()
#HotIf
