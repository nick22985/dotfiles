-- Environment variables + shared program names.
-- Converted from conf/env.conf.
--
-- Each require()d file is a separate Lua scope, so program names are shared by
-- RETURNING them as a table (bottom of this file) rather than as globals.
-- Consumers do: local vars = require("conf.env"); vars.terminal, etc.

local vars = {
    mainMod     = "SUPER",
    terminal    = "ghostty",
    fileManager = "thunar",
    menu        = "walker",
}

-- For dolphin etc. to open default apps automatically
hl.env("XDG_MENU_PREFIX", "arch-")
-- Force wayland via env
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")

hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force all apps to use Wayland
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_STYLE_OVERRIDE", "BreezeDark")
hl.env("QT_FORCE_DARK_MODE", "1")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("SDL_VIDEODRIVER", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")
-- Allow better support for screen sharing (Google Meet, Discord, etc)
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
    ecosystem = {
        no_update_news = true,
    },
})

return vars
