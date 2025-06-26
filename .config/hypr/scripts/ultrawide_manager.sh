#!/bin/bash

# Hyprland Ultra-wide Window Manager
# For Samsung Odyssey G95NC - Monitor-specific gap management
MONITOR_DESC="Samsung Electric Company Odyssey G95NC HNTX400116"
# TODO: get from MONITOR_DEC and set this
MONITOR_WIDTH=7680
MONITOR_HEIGHT=2160
SCREEN_CENTER=$((MONITOR_WIDTH/2))

PADDING_PERCENTAGE=20
# TODO: left, right. top, bot
DEFAULT_PADDING=20

SIDE_PADDING=$((MONITOR_WIDTH * PADDING_PERCENTAGE / 100))
CENTER_WIDTH=$((MONITOR_WIDTH - 2 * SIDE_PADDING))
AVAILABLE_AFTER_ONE_GAP=$((MONITOR_WIDTH - SIDE_PADDING))

declare -i current_windows=0
declare -i previous_windows=0
layout_mode="default"
target_workspace=""
gap_side=""

get_target_workspace() {
    hyprctl monitors -j | jq -r ".[] | select(.description == \"$MONITOR_DESC\") | .activeWorkspace.id"
}

get_window_count() {
    local workspace=$(get_target_workspace)
    if [[ -z "$workspace" ]]; then
        echo 0
        return
    fi

    local count=$(hyprctl clients -j | jq "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == false)] | length")
    echo "$count"
}

is_target_workspace() {
    local current_workspace=$(hyprctl activeworkspace -j | jq -r '.id')
    local target_ws=$(get_target_workspace)
    [[ "$current_workspace" == "$target_ws" ]]
}

set_workspace_gaps() {
    local workspace=$(get_target_workspace)
    local left=$1
    local right=$2
    local top=${3:-0}
    local bottom=${4:-0}

    if [[ -n "$workspace" ]]; then
        local gap_command="workspace $workspace,gapsout:$top $right $bottom $left"
        echo "Executing: hyprctl keyword $gap_command"
        hyprctl keyword "$gap_command"
        echo "Set gaps for workspace $workspace: top=$top right=$right bottom=$bottom left=$left"
    fi
}

reset_workspace_gaps() {
    local workspace=$(get_target_workspace)
    if [[ -n "$workspace" ]]; then
        hyprctl keyword workspace "$workspace,gapsout:0"
        echo "Reset gaps for workspace $workspace"
    fi
}

handle_single_window() {
    if [[ "$layout_mode" != "single" ]] && is_target_workspace; then
        echo "Setting single window mode - ${PADDING_PERCENTAGE}% padding on sides"
        set_workspace_gaps $SIDE_PADDING $SIDE_PADDING $DEFAULT_PADDING $DEFAULT_PADDING
        layout_mode="single"
    fi
}

get_mouse_position_on_target_monitor() {
    local monitor_info=$(hyprctl monitors -j | jq -r ".[] | select(.description == \"$MONITOR_DESC\")")
    local monitor_x=$(echo "$monitor_info" | jq -r '.x')
    local mouse_x=$(hyprctl cursorpos | grep -oP '\d+' | head -1)

    local relative_x=$((mouse_x - monitor_x))
    echo "$relative_x"
}

get_main_window() {
    local workspace=$(get_target_workspace)
    hyprctl clients -j | jq -r "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == false)] | sort_by(.pid) | first | .address"
}

get_newest_window() {
    local workspace=$(get_target_workspace)
    hyprctl clients -j | jq -r "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == false)] | sort_by(.pid) | last | .address"
}

handle_initial_dual_windows() {
    echo "Handling initial dual window configuration"

    local workspace=$(get_target_workspace)
    local windows_json=$(hyprctl clients -j | jq "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == false)] | sort_by(.at[0])")

    local left_window=$(echo "$windows_json" | jq -r '.[0].address')
    local right_window=$(echo "$windows_json" | jq -r '.[1].address')

    local left_x=$(echo "$windows_json" | jq -r '.[0].at[0]')
    local right_x=$(echo "$windows_json" | jq -r '.[1].at[0]')
    local left_width=$(echo "$windows_json" | jq -r '.[0].size[0]')
    local right_width=$(echo "$windows_json" | jq -r '.[1].size[0]')

    echo "Left window at X=$left_x, width=$left_width"
    echo "Right window at X=$right_x, width=$right_width"

    if [[ $left_width -lt $((SIDE_PADDING + 100)) ]]; then
        echo "Detected: Left window is in gap, setting appropriate gaps"
        set_workspace_gaps 0 $SIDE_PADDING $DEFAULT_PADDING $DEFAULT_PADDING

        hyprctl dispatch resizewindowpixel exact $SIDE_PADDING $MONITOR_HEIGHT,address:$left_window
        hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$right_window

        gap_side="left"
    elif [[ $right_width -lt $((SIDE_PADDING + 100)) ]]; then
        echo "Detected: Right window is in gap, setting appropriate gaps"
        set_workspace_gaps $SIDE_PADDING 0 $DEFAULT_PADDING $DEFAULT_PADDING

        hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$left_window
        hyprctl dispatch resizewindowpixel exact $((SIDE_PADDING - $DEFAULT_PADDING)) $MONITOR_HEIGHT,address:$right_window

        gap_side="right"
    else
        echo "Windows are roughly equal sized, using mouse position to determine layout"
        local mouse_x=$(get_mouse_position_on_target_monitor)

        if [[ $mouse_x -lt $SCREEN_CENTER ]]; then
            set_workspace_gaps 0 $SIDE_PADDING $DEFAULT_PADDING $DEFAULT_PADDING
            hyprctl dispatch resizewindowpixel exact $SIDE_PADDING $MONITOR_HEIGHT,address:$left_window
            hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$right_window
            gap_side="left"
        else
            set_workspace_gaps $SIDE_PADDING 0 $DEFAULT_PADDING $DEFAULT_PADDING
            hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$left_window
            hyprctl dispatch resizewindowpixel exact $((SIDE_PADDING - $DEFAULT_PADDING)) $MONITOR_HEIGHT,address:$right_window
            gap_side="right"
        fi
    fi

    layout_mode="dual"
}

handle_dual_windows() {
    if [[ "$layout_mode" != "dual" ]] && is_target_workspace; then
        echo "Setting dual window mode"

        local mouse_x=$(get_mouse_position_on_target_monitor)

        echo "Mouse position on target monitor: $mouse_x, Screen center: $SCREEN_CENTER"

        local new_window=$(get_newest_window)

        if [[ $mouse_x -lt $SCREEN_CENTER ]]; then
            echo "Positioning new window in left gap space and removing left gap"
            set_workspace_gaps 0 $SIDE_PADDING $DEFAULT_PADDING $DEFAULT_PADDING

            local main_window=$(get_main_window)
            local new_window=$(get_newest_window)

            echo "Main window: $main_window, New window: $new_window"
            echo "Resizing new window to exactly ${SIDE_PADDING}px and main window to ${CENTER_WIDTH}px"

            hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$main_window
            hyprctl dispatch resizewindowpixel exact $SIDE_PADDING $MONITOR_HEIGHT,address:$new_window

            gap_side="left"
        else
            echo "Positioning new window in right gap space and removing right gap"
            set_workspace_gaps $SIDE_PADDING 0 $DEFAULT_PADDING $DEFAULT_PADDING

            local main_window=$(get_main_window)
            local new_window=$(get_newest_window)

            echo "Main window: $main_window, New window: $new_window"
            echo "Resizing main window to ${CENTER_WIDTH}px and new window to ${SIDE_PADDING}px"

            hyprctl dispatch layoutmsg swapwithmaster

            sleep 0.1

            hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$main_window
            hyprctl dispatch resizewindowpixel exact $((SIDE_PADDING - $DEFAULT_PADDING)) $MONITOR_HEIGHT,address:$new_window

            hyprctl dispatch moveactive exact $((CENTER_WIDTH + SIDE_PADDING)) 0

            gap_side="right"
        fi

        layout_mode="dual"
    fi
}

handle_initial_triple_windows() {
    echo "Handling initial triple window configuration"

    set_workspace_gaps 0 0 $DEFAULT_PADDING $DEFAULT_PADDING

    sleep 0.3

    local workspace=$(get_target_workspace)
    local windows_json=$(hyprctl clients -j | jq "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == false)] | sort_by(.at[0])")

    local left_window=$(echo "$windows_json" | jq -r '.[0].address')
    local center_window=$(echo "$windows_json" | jq -r '.[1].address')
    local right_window=$(echo "$windows_json" | jq -r '.[2].address')

    hyprctl dispatch resizewindowpixel exact $SIDE_PADDING $MONITOR_HEIGHT,address:$left_window
    hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$center_window
    hyprctl dispatch resizewindowpixel exact $((SIDE_PADDING - 30)) $MONITOR_HEIGHT,address:$right_window

    layout_mode="triple"
}

handle_triple_windows() {
    if [[ "$layout_mode" != "triple" ]] && is_target_workspace; then
        echo "Setting triple window mode"

        set_workspace_gaps 0 0 $DEFAULT_PADDING $DEFAULT_PADDING

        sleep 0.3

        local workspace=$(get_target_workspace)
        local windows_json=$(hyprctl clients -j | jq "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == false)] | sort_by(.at[0])")

        local window_count=$(echo "$windows_json" | jq 'length')
        if [[ $window_count -ne 3 ]]; then
            echo "Warning: Expected 3 windows but found $window_count"
            return
        fi

        local left_window=$(echo "$windows_json" | jq -r '.[0].address')
        local center_window=$(echo "$windows_json" | jq -r '.[1].address')
        local right_window=$(echo "$windows_json" | jq -r '.[2].address')

        local left_x=$(echo "$windows_json" | jq -r '.[0].at[0]')
        local center_x=$(echo "$windows_json" | jq -r '.[1].at[0]')
        local right_x=$(echo "$windows_json" | jq -r '.[2].at[0]')

        echo "Windows sorted by X position:"
        echo "  Left: $left_window at X=$left_x"
        echo "  Center: $center_window at X=$center_x"
        echo "  Right: $right_window at X=$right_x"

        echo "Resizing: left=${SIDE_PADDING}px, center=${CENTER_WIDTH}px, right=$((SIDE_PADDING - 30))px"

        hyprctl dispatch resizewindowpixel exact $SIDE_PADDING $MONITOR_HEIGHT,address:$left_window
        hyprctl dispatch resizewindowpixel exact $CENTER_WIDTH $MONITOR_HEIGHT,address:$center_window
        hyprctl dispatch resizewindowpixel exact $((SIDE_PADDING - 30)) $MONITOR_HEIGHT,address:$right_window

        layout_mode="triple"
    fi
}

handle_multiple_windows() {
    if [[ "$layout_mode" != "default" ]] && is_target_workspace; then
        echo "Setting default window mode"
        reset_workspace_gaps
        layout_mode="default"
        gap_side=""
    fi
}

handle_window_event() {
    if ! is_target_workspace; then
        return
    fi

    sleep 0.1

    local new_count=$(get_window_count)

    if [[ $new_count -ne $current_windows ]]; then
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

handle_workspace_change() {
    local new_workspace=$(get_target_workspace)

    if is_target_workspace; then
        local new_count=$(get_window_count)
        local prev_count=$current_windows
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
        layout_mode="default"
        gap_side=""
    fi
}

handle_monitor_change() {
    local event_data=$1

    if echo "$event_data" | grep -q "$MONITOR_DESC"; then
        echo "Focused target monitor"
        handle_workspace_change
    fi
}

handle_window_reposition() {
    sleep 0.3

    local new_count=$(get_window_count)
    local prev_count=$current_windows

    echo "Window drag completed - re-evaluating layout"
    echo "Previous window count: $prev_count, Current window count: $new_count"

    current_windows=$new_count

    layout_mode=""

    case $new_count in
        0)
            reset_workspace_gaps
            layout_mode="default"
            gap_side=""
            ;;
        1)
            handle_single_window
            gap_side=""
            ;;
        2)
            handle_initial_dual_windows
            ;;
        3)
            handle_initial_triple_windows
            ;;
        *)
            handle_multiple_windows
            ;;
    esac

    previous_windows=$new_count
}

was_target_workspace_involved() {
    local event_data=$1
    local target_ws=$(get_target_workspace)

    if [[ -n "$target_ws" ]] && echo "$event_data" | grep -qE "(^|,)${target_ws}(,|$)"; then
        return 0
    fi
    return 1
}

handle_event() {
    local line=$1
    local event_type=$(echo "$line" | cut -d'>' -f1)
    local event_data=$(echo "$line" | cut -d'>' -f2-)

    case "$event_type" in
        "openwindow"|"closewindow")
            handle_window_event
            ;;
        "movewindow")
            echo "Move window event detected: $event_data"

            local moved_to_workspace=$(echo "$event_data" | cut -d',' -f2)
            local target_ws=$(get_target_workspace)

            local should_handle=0

            if is_target_workspace; then
                should_handle=1
                echo "Currently on target workspace - will re-evaluate"
            fi

            if [[ "$moved_to_workspace" == "$target_ws" ]]; then
                should_handle=1
                echo "Window moved TO target workspace $target_ws"
            fi

            if [[ "$target_workspace" == "$target_ws" ]] && [[ -n "$target_ws" ]]; then
                should_handle=1
                echo "Target workspace was involved in move"
            fi

            if [[ $should_handle -eq 1 ]]; then
                handle_window_reposition
            fi
            ;;
        "changefloatingmode")
            if is_target_workspace; then
                echo "Floating mode changed - will re-evaluate after delay"
                sleep 0.5
                handle_window_reposition
            fi
            ;;
        "workspace")
            handle_workspace_change
            ;;
        "focusedmon")
            handle_monitor_change "$event_data"
            ;;
    esac
}

echo "Starting Hyprland Ultra-wide Window Manager"
echo "Target monitor: $MONITOR_DESC"
echo "Monitor resolution: ${MONITOR_WIDTH}x${MONITOR_HEIGHT}"
echo "Padding: ${PADDING_PERCENTAGE}% (${SIDE_PADDING}px each side)"
echo "Will apply ${SIDE_PADDING}px side gaps for single windows on target monitor only"

target_workspace=$(get_target_workspace)
if [[ -n "$target_workspace" ]] && is_target_workspace; then
    current_windows=$(get_window_count)
    previous_windows=$current_windows
    echo "Initial workspace: $target_workspace, Window count: $current_windows"

    case $current_windows in
        0)
            echo "No windows on target monitor"
            layout_mode="default"
            ;;
        1)
            echo "Applying single window layout"
            handle_single_window
            ;;
        2)
            echo "Applying dual window layout"
            handle_initial_dual_windows
            ;;
        3)
            echo "Applying triple window layout"
            handle_initial_triple_windows
            ;;
        *)
            echo "Multiple windows detected ($current_windows), using default layout"
            handle_multiple_windows
            ;;
    esac
else
    echo "Not currently on target monitor"
fi

echo "Listening for window events..."
socat - "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock" | while read -r line; do
    handle_event "$line"
done
