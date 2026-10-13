-- Obsidian. Converted from conf/apps/obsidian.conf.

local vars = require("conf.env")

hl.workspace_rule({
	workspace = "special:obsidian",
	monitor = "desc:Samsung Electric Company Odyssey G95NC HNTX400116",
	gaps_out = { top = 0, right = 1900, bottom = 0, left = 1900 },
})

hl.window_rule({
	name = "obsidian",
	match = { class = "^(obsidian)$" },
	workspace = "special:obsidian silent",
})

hl.bind(vars.mainMod .. " + O", hl.dsp.exec_cmd("~/.config/hypr/scripts/obsidian-workspace.sh"))
