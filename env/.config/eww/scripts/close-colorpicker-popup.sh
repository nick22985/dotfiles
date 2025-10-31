#!/bin/bash

# Add small delay to allow mouse to move between colorpicker and popup
sleep 0.1

# Check if we're still hovering (another hover event might have set it back to true)
if [ "$(eww get colorpicker_hover)" = "false" ]; then
    # Close all colorpicker popups
    eww close colorpicker-popup0 2>/dev/null
    eww close colorpicker-popup1 2>/dev/null  
    eww close colorpicker-popup2 2>/dev/null
fi