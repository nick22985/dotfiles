-- Gamer special workspace. Converted from conf/special/games.conf.

-- Toggle gamer special workspace
hl.bind("SUPER + G", hl.dsp.workspace.toggle_special("game"))
hl.bind("SUPER + SHIFT + G", hl.dsp.window.move({ workspace = "special:game" }))

-- Special workspace settings
hl.workspace_rule({ workspace = "special:game", gaps_in = 0, gaps_out = 0, no_border = true })
hl.workspace_rule({
	workspace = "special:game",
	monitor = "desc:Samsung Electric Company Odyssey G95NC HNTX400116",
	gaps_out = { top = 0, right = 1900, bottom = 0, left = 1900 },
	gaps_in = 0,
})

hl.window_rule({
	name = "game_steam",
	match = { class = "^(?i)steam_app_.*" },
	workspace = "special:game silent",
	no_initial_focus = true,
})
