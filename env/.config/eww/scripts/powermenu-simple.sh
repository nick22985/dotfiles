#!/bin/bash

# Simple power menu with escape support using hyprctl

case "$1" in
    "open")
        # Kill any existing power menu
        eww close powermenu-popup 2>/dev/null
        
        # Open power menu
        eww open powermenu-popup
        
        # Add temporary keybind to close power menu on Escape.
        # Hyprland 0.55+ Lua config: binds must go through hl.bind via `hyprctl eval`;
        # the old `hyprctl keyword bind "SUPER, Escape, ..."` string form is dead.
        hyprctl eval 'hl.bind("SUPER + Escape", hl.dsp.exec_cmd("~/.config/eww/scripts/close-powermenu.sh"))' 2>/dev/null
        hyprctl eval 'hl.bind("Escape", hl.dsp.exec_cmd("~/.config/eww/scripts/close-powermenu.sh"))' 2>/dev/null
        ;;
    "close")
        # Close power menu
        eww close powermenu-popup 2>/dev/null
        
        # Remove temporary keybinds
        hyprctl keyword unbind "SUPER, Escape" 2>/dev/null
        hyprctl keyword unbind ", Escape" 2>/dev/null
        ;;
    *)
        echo "Usage: $0 [open|close]"
        ;;
esac