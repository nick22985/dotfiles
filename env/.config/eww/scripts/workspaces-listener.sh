#!/bin/bash
# Hyprland workspaces listener for eww
# This script listens to Hyprland events and outputs workspace information
# Automatically detects monitor from environment or parameter

# Get monitor name from parameter, environment vars, or auto-detect
if [[ -n "$1" ]]; then
    MONITOR_NAME="$1"
elif [[ -n "$MONITOR_ID" ]]; then
    # Convert monitor ID to monitor name
    MONITOR_NAME=$(hyprctl -j monitors 2>/dev/null | jq -r ".[$MONITOR_ID].name" 2>/dev/null || echo "")
elif [[ -n "$EWW_MONITOR" ]]; then
    MONITOR_NAME="$EWW_MONITOR"
else
    # Auto-detect current monitor
    MONITOR_NAME=$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused == true) | .name' 2>/dev/null || echo "")
fi

# Function to get workspaces with windows
get_workspaces_info() {
    # Fetch all data in one call to minimize hyprctl invocations
    local hypr_data=$(hyprctl -j workspaces 2>/dev/null || echo "[]")
    local active_workspace=$(hyprctl -j activeworkspace 2>/dev/null | jq -r '.id' 2>/dev/null || echo "1")
    
    # Validate active_workspace is a number
    if ! [[ "$active_workspace" =~ ^[0-9]+$ ]]; then
        active_workspace="1"
    fi
    
    # Parse workspace data once - more efficient than multiple jq calls
    local workspace_data=$(echo "$hypr_data" | jq -r '.[] | select(.windows > 0) | "\(.id):\(.monitor)"' 2>/dev/null)
    
    # Start with workspaces 1-6 (always visible on all monitors)
    local -a all_workspaces=(1 2 3 4 5 6)
    
    # Handle active workspace 7+ logic
    if [[ $active_workspace -gt 6 ]]; then
        local ws_bound_monitor=$(echo "$hypr_data" | jq -r ".[] | select(.id == $active_workspace) | .monitor" 2>/dev/null)
        
        # Simplified logic: add active workspace if no monitor specified OR if it matches this monitor
        if [[ -z "$MONITOR_NAME" || "$ws_bound_monitor" == "$MONITOR_NAME" ]]; then
            all_workspaces+=("$active_workspace")
        fi
    fi
    
    # Add monitor-bound workspaces 7+ that have windows
    if [[ -n "$workspace_data" ]]; then
        while IFS=':' read -r ws_id ws_monitor; do
            # Skip if empty or not a high workspace
            [[ -z "$ws_id" || $ws_id -le 6 || $ws_id -eq $active_workspace ]] && continue
            
            # Add workspace based on monitor filtering
            if [[ -z "$MONITOR_NAME" || "$ws_monitor" == "$MONITOR_NAME" ]]; then
                all_workspaces+=("$ws_id")
            fi
        done <<< "$workspace_data"
    fi
    
    # Sort and deduplicate using bash array operations (more efficient)
    IFS=$'\n' sorted_workspaces=($(printf '%s\n' "${all_workspaces[@]}" | sort -n | uniq))
    
    # Join array elements with commas
    local final_workspaces=$(IFS=','; echo "${sorted_workspaces[*]}")
    
    # Ensure we have valid output
    [[ -z "$final_workspaces" ]] && final_workspaces="1,2,3,4,5,6"
    
    # Create JSON output
    echo "{\"active\": $active_workspace, \"occupied\": [$final_workspaces]}"
}

# Rate limiting variables
last_output=""

# Output initial workspace info
get_workspaces_info

# Check if we're in Hyprland and socket exists
if [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]]; then
    SOCKET_PATH="/run/user/$(id -u)/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
    if [[ -S "$SOCKET_PATH" ]]; then
        # Listen to Hyprland events
        socat -u "UNIX-CONNECT:$SOCKET_PATH" - | while read -r line; do
            # Check for events that affect workspace display
            case "$line" in
                "workspace>>"*|"workspacev2>>"*|"focusedmon>>"*|"focusedmonv2>>"*|"openwindow>>"*|"closewindow>>"*|"destroyworkspace>>"*|"destroyworkspacev2>>"*|"createworkspace>>"*|"createworkspacev2>>"*|"movewindow>>"*|"movewindowv2>>"*)
                    current_output=$(get_workspaces_info)
                    # Only output if different from last output
                    if [[ "$current_output" != "$last_output" ]]; then
                        echo "$current_output"
                        last_output="$current_output"
                    fi
                    ;;
            esac
        done
    else
        # Fallback to polling if socket doesn't exist
        while true; do
            current_output=$(get_workspaces_info)
            if [[ "$current_output" != "$last_output" ]]; then
                echo "$current_output"
                last_output="$current_output"
            fi
            sleep 1
        done
    fi
else
    # Fallback to polling if not in Hyprland
    while true; do
        current_output=$(get_workspaces_info)
        if [[ "$current_output" != "$last_output" ]]; then
            echo "$current_output"
            last_output="$current_output"
        fi
        sleep 2
    done
fi
