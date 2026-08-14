-- Window rules. Converted from conf/windowrule.conf.
--
-- The original used a non-standard `match:class ...` hyprlang form (neither the
-- old `class:` matcher nor the new lua `match = {}` table). Rewritten to the
-- correct lua `hl.window_rule` API, combining same-match rules where possible.

-- discord & slack always on 9 and 10
hl.window_rule({ match = { class = "(discord)$" }, workspace = "9 silent" })
hl.window_rule({ match = { class = "(slack)$" },   workspace = "10 silent", no_initial_focus = true })

-- flameshot setup
-- (noanim isn't necessary but animations with these rules might look bad)
hl.window_rule({
    match            = { class = "^(flameshot)$" },
    no_anim          = true,
    float            = true,
    move             = { 0, 0 },
    pin              = true,
    no_initial_focus = true,
})
-- The corresponding `exec` for flameshot was moved to conf/autostart.lua.

-- 1Password quick access popup centering
hl.window_rule({
    match        = { class = "^(1Password)$", title = "^(Quick Access — 1Password)$" },
    center       = true,
    stay_focused = true,
    pin          = true,
})

-- xwaylandvideobridge
hl.window_rule({
    match            = { class = "^(xwaylandvideobridge)$" },
    opacity          = "0.0 override",
    no_anim          = true,
    no_initial_focus = true,
    no_focus         = true,
    max_size         = { 1, 1 },
    no_blur          = true,
})

-- Ignore maximize requests from apps. You'll probably like this.
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

-- Fix some dragging issues with XWayland
hl.window_rule({
    match    = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})
