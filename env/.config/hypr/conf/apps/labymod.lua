-- LabyMod freeze fix. Converted from conf/apps/labymod.conf.

hl.window_rule({
    name             = "labymodfreezefix",
    -- LabyMod titles read "Minecraft 26.3 | Laby Client v47.2"; older builds said "| LabyMod".
    -- No class match: the class is not always com.mojang.minecraft (some builds set it to the title).
    match            = { title = [[^Minecraft .* \| Laby.*$]] },
    render_unfocused = true,
    workspace        = "special:game silent",
    no_initial_focus = true,
    -- suppress_event takes a space-separated string in lua
    suppress_event   = "fullscreen maximize activate activatefocus fullscreenoutput",
})
