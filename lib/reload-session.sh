#!/usr/bin/env bash

# Helper script to reload user session without full logout
# This addresses group membership changes that require session reload

log() {
    echo "$1"
}

# Check if we need to reload the session
check_group_changes() {
    local current_groups=$(groups)
    local system_groups=$(id -Gn)
    
    if [[ "$current_groups" != "$system_groups" ]]; then
        log "→ Group membership has changed, session reload recommended"
        return 0
    fi
    return 1
}

# Attempt to reload the session in various ways
reload_session() {
    log "→ Attempting to reload user session..."
    
    # Method 1: Try to refresh systemd user session
    if command -v systemctl >/dev/null 2>&1; then
        log "→ Reloading systemd user session..."
        systemctl --user daemon-reexec 2>/dev/null || true
        systemctl --user daemon-reload 2>/dev/null || true
    fi
    
    # Method 2: Refresh D-Bus session
    if command -v dbus-launch >/dev/null 2>&1; then
        log "→ Refreshing D-Bus session..."
        # This is tricky to do safely in a script
        export $(dbus-launch 2>/dev/null | head -2) 2>/dev/null || true
    fi
    
    # Method 3: For Flatpak specifically, try to restart the user bus
    if command -v flatpak >/dev/null 2>&1; then
        log "→ Restarting Flatpak user services..."
        # Kill any running flatpak processes for the user
        pkill -u "$USER" -f flatpak 2>/dev/null || true
        sleep 1
    fi
    
    log "✓ Session reload attempted"
    log "→ If issues persist, a full logout/login may be required"
}

# Main execution
if check_group_changes; then
    reload_session
else
    log "→ No session reload needed"
fi