local terminalBundleId = "com.apple.Terminal"
local prefixPending = false
local prefixTimer = nil
local forwardingPrefix = false

local function resetPrefix()
    prefixPending = false
    if prefixTimer then
        prefixTimer:stop()
        prefixTimer = nil
    end
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
    if forwardingPrefix then
        return false
    end

    local app = hs.application.frontmostApplication()
    if not app or app:bundleID() ~= terminalBundleId then
        resetPrefix()
        return false
    end

    local key = event:getCharacters(true):lower()
    local flags = event:getFlags()
    if not prefixPending then
        if key == " " and flags.ctrl then
            prefixPending = true
            prefixTimer = hs.timer.doAfter(1, resetPrefix)
            return true
        end
        return false
    end

    if key == " " and flags.ctrl then
        resetPrefix()
        forwardingPrefix = true
        hs.eventtap.keyStroke({ "ctrl" }, "space", 0)
        hs.timer.doAfter(0, function()
            forwardingPrefix = false
        end)
        return true
    end

    local action = key == "\t" and (flags.shift and suffixActions.shift_tab or suffixActions.tab) or suffixActions[key]
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
