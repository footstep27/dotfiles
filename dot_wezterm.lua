local wezterm = require("wezterm")

local config = wezterm.config_builder()
config.font = wezterm.font("Maple Mono NF")
config.font_size = 14
config.enable_tab_bar = false
config.window_decorations = "RESIZE"
config.color_scheme_dirs = { '~/.wezterm-themes' }
config.color_scheme = "Catppuccin Macchiato"
config.window_background_opacity = 1.0
config.macos_window_background_blur = 0
return config
