-- Autostart. Converted from conf/autostart.conf.
-- Also consolidates the two startup execs that lived in other sourced files:
--   * conf/env.conf       -> kbuildsycoca6
--   * conf/windowrule.conf -> flameshot
-- (both noted inline below).

local vars = require("conf.env")

hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/lib/pam_kwallet_init & hyprpaper & kwalletd5 & nm-applet")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
    -- hl.exec_cmd("uwsm app -- waybar")
    hl.exec_cmd("uwsm app -- 1password --silent")
    hl.exec_cmd("uwsm app -- steam")
    hl.exec_cmd("uwsm app -- elephant")
    hl.exec_cmd("uwsm app -- walker --gapplication-service")
    hl.exec_cmd("uwsm app -- tailscale systray")
    hl.exec_cmd("uwsm app swaync")
    -- hl.exec_cmd("hypridle")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd([[sudo -b ydotoold --socket-path="$HOME/.ydotool_socket" --socket-own="$(id -u):$(id -g)"]])

    -- dark mode
    hl.exec_cmd([[gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"]])   -- GTK3 apps
    hl.exec_cmd([[gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"]])  -- GTK4 apps

    hl.exec_cmd("sleep 2 && bash $HOME/.config/hypr/scripts/ultrawide_manager.sh")
    hl.exec_cmd("bash ~/.config/eww/launch.sh")

    -- Launch apps onto specific workspaces.
    -- NOTE: hl.exec_cmd takes ONLY a command string (run via /bin/sh) — the old
    -- `exec-once = [workspace N silent] <cmd>` inline-rule form has no direct
    -- equivalent here, so a `{ workspace = ... }` 2nd arg is NOT valid and was
    -- removed. Placement is instead done by class-matched window rules:
    --   * discord -> ws9, slack -> ws10  are set in conf/windowrule.lua and
    --     fire for these launched instances too.
    --   * terminal opens on ws1 (the default focused workspace at startup).
    hl.exec_cmd(vars.terminal)
    hl.exec_cmd("brave --disable-features=WaylandWpColorManagerV1")
    hl.exec_cmd("flatpak run com.discordapp.Discord")
    -- hl.exec_cmd("discord")
    hl.exec_cmd("flatpak run com.slack.Slack")

    -- From conf/env.conf
    hl.exec_cmd("XDG_MENU_PREFIX=arch- kbuildsycoca6")

    -- From conf/windowrule.conf (original had a typo "Flamehsot"; corrected here)
    hl.exec_cmd("flatpak run org.flameshot.Flameshot")
end)
