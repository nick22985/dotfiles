-- System floating-window rules. Converted from conf/apps/system.conf.
-- (Original used the non-standard `match:` form; rewritten to correct lua.)

-- Floating windows (matched by the `floating-window` tag, set below)
hl.window_rule({ match = { tag = "floating-window" }, float = true, center = true, size = { 800, 600 } })

-- Tag common file dialogs as floating-window
hl.window_rule({
    match = {
        class = "(xdg-desktop-portal-gtk|sublime_text|DesktopEditors|org.gnome.Nautilus)",
        title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files)",
    },
    tag = "+floating-window",
})

-- Fullscreen screensaver
hl.window_rule({ match = { class = "Screensaver" }, fullscreen = true })
