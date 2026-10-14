local binding = require("config.key_allocation").binding("which-key")
require("which-key").setup({
    triggers = {
        { "<auto>", mode = "nixsotc" },
        { binding.key, mode = binding.mode },
    },
})
