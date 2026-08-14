local terminalBundleId = "com.apple.Terminal"
local backTabCharacter = string.char(0x19)
local noModifiers = {}
local ctrlOnly = { ctrl = true }
local shiftOnly = { shift = true }
local prefixPending = false
local prefixTimer = nil
local prefixGeneration = 0

local function resetPrefix()
    prefixPending = false
    prefixGeneration = prefixGeneration + 1
    if prefixTimer then
        prefixTimer:stop()
        prefixTimer = nil
    end
end

local function startPrefix()
    resetPrefix()
    prefixPending = true
    local generation = prefixGeneration
    prefixTimer = hs.timer.doAfter(1, function()
        if prefixGeneration == generation then
            resetPrefix()
        end
    end)
end

local function hasExactModifiers(flags, expected)
    for modifier, enabled in pairs(flags) do
        if enabled and not expected[modifier] then
            return false
        end
    end
    for modifier, enabled in pairs(expected) do
        if enabled and not flags[modifier] then
            return false
        end
    end
    return true
end

local function send(mods, key)
    resetPrefix()
    hs.eventtap.keyStroke(mods, key, 0)
end

local suffixActions = {
    n = function()
        send({ "cmd" }, "t")
    end,
    q = function()
        send({ "cmd" }, "w")
    end,
    tab = function()
        send({ "ctrl" }, "tab")
    end,
    shift_tab = function()
        send({ "ctrl", "shift" }, "tab")
    end,
    v = function()
        send({ "cmd" }, "d")
    end,
    x = function()
        send({ "cmd", "shift" }, "d")
    end,
}

terminalPrefixTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    local app = hs.application.frontmostApplication()
    if not app or app:bundleID() ~= terminalBundleId then
        resetPrefix()
        return false
    end

    local key = event:getCharacters(true):lower()
    local flags = event:getFlags()
    if not prefixPending then
        if key == " " and hasExactModifiers(flags, ctrlOnly) then
            startPrefix()
            return true
        end
        return false
    end

    if key == " " and hasExactModifiers(flags, ctrlOnly) then
        resetPrefix()
        return true, hs.eventtap.event.newKeyEventSequence({ "ctrl" }, "space")
    end

    local action = nil
    if hasExactModifiers(flags, noModifiers) then
        action = key == "\t" and suffixActions.tab or suffixActions[key]
    elseif key == backTabCharacter and hasExactModifiers(flags, shiftOnly) then
        action = suffixActions.shift_tab
    end
    resetPrefix()
    if action then
        action()
    end
    return true
end)

hs.autoLaunch(true)
if hs.accessibilityState() then
    terminalPrefixTap:start()
else
    hs.alert.show("Hammerspoon Accessibility permission is required for Terminal keybindings")
end
