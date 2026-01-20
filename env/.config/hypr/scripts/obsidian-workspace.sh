#!/usr/bin/env bash

if ! pgrep -x obsidian >/dev/null; then
    flatpak run md.obsidian.Obsidian &
    sleep 1
fi

hyprctl dispatch togglespecialworkspace obsidian

