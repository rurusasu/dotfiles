local wezterm = require("wezterm")

return {
  color_scheme = "Gruvbox Dark",
  font = wezterm.font("Source Han Code JP"),
  font_size = 12.0,
  enable_tab_bar = true,
  hide_tab_bar_if_only_one_tab = true,
  use_fancy_tab_bar = false,
  window_decorations = "RESIZE",
  window_padding = {
    left = 8,
    right = 8,
    top = 6,
    bottom = 6,
  },
}
