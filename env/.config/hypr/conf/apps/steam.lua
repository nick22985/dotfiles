-- Steam. Converted from conf/apps/steam.conf.

hl.window_rule({ match = { class = "steam" }, float = true, opacity = "1 1", idle_inhibit = "fullscreen" })
hl.window_rule({ match = { class = "steam", title = "Steam" }, center = true, size = { 1100, 700 } })
hl.window_rule({ match = { class = "steam", title = "Friends List" }, size = { 460, 800 } })
