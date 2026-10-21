-- LabyMod freeze fix. Converted from conf/apps/labymod.conf.

hl.window_rule({
    name             = "labymodfreezefix",
    -- Any Minecraft game window: LabyMod maps as "Minecraft 1.21.10 | Laby Client v47.4", vanilla as
    -- "Minecraft* 1.21.11". The Laby Launcher window ("Laby Launcher") stays out.
    -- No class match: the class is not always com.mojang.minecraft (some builds set it to the title).
    match            = { title = [[^Minecraft\*? [0-9].*$]] },
    render_unfocused = true,
    workspace        = "special:game silent",
    no_initial_focus = true,
    -- suppress_event takes a space-separated string in lua
    suppress_event   = "fullscreen maximize activate activatefocus fullscreenoutput",
})
