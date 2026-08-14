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

if A_Args.Length > 0 {
    if A_Args[1] = "--check"
        ExitApp 0
    if A_Args[1] = "--self-test" {
        RunTerminalSelfTests()
        ExitApp 0
    }
}

IsExactTerminalPrefix() {
    return !GetKeyState("Shift", "P")
        && !GetKeyState("Alt", "P")
        && !GetKeyState("LWin", "P")
        && !GetKeyState("RWin", "P")
}

StartTerminalPrefix() {
    global TerminalInputHook, TerminalPrefixPending

    if TerminalPrefixPending {
        ForwardNestedTerminalPrefix(TerminalInputHook, SendTerminalOutput)
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

ForwardNestedTerminalPrefix(input, sendOutput) {
    global TerminalInputHook, TerminalPrefixPending

    input.Stop()
    TerminalPrefixPending := false
    if IsObject(TerminalInputHook) && TerminalInputHook == input
        TerminalInputHook := ""
    sendOutput.Call("{Ctrl down}{Space}{Ctrl up}")
}

HandleTerminalSuffix(input, vk, sc) {
    key := StrLower(GetKeyName(Format("vk{:x}sc{:x}", vk, sc)))
    if IsTerminalModifierKey(key)
        return

    ProcessTerminalSuffix(
        input,
        key,
        WinActive("ahk_exe WindowsTerminal.exe"),
        GetTerminalModifierState(),
        Format("{{Blind}}{{vk{:x}sc{:x}}}", vk, sc),
        SendTerminalOutput
    )
}

ProcessTerminalSuffix(input, key, terminalActive, modifiers, rawKey, sendOutput) {
    global TerminalInputHook, TerminalPrefixPending

    TerminalPrefixPending := false
    input.Stop()
    if IsObject(TerminalInputHook) && TerminalInputHook == input
        TerminalInputHook := ""

    if !terminalActive {
        sendOutput.Call(rawKey)
        return
    }

    action := ResolveTerminalSuffixForState(key, modifiers)
    if action != ""
        sendOutput.Call(action)
}

ResolveTerminalSuffixForState(key, modifiers) {
    global TerminalSuffixActions

    if modifiers.Ctrl || modifiers.Alt || modifiers.LWin || modifiers.RWin
        return ""
    if modifiers.Shift && key != "tab"
        return ""

    signature := modifiers.Shift ? "shift" : ""
    return TerminalSuffixActions.Get(key "|" signature, "")
}

GetTerminalModifierState() {
    return {
        Ctrl: GetKeyState("Ctrl", "P"),
        Alt: GetKeyState("Alt", "P"),
        Shift: GetKeyState("Shift", "P"),
        LWin: GetKeyState("LWin", "P"),
        RWin: GetKeyState("RWin", "P")
    }
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

SendTerminalOutput(output) {
    SendEvent output
}

RunTerminalSelfTests() {
    try {
        RunTerminalResolverSelfTests()
        RunTerminalStateSelfTests()
        FileAppend("Terminal self-tests: PASS`n", "*")
    } catch as error {
        FileAppend("Terminal self-tests: FAIL: " error.Message "`n", "**")
        ExitApp 1
    }
}

RunTerminalResolverSelfTests() {
    cases := [
        {Key: "n", Modifiers: TerminalSelfTestModifiers(), Expected: "{F13}"},
        {Key: "q", Modifiers: TerminalSelfTestModifiers(), Expected: "{F14}"},
        {Key: "tab", Modifiers: TerminalSelfTestModifiers(), Expected: "{F15}"},
        {Key: "tab", Modifiers: TerminalSelfTestModifiers(, , true), Expected: "{F16}"},
        {Key: "h", Modifiers: TerminalSelfTestModifiers(), Expected: "{F17}"},
        {Key: "j", Modifiers: TerminalSelfTestModifiers(), Expected: "{F18}"},
        {Key: "k", Modifiers: TerminalSelfTestModifiers(), Expected: "{F19}"},
        {Key: "l", Modifiers: TerminalSelfTestModifiers(), Expected: "{F20}"},
        {Key: "v", Modifiers: TerminalSelfTestModifiers(), Expected: "{F21}"},
        {Key: "-", Modifiers: TerminalSelfTestModifiers(), Expected: "{F22}"},
        {Key: "x", Modifiers: TerminalSelfTestModifiers(), Expected: "{F23}"},
        {Key: "w", Modifiers: TerminalSelfTestModifiers(), Expected: ""},
        {Key: "a", Modifiers: TerminalSelfTestModifiers(), Expected: ""},
        {Key: "g", Modifiers: TerminalSelfTestModifiers(), Expected: ""},
        {Key: "d", Modifiers: TerminalSelfTestModifiers(), Expected: ""},
        {Key: "escape", Modifiers: TerminalSelfTestModifiers(), Expected: ""},
        {Key: "unknown", Modifiers: TerminalSelfTestModifiers(), Expected: ""},
        {Key: "n", Modifiers: TerminalSelfTestModifiers(, , true), Expected: ""},
        {Key: "n", Modifiers: TerminalSelfTestModifiers(true), Expected: ""},
        {Key: "tab", Modifiers: TerminalSelfTestModifiers(true), Expected: ""},
        {Key: "tab", Modifiers: TerminalSelfTestModifiers(, true, true), Expected: ""}
    ]

    for testCase in cases {
        actual := ResolveTerminalSuffixForState(testCase.Key, testCase.Modifiers)
        TerminalSelfTestEqual(actual, testCase.Expected, "resolver " testCase.Key)
    }
}

RunTerminalStateSelfTests() {
    global TerminalInputHook, TerminalPrefixPending

    activeInput := TerminalSelfTestInput()
    otherInput := TerminalSelfTestInput()
    TerminalInputHook := activeInput
    TerminalPrefixPending := true
    HandleTerminalPrefixEnd(otherInput)
    TerminalSelfTestTrue(TerminalPrefixPending, "unrelated InputHook end changed pending state")
    TerminalSelfTestTrue(TerminalInputHook == activeInput, "unrelated InputHook end cleared active identity")
    HandleTerminalPrefixEnd(activeInput)
    TerminalSelfTestTrue(!TerminalPrefixPending, "active InputHook end did not clear pending state")
    TerminalSelfTestEqual(TerminalInputHook, "", "active InputHook end did not clear identity")

    collector := TerminalSelfTestCollector()
    focusInput := TerminalSelfTestInput()
    rawKey := "{Blind}{vk4esc032}"
    TerminalInputHook := focusInput
    TerminalPrefixPending := true
    ProcessTerminalSuffix(
        focusInput,
        "n",
        false,
        TerminalSelfTestModifiers(),
        rawKey,
        collector
    )
    TerminalSelfTestEqual(focusInput.StopCount, 1, "focus change did not stop InputHook once")
    TerminalSelfTestEqual(collector.Values.Length, 1, "focus change did not forward exactly once")
    TerminalSelfTestEqual(collector.Values[1], rawKey, "focus change forwarded transport instead of raw key")
    TerminalSelfTestTrue(!TerminalPrefixPending, "focus change did not clear pending state")
    TerminalSelfTestEqual(TerminalInputHook, "", "focus change did not clear InputHook identity")

    collector := TerminalSelfTestCollector()
    unsupportedInput := TerminalSelfTestInput()
    TerminalInputHook := unsupportedInput
    TerminalPrefixPending := true
    ProcessTerminalSuffix(
        unsupportedInput,
        "w",
        true,
        TerminalSelfTestModifiers(),
        "",
        collector
    )
    TerminalSelfTestEqual(unsupportedInput.StopCount, 1, "unsupported suffix did not stop InputHook")
    TerminalSelfTestEqual(collector.Values.Length, 0, "unsupported suffix emitted output")

    collector := TerminalSelfTestCollector()
    nestedInput := TerminalSelfTestInput()
    TerminalInputHook := nestedInput
    TerminalPrefixPending := true
    ForwardNestedTerminalPrefix(nestedInput, collector)
    TerminalSelfTestEqual(nestedInput.StopCount, 1, "nested prefix did not stop InputHook once")
    TerminalSelfTestEqual(collector.Values.Length, 1, "nested prefix did not forward exactly once")
    TerminalSelfTestEqual(collector.Values[1], "{Ctrl down}{Space}{Ctrl up}", "nested prefix forwarded wrong key")
    TerminalSelfTestTrue(!TerminalPrefixPending, "nested prefix did not clear pending state")
    TerminalSelfTestEqual(TerminalInputHook, "", "nested prefix did not clear InputHook identity")
}

TerminalSelfTestModifiers(ctrl := false, alt := false, shift := false, lwin := false, rwin := false) {
    return {Ctrl: ctrl, Alt: alt, Shift: shift, LWin: lwin, RWin: rwin}
}

TerminalSelfTestEqual(actual, expected, message) {
    if actual != expected
        throw Error(message ": expected '" expected "', got '" actual "'")
}

TerminalSelfTestTrue(condition, message) {
    if !condition
        throw Error(message)
}

class TerminalSelfTestInput {
    StopCount := 0

    Stop() {
        this.StopCount += 1
    }
}

class TerminalSelfTestCollector {
    Values := []

    Call(value) {
        this.Values.Push(value)
    }
}

#HotIf WinActive("ahk_exe WindowsTerminal.exe") && IsExactTerminalPrefix()
$^Space::StartTerminalPrefix()
#HotIf
