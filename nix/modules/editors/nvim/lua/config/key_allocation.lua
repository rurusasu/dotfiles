local allocation = require("config.shared_keybindings")
local M = {}

function M.binding(action, scope)
    for _, binding in ipairs(allocation.bindings) do
        if binding.action == action and binding.scope == (scope or "editor") then
            return binding
        end
    end
    error("Missing shared Neovim key allocation: " .. action)
end

function M.key(action, scope)
    return M.binding(action, scope).key
end

return M
