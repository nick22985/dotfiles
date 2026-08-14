-- LabyMod freeze fix. Converted from conf/apps/labymod.conf.

hl.window_rule({
    name             = "labymodfreezefix",
    match            = { title = [[^Minecraft .* \| LabyMod .*$]] },
    render_unfocused = true,
    workspace        = "special:game silent",
    no_initial_focus = true,
    -- suppress_event takes a space-separated string in lua
    suppress_event   = "fullscreen maximize activate activatefocus fullscreenoutput",
})
