-- Obsidian. Converted from conf/apps/obsidian.conf.

local vars = require("conf.env")

hl.window_rule({
	name = "obsidian",
	match = { class = "^(obsidian)$" },
	workspace = "special:obsidian silent",
})

hl.bind(vars.mainMod .. " + O", hl.dsp.exec_cmd("~/.config/hypr/scripts/obsidian-workspace.sh"))
