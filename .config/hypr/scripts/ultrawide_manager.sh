#!/bin/bash

# Hyprland Ultra-wide Window Manager
# For Samsung Odyssey G95NC - Monitor-specific gap management

MONITOR_DESC="Samsung Electric Company Odyssey G95NC HNTX400116"
MONITOR_WIDTH=7680
MONITOR_HEIGHT=2160

# Configurable padding percentage (change this to adjust side padding)
PADDING_PERCENTAGE=20

# Calculate padding values
SIDE_PADDING=$((MONITOR_WIDTH * PADDING_PERCENTAGE / 100))  # 20% = 1536px
CENTER_WIDTH=$((MONITOR_WIDTH - 2 * SIDE_PADDING))  # 4608px
AVAILABLE_AFTER_ONE_GAP=$((MONITOR_WIDTH - SIDE_PADDING))  # 6144px when one gap removed

# Store current state - declare as integers
declare -i current_windows=0
declare -i previous_windows=0
layout_mode="default"
target_workspace=""
gap_side=""  # Track which side has a window in the gap ("left" or "right")

# Function to get the workspace ID for our target monitor
get_target_workspace() {
    hyprctl monitors -j | jq -r ".[] | select(.description == \"$MONITOR_DESC\") | .activeWorkspace.id"
}

# Function to get window count on the current workspace of our monitor
get_window_count() {
    local workspace=$(get_target_workspace)
    if [[ -z "$workspace" ]]; then
        echo 0
        return
    fi

    # Count windows on this workspace (excluding special workspaces)
    local count=$(hyprctl clients -j | jq "[.[] | select(.workspace.id == $workspace and .mapped == true)] | length")
    echo "$count"
}

# Function to check if the current workspace is on our target monitor
is_target_workspace() {
    local current_workspace=$(hyprctl activeworkspace -j | jq -r '.id')
    local target_ws=$(get_target_workspace)
    [[ "$current_workspace" == "$target_ws" ]]
}

# Function to set monitor-specific gaps using workspace rules
# Hyprland uses CSS order: top right bottom left
set_workspace_gaps() {
    local workspace=$(get_target_workspace)
    local left=$1
    local right=$2
    local top=${3:-0}
    local bottom=${4:-0}

    if [[ -n "$workspace" ]]; then
        # Set gaps for the specific workspace (top right bottom left)
        local gap_command="workspace $workspace,gapsout:$top $right $bottom $left"
        echo "Executing: hyprctl keyword $gap_command"
        hyprctl keyword "$gap_command"
        echo "Set gaps for workspace $workspace: top=$top right=$right bottom=$bottom left=$left"
    fi
}

# Function to reset workspace gaps
reset_workspace_gaps() {
    local workspace=$(get_target_workspace)
    if [[ -n "$workspace" ]]; then
        hyprctl keyword workspace "$workspace,gapsout:0"
        echo "Reset gaps for workspace $workspace"
    fi
}

# Function to center single window with configurable padding on sides
handle_single_window() {
    if [[ "$layout_mode" != "single" ]] && is_target_workspace; then
        echo "Setting single window mode - ${PADDING_PERCENTAGE}% padding on sides"
        # Set padding on left and right sides
        set_workspace_gaps $SIDE_PADDING $SIDE_PADDING 0 0
        layout_mode="single"
    fi
}

# Function to get mouse position relative to target monitor
get_mouse_position_on_target_monitor() {
    # Get the target monitor's position and mouse position
    local monitor_info=$(hyprctl monitors -j | jq -r ".[] | select(.description == \"$MONITOR_DESC\")")
    local monitor_x=$(echo "$monitor_info" | jq -r '.x')
    local mouse_x=$(hyprctl cursorpos | grep -oP '\d+' | head -1)

    # Calculate relative position on the target monitor
    local relative_x=$((mouse_x - monitor_x))
    echo "$relative_x"
}

# Function to get the main (first) window on the workspace
get_main_window() {
    local workspace=$(get_target_workspace)
    hyprctl clients -j | jq -r "[.[] | select(.workspace.id == $workspace and .mapped == true)] | sort_by(.pid) | first | .address"
}

# Function to get the most recently opened window
get_newest_window() {
    local workspace=$(get_target_workspace)
    hyprctl clients -j | jq -r "[.[] | select(.workspace.id == $workspace and .mapped == true)] | sort_by(.pid) | last | .address"
}

# Function to handle dual windows - position new window in gap space and remove that gap
handle_dual_windows() {
    if [[ "$layout_mode" != "dual" ]] && is_target_workspace; then
        echo "Setting dual window mode"

        # Get mouse position relative to our target monitor
        local mouse_x=$(get_mouse_position_on_target_monitor)
        local screen_center=3840  # Half of 7680 (now relative to monitor)

        echo "Mouse position on target monitor: $mouse_x, Screen center: $screen_center"

        # Get the newest window (the one that just opened)
        local new_window=$(get_newest_window)

        if [[ $mouse_x -lt $screen_center ]]; then
            # New window on left side - use precise window targeting
            echo "Positioning new window in left gap space and removing left gap"
            # Remove the left gap first
            set_workspace_gaps 0 $SIDE_PADDING 0 0  # remove left gap, keep right gap

            # Get both windows
            local main_window=$(get_main_window)
            local new_window=$(get_newest_window)

            echo "Main window: $main_window, New window: $new_window"
            echo "Resizing new window to exactly ${SIDE_PADDING}px and main window to ${CENTER_WIDTH}px"

            # Resize both windows to exact sizes (original behavior that was working)
            hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$main_window
            hyprctl dispatch resizewindowpixel exact $SIDE_PADDING $MONITOR_HEIGHT,address:$new_window

            gap_side="left"  # Track that left gap is filled
        else
            # New window on right side - use precise window targeting
            echo "Positioning new window in right gap space and removing right gap"
            # Remove the right gap first
            set_workspace_gaps $SIDE_PADDING 0 0 0  # keep left gap, remove right gap

            # Get both windows
            local main_window=$(get_main_window)
            local new_window=$(get_newest_window)

            echo "Main window: $main_window, New window: $new_window"
            echo "Resizing main window to ${CENTER_WIDTH}px and new window to ${SIDE_PADDING}px"

            # For right side, let's try a different approach
            # First, ensure windows are in correct layout
            hyprctl dispatch layoutmsg swapwithmaster

            # Small delay
            sleep 0.1

            # Now resize using the same values as left side but with compensation
            hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$main_window
            hyprctl dispatch resizewindowpixel exact $((SIDE_PADDING + 15)) $MONITOR_HEIGHT,address:$new_window

            # Alternative: try using moveactive to force correct positioning
            hyprctl dispatch moveactive exact $((CENTER_WIDTH + SIDE_PADDING)) 0

            gap_side="right"  # Track that right gap is filled
        fi

        layout_mode="dual"
    fi
}

# Function to handle triple windows - fill the remaining gap
handle_triple_windows() {
    if [[ "$layout_mode" != "triple" ]] && is_target_workspace; then
        echo "Setting triple window mode"

        # Remove all gaps first
        set_workspace_gaps 0 0 0 0

        # Wait for layout to settle after gap removal
        sleep 0.3

        # Get all windows sorted by their X position (left to right)
        local workspace=$(get_target_workspace)
        local windows_json=$(hyprctl clients -j | jq "[.[] | select(.workspace.id == $workspace and .mapped == true)] | sort_by(.at[0])")

        # Verify we have 3 windows
        local window_count=$(echo "$windows_json" | jq 'length')
        if [[ $window_count -ne 3 ]]; then
            echo "Warning: Expected 3 windows but found $window_count"
            return
        fi

        # Get the windows in left-to-right order
        local left_window=$(echo "$windows_json" | jq -r '.[0].address')
        local center_window=$(echo "$windows_json" | jq -r '.[1].address')
        local right_window=$(echo "$windows_json" | jq -r '.[2].address')

        # Debug output
        local left_x=$(echo "$windows_json" | jq -r '.[0].at[0]')
        local center_x=$(echo "$windows_json" | jq -r '.[1].at[0]')
        local right_x=$(echo "$windows_json" | jq -r '.[2].at[0]')

        echo "Windows sorted by X position:"
        echo "  Left: $left_window at X=$left_x"
        echo "  Center: $center_window at X=$center_x"
        echo "  Right: $right_window at X=$right_x"

        # Resize all windows to their correct sizes
        echo "Resizing: left=${SIDE_PADDING}px, center=${CENTER_WIDTH}px, right=$((SIDE_PADDING - 30))px"

        hyprctl dispatch resizewindowpixel exact $SIDE_PADDING $MONITOR_HEIGHT,address:$left_window
        hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$center_window
        hyprctl dispatch resizewindowpixel exact $((SIDE_PADDING - 30)) $MONITOR_HEIGHT,address:$right_window

        layout_mode="triple"
    fi
}

# Function to handle multiple windows (4+) - default behavior
handle_multiple_windows() {
    if [[ "$layout_mode" != "default" ]] && is_target_workspace; then
        echo "Setting default window mode"
        reset_workspace_gaps
        layout_mode="default"
        gap_side=""
    fi
}

# Main event handler for window changes
handle_window_event() {
    # Only process if we're on a workspace belonging to the target monitor
    if ! is_target_workspace; then
        return
    fi

    # Small delay to ensure window state is updated
    sleep 0.1

    local new_count=$(get_window_count)

    # Only process if window count changed
    if [[ $new_count -ne $current_windows ]]; then
        # Save previous count BEFORE updating current_windows
        local prev_count=$current_windows
        current_windows=$new_count
        echo "Window count changed from $prev_count to $new_count on target monitor"

        case $new_count in
            0)
                reset_workspace_gaps
                layout_mode="default"
                gap_side=""
                previous_windows=0
                ;;
            1)
                handle_single_window
                gap_side=""
                previous_windows=1
                ;;
            2)
                # Pass the previous count to the function
                handle_dual_windows $prev_count
                previous_windows=2
                ;;
            3)
                handle_triple_windows
                previous_windows=3
                ;;
            *)
                handle_multiple_windows
                previous_windows=$new_count
                ;;
        esac
    fi
}

# Function to handle workspace changes
handle_workspace_change() {
    local new_workspace=$(get_target_workspace)

    # Check if we switched to a workspace on our target monitor
    if is_target_workspace; then
        local new_count=$(get_window_count)
        local prev_count=$current_windows  # Save before updating
        current_windows=$new_count
        target_workspace=$new_workspace
        echo "Switched to target monitor workspace $new_workspace - Window count: $new_count"

        case $new_count in
            0)
                reset_workspace_gaps
                layout_mode="default"
                ;;
            1)
                handle_single_window
                ;;
            2)
                handle_dual_windows $prev_count
                ;;
            3)
                handle_triple_windows
                ;;
            *)
                handle_multiple_windows
                ;;
        esac

        previous_windows=$new_count
    else
        # We're no longer on target monitor, reset our tracking
        layout_mode="default"
        gap_side=""
    fi
}

# Function to handle monitor focus changes
handle_monitor_change() {
    local event_data=$1

    # Check if we focused our target monitor
    if echo "$event_data" | grep -q "$MONITOR_DESC"; then
        echo "Focused target monitor"
        handle_workspace_change
    fi
}

# Main event handler
handle_event() {
    local line=$1
    local event_type=$(echo "$line" | cut -d'>' -f1)
    local event_data=$(echo "$line" | cut -d'>' -f2-)

    case "$event_type" in
        "openwindow"|"closewindow")
            handle_window_event
            ;;
        "workspace")
            handle_workspace_change
            ;;
        "focusedmon")
            handle_monitor_change "$event_data"
            ;;
    esac
}

# Initialize
echo "Starting Hyprland Ultra-wide Window Manager"
echo "Target monitor: $MONITOR_DESC"
echo "Monitor resolution: ${MONITOR_WIDTH}x${MONITOR_HEIGHT}"
echo "Padding: ${PADDING_PERCENTAGE}% (${SIDE_PADDING}px each side)"
echo "Will apply ${SIDE_PADDING}px side gaps for single windows on target monitor only"

# Get initial state
target_workspace=$(get_target_workspace)
if [[ -n "$target_workspace" ]] && is_target_workspace; then
    current_windows=$(get_window_count)
    previous_windows=$current_windows  # Initialize previous_windows
    echo "Initial workspace: $target_workspace, Window count: $current_windows"

    # Apply initial layout
    case $current_windows in
        1)
            handle_single_window
            ;;
        2)
            handle_dual_windows 0  # Pass 0 as we don't know previous state
            ;;
        3)
            handle_triple_windows
            ;;
        *)
            handle_multiple_windows
            ;;
    esac
else
    echo "Not currently on target monitor"
fi

# Main loop - connect to Hyprland socket
echo "Listening for window events..."
socat - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while read -r line; do
    handle_event "$line"
done
