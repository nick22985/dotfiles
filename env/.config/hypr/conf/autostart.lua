-- Autostart. Converted from conf/autostart.conf.
-- Also consolidates the startup exec that lived in conf/env.conf (kbuildsycoca6,
-- noted inline below).

local vars = require("conf.env")

hl.on("hyprland.start", function()
	hl.exec_cmd("/usr/lib/pam_kwallet_init & hyprpaper & kwalletd5 & nm-applet")
	-- Start the user services after exporting the session environment: they require WAYLAND_DISPLAY,
	-- and outside a uwsm session graphical-session.target never starts them. Apps launched through
	-- elephant inherit its environment; without XCURSOR_SIZE, X11 apps size the cursor from the DPI.
	-- elephant restarts because it may already be running without these variables.
	hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE XCURSOR_SIZE HYPRCURSOR_SIZE && systemctl --user start hyprpolkitagent swaync hypridle && systemctl --user restart elephant; systemctl --user start wayvnc")
	-- hl.exec_cmd("uwsm app -- waybar")
	hl.exec_cmd("uwsm app -- 1password --silent")
	hl.exec_cmd("uwsm app -- steam")
	hl.exec_cmd("uwsm app -- walker --gapplication-service")
	hl.exec_cmd("uwsm app -- tailscale systray")
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	hl.exec_cmd([[sudo -b ydotoold --socket-path="$HOME/.ydotool_socket" --socket-own="$(id -u):$(id -g)"]])

	-- dark mode
	hl.exec_cmd([[gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"]]) -- GTK3 apps
	hl.exec_cmd([[gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"]]) -- GTK4 apps

	hl.exec_cmd("sleep 2 && bash $HOME/.config/hypr/scripts/ultrawide_manager_v3.sh")
	hl.exec_cmd("bash ~/.config/eww/launch.sh")

	-- Launch apps onto specific workspaces. The second argument is an exec rule that applies only to the
	-- window this command opens; discord (ws9) and slack (ws10) use class rules in conf/windowrule.lua instead.
	-- The terminal's rule is not silent so the session starts focused on ws1 on any monitor layout.
	hl.exec_cmd(vars.terminal, { workspace = "1" })
	hl.exec_cmd("brave --disable-features=WaylandWpColorManagerV1", { workspace = "2 silent" })
	hl.exec_cmd("flatpak run com.discordapp.Discord")
	-- hl.exec_cmd("discord")
	hl.exec_cmd("flatpak run com.slack.Slack")

	-- From conf/env.conf
	hl.exec_cmd("XDG_MENU_PREFIX=arch- kbuildsycoca6")
end)
