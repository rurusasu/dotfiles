local terminalBundleId = "com.apple.Terminal"
local currentBundleId = terminalBundleId
local eventCallback = nil
local callbackCount = 0
local timers = {}
local keyStrokes = {}
local keyEventSequences = {}
local tapStarted = false
local autoLaunchEnabled = nil

local function copyArray(values)
    local result = {}
    for index, value in ipairs(values) do
        result[index] = value
    end
    return result
end

hs = {
    accessibilityState = function()
        return true
    end,
    alert = {
        show = function() end,
    },
    application = {
        frontmostApplication = function()
            if not currentBundleId then
                return nil
            end
            return {
                bundleID = function()
                    return currentBundleId
                end,
            }
        end,
    },
    autoLaunch = function(enabled)
        autoLaunchEnabled = enabled
    end,
    eventtap = {
        event = {
            newKeyEventSequence = function(modifiers, key)
                local events = {
                    {
                        kind = "key-event-sequence",
                    },
                }
                table.insert(keyEventSequences, {
                    modifiers = copyArray(modifiers),
                    key = key,
                    events = events,
                })
                return events
            end,
            types = {
                keyDown = 10,
            },
        },
        keyStroke = function(modifiers, key, delay)
            table.insert(keyStrokes, {
                modifiers = copyArray(modifiers),
                key = key,
                delay = delay,
            })
        end,
        new = function(_, callback)
            eventCallback = callback
            return {
                start = function()
                    tapStarted = true
                end,
            }
        end,
    },
    timer = {
        doAfter = function(delay, callback)
            local timer = {
                callback = callback,
                delay = delay,
                stopped = false,
            }
            function timer:stop()
                self.stopped = true
            end
            table.insert(timers, timer)
            return timer
        end,
    },
}

local function makeEvent(characters, flags)
    return {
        getCharacters = function(_, clean)
            assert(clean == true, "state machine must request clean characters")
            return characters
        end,
        getFlags = function()
            return flags or {}
        end,
    }
end

local function dispatch(characters, flags)
    callbackCount = callbackCount + 1
    return eventCallback(makeEvent(characters, flags))
end

local function fail(message)
    error(message, 2)
end

local function expect(condition, message)
    if not condition then
        fail(message)
    end
end

local function expectModifiers(actual, expected, context)
    expect(#actual == #expected, context .. ": modifier count mismatch")
    for index, modifier in ipairs(expected) do
        expect(actual[index] == modifier, context .. ": modifier mismatch at " .. index)
    end
end

local function expectStroke(index, modifiers, key)
    local stroke = keyStrokes[index]
    expect(stroke ~= nil, "missing key stroke " .. index)
    expectModifiers(stroke.modifiers, modifiers, "key stroke " .. index)
    expect(stroke.key == key, "key stroke " .. index .. ": expected " .. key .. ", got " .. tostring(stroke.key))
    expect(stroke.delay == 0, "key stroke " .. index .. ": delay must be zero")
end

dofile("chezmoi/terminals/hammerspoon/init.lua")

expect(eventCallback ~= nil, "event tap callback was not registered")
expect(tapStarted, "event tap was not started with Accessibility enabled")
expect(autoLaunchEnabled == true, "auto launch was not enabled")

local function resetScenario()
    for _, timer in ipairs(timers) do
        if timer.delay == 0 and not timer.stopped then
            timer.callback()
        end
    end
    currentBundleId = "com.example.Other"
    dispatch("z", {})
    currentBundleId = terminalBundleId
    timers = {}
    keyStrokes = {}
    keyEventSequences = {}
end

local failures = 0
local function test(name, body)
    resetScenario()
    local ok, message = pcall(body)
    if ok then
        io.write("ok - ", name, "\n")
    else
        failures = failures + 1
        io.write("not ok - ", name, ": ", tostring(message), "\n")
    end
end

test("supported suffixes send exact Terminal shortcuts including back-tab 0x19", function()
    local cases = {
        { characters = "n", flags = {}, modifiers = { "cmd" }, key = "t" },
        { characters = "q", flags = {}, modifiers = { "cmd" }, key = "w" },
        { characters = "\t", flags = {}, modifiers = { "ctrl" }, key = "tab" },
        { characters = string.char(0x19), flags = { shift = true }, modifiers = { "ctrl", "shift" }, key = "tab" },
        { characters = "v", flags = {}, modifiers = { "cmd" }, key = "d" },
        { characters = "x", flags = {}, modifiers = { "cmd", "shift" }, key = "d" },
    }

    for index, case in ipairs(cases) do
        local prefixSwallowed = dispatch(" ", { ctrl = true })
        expect(prefixSwallowed == true, "prefix was not swallowed for case " .. index)
        local suffixSwallowed = dispatch(case.characters, case.flags)
        expect(suffixSwallowed == true, "suffix was not swallowed for case " .. index)
        expectStroke(index, case.modifiers, case.key)
    end
    expect(#keyStrokes == #cases, "unexpected supported-suffix key stroke count")
end)

test("prefix and suffix modifiers match exactly", function()
    local swallowed = dispatch(" ", { ctrl = true, shift = true })
    expect(swallowed == false, "Ctrl+Shift+Space must not start prefix mode")
    expect(#timers == 0, "Ctrl+Shift+Space must not create a prefix timer")

    expect(dispatch(" ", { ctrl = true }) == true, "exact Ctrl+Space must start prefix mode")
    expect(dispatch("N", { shift = true }) == true, "Shift+N must be swallowed while prefix is pending")
    expect(#keyStrokes == 0, "Shift+N must not trigger the plain n action")
    expect(dispatch("n", {}) == false, "Shift+N must reset prefix mode")

    expect(dispatch(" ", { ctrl = true }) == true, "exact Ctrl+Space must restart prefix mode")
    expect(dispatch("n", { ctrl = true }) == true, "Ctrl+N must be swallowed while prefix is pending")
    expect(#keyStrokes == 0, "Ctrl+N must not trigger the plain n action")
    expect(dispatch("n", {}) == false, "Ctrl+N must reset prefix mode")

    expect(dispatch(" ", { ctrl = true }) == true, "exact Ctrl+Space must restart prefix mode")
    local forwarded = dispatch(" ", { ctrl = true, shift = true })
    expect(forwarded == true, "Ctrl+Shift+Space must be swallowed as an unsupported suffix")
    expect(dispatch("n", {}) == false, "Ctrl+Shift+Space suffix must reset prefix mode")
end)

test("nested prefix returns exactly one non-recaptured Ctrl+Space key sequence", function()
    local callbackCountBefore = callbackCount
    local firstSwallowed, firstEvents = dispatch(" ", { ctrl = true })
    expect(firstSwallowed == true and firstEvents == nil, "first prefix must be swallowed without replacement events")

    local secondSwallowed, replacementEvents = dispatch(" ", { ctrl = true })
    expect(secondSwallowed == true, "nested prefix source event must be swallowed")
    expect(type(replacementEvents) == "table", "nested prefix must return replacement events")
    expect(#keyStrokes == 0, "nested prefix must not post a recapturable keyStroke")
    expect(callbackCount == callbackCountBefore + 2, "returned events must not re-enter the tap callback")
    expect(#keyEventSequences == 1, "nested prefix must build exactly one key event sequence")
    expectModifiers(keyEventSequences[1].modifiers, { "ctrl" }, "nested sequence")
    expect(keyEventSequences[1].key == "space", "nested sequence must contain Ctrl+Space")
    expect(replacementEvents == keyEventSequences[1].events, "callback must return the unposted key event sequence")

    expect(dispatch("n", {}) == false, "nested forwarding must leave prefix mode reset")
end)

test("unsupported suffix and Escape are swallowed and reset prefix mode", function()
    for _, characters in ipairs({ "w", string.char(0x1b) }) do
        expect(dispatch(" ", { ctrl = true }) == true, "prefix must start")
        local swallowed, replacementEvents = dispatch(characters, {})
        expect(swallowed == true, "unsupported suffix must be swallowed")
        expect(replacementEvents == nil, "unsupported suffix must not return events")
        expect(#keyStrokes == 0, "unsupported suffix must not send a shortcut")
        expect(dispatch("n", {}) == false, "unsupported suffix must reset prefix mode")
    end
end)

test("timeout generation ignores stale callbacks and expires the active prefix", function()
    expect(dispatch(" ", { ctrl = true }) == true, "first prefix must start")
    local staleTimer = timers[#timers]
    expect(staleTimer.delay == 1, "prefix timeout must be one second")
    expect(dispatch("w", {}) == true, "unsupported suffix must cancel first prefix")
    expect(staleTimer.stopped, "cancelled prefix timer must be stopped")

    expect(dispatch(" ", { ctrl = true }) == true, "second prefix must start")
    staleTimer.callback()
    expect(dispatch("n", {}) == true, "stale timeout must not cancel the newer prefix")
    expectStroke(1, { "cmd" }, "t")

    keyStrokes = {}
    expect(dispatch(" ", { ctrl = true }) == true, "third prefix must start")
    local activeTimer = timers[#timers]
    activeTimer.callback()
    expect(dispatch("n", {}) == false, "active timeout must expire prefix mode")
    expect(#keyStrokes == 0, "expired prefix must not run suffix action")
end)

test("switching away from Terminal resets prefix and passes the new app event", function()
    expect(dispatch(" ", { ctrl = true }) == true, "prefix must start in Terminal")
    currentBundleId = "com.example.Other"
    expect(dispatch("n", {}) == false, "event in another app must pass through")
    currentBundleId = terminalBundleId
    expect(dispatch("n", {}) == false, "app switch must reset Terminal prefix state")
    expect(#keyStrokes == 0, "app switch must not send a Terminal shortcut")
end)

if failures > 0 then
    io.write(failures, " behavioral test(s) failed\n")
    os.exit(1)
end

io.write("all Hammerspoon Terminal prefix behavioral tests passed\n")
