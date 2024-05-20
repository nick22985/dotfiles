local wezterm = require("wezterm")

local config = {}

config.set_environment_variables = {}

if wezterm.target_triple == "x86_64-pc-windows-msvc" then
	config.default_prog = { "" }
	-- Use OSC 7 as per the above example
	config.set_environment_variables["prompt"] = "$E]7;file://localhost/$P$E\\$E[32m$T$E[0m $E[35m$P$E[36m$_$G$E[0m "
	-- use a more ls-like output format for dir
	config.set_environment_variables["DIRCMD"] = "/d"
	-- And inject clink into the command prompt
	config.default_prog = { "cmd.exe", "/s", "/k", "c:/clink/clink_x64.exe", "inject", "-q" }
end

if wezterm.config_builder then
	config = wezterm.config_builder()
end

config.window_padding = {
	left = 0,
	right = 0,
	top = 0,
	bottom = 0,
}

config.window_close_confirmation = "NeverPrompt"

-- config.window_decorations = "NONE"

config.color_scheme = "Rosé Pine (Gogh)"

config.audible_bell = "Disabled"

-- config.font = wezterm.font 'DroidSansMono Nerd Font'
-- "DroidSansMono Nerd Font", "MesloLGS Nerd Font", "Monaco", "Noto Color Emoji", "Consolas", "monospace"

return config
