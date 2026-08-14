-- Keybindings. Converted from conf/bindings.conf.

local vars        = require("conf.env")
local mainMod     = vars.mainMod
local terminal    = vars.terminal
local fileManager = vars.fileManager
local menu        = vars.menu

hl.bind(mainMod .. " + Q", hl.dsp.window.close())
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal))
-- hl.bind(mainMod .. " + M", hl.dsp.exit())
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
hl.bind(mainMod .. " + V", hl.dsp.window.float())
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo()) -- dwindle

-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- nvim-style focus (h/l/k/j)
hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "down" }))

hl.bind(mainMod .. " + SHIFT + l", hl.dsp.exec_cmd("hyprlock"))
-- NOTE: original config also binds SUPER+SHIFT+l to resizeactive (below); the
-- later bind wins. This conflict exists in the original conf and is preserved.

-- Switch workspaces with mainMod + [0-9]; move active window with + SHIFT
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Resize active window (repeating)
hl.bind("SUPER + SHIFT + left",  hl.dsp.window.resize({ x = -20, y = 0,   relative = true }), { repeating = true })
hl.bind("SUPER + SHIFT + right", hl.dsp.window.resize({ x = 20,  y = 0,   relative = true }), { repeating = true })
hl.bind("SUPER + SHIFT + up",    hl.dsp.window.resize({ x = 0,   y = -20, relative = true }), { repeating = true })
hl.bind("SUPER + SHIFT + down",  hl.dsp.window.resize({ x = 0,   y = 20,  relative = true }), { repeating = true })
hl.bind("SUPER + SHIFT + h",     hl.dsp.window.resize({ x = -20, y = 0,   relative = true }), { repeating = true })
hl.bind("SUPER + SHIFT + l",     hl.dsp.window.resize({ x = 20,  y = 0,   relative = true }), { repeating = true })
hl.bind("SUPER + SHIFT + k",     hl.dsp.window.resize({ x = 0,   y = -20, relative = true }), { repeating = true })
hl.bind("SUPER + SHIFT + j",     hl.dsp.window.resize({ x = 0,   y = 20,  relative = true }), { repeating = true })

-- Screenshots (scrnly) / recording (unified capture script)
hl.bind(mainMod .. " + S",         hl.dsp.exec_cmd("shot capture -m region -i"))
hl.bind(mainMod .. " + W",         hl.dsp.exec_cmd("shot capture -m window -i"))
hl.bind(mainMod .. " + M",         hl.dsp.exec_cmd("shot capture -m current-monitor -i"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd("~/.local/bin/capture -r -g"))
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.local/bin/capture -r -w"))
hl.bind(mainMod .. " + SHIFT + M", hl.dsp.exec_cmd("~/.local/bin/capture -r -m"))
hl.bind(mainMod .. " + SHIFT + X", hl.dsp.exec_cmd("~/.local/bin/capture --stop-recording"))

hl.bind("CTRL + SHIFT + SPACE", hl.dsp.exec_cmd("1password --quick-access"))
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "maximized" })) -- was fullscreen, 1

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness (locked + repeating)
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"),    { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),    { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl s 10%+"),                         { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl s 10%-"),                         { locked = true, repeating = true })

-- Requires playerctl (locked)
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })

hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("~/.config/hypr/scripts/active_window.sh"))

-- Audio profile switching
hl.bind(mainMod .. " + ALT + G",         hl.dsp.exec_cmd("~/dotfiles/scripts/switch-audio-device --use gsx-scarlett"))
hl.bind(mainMod .. " + ALT + B",         hl.dsp.exec_cmd("~/dotfiles/scripts/switch-audio-device --use btd-scarlett"))
hl.bind(mainMod .. " + ALT + SHIFT + B", hl.dsp.exec_cmd("~/dotfiles/scripts/switch-audio-device --use btd-mic"))
hl.bind(mainMod .. " + ALT + A",         hl.dsp.exec_cmd("~/.local/bin/audio-walker"))

hl.bind(mainMod .. " + SHIFT + p",
    hl.dsp.exec_cmd("$HOME/.config/hypr/scripts/click.sh $HOME/.config/hypr/scripts/click.txt --run"),
    { repeating = true })
