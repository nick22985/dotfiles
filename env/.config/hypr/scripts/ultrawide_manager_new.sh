#!/bin/bash

# Hyprland Ultra-wide Window Manager v2
# For Samsung Odyssey G95NC - Improved zone-based window management
#
# Layout concept:
#   |--LEFT--|----CENTER----|--RIGHT--|
#   |  25%   |     50%      |   25%   |
#
# Behaviors:
#   1 window  -> centered in CENTER zone (with side gaps)
#   2 windows -> one CENTER + one SIDE (user chooses which side)
#   3 windows -> LEFT + CENTER + RIGHT
#   4+ windows -> default hyprland layout (no gaps)

# Note: Not using set -e as it causes issues with the event loop
set -uo pipefail

# === CONFIGURATION ===
MONITOR_DESC="Samsung Electric Company Odyssey G95NC HNTX400116"
MONITOR_WIDTH=7680
MONITOR_HEIGHT=2160

# Zone percentages (must sum to 100)
LEFT_ZONE_PCT=25
CENTER_ZONE_PCT=50
RIGHT_ZONE_PCT=25

# Gaps/padding
OUTER_GAP=20  # Gap around the edges of the monitor
INNER_GAP=10  # Gap between windows

# === CALCULATED VALUES ===
LEFT_ZONE_WIDTH=$((MONITOR_WIDTH * LEFT_ZONE_PCT / 100))
CENTER_ZONE_WIDTH=$((MONITOR_WIDTH * CENTER_ZONE_PCT / 100))
RIGHT_ZONE_WIDTH=$((MONITOR_WIDTH * RIGHT_ZONE_PCT / 100))

# Zone boundaries (x coordinates)
LEFT_ZONE_END=$LEFT_ZONE_WIDTH
CENTER_ZONE_END=$((LEFT_ZONE_WIDTH + CENTER_ZONE_WIDTH))

# === STATE ===
declare -A WINDOW_ZONES  # Maps window address -> zone (left/center/right)
CURRENT_LAYOUT=""        # single/dual-left/dual-right/triple/default
DEBOUNCE_PID=""
SETTLING_FILE="/tmp/ultrawide_manager.settling"  # File-based settling flag

# === LOGGING ===
LOG_FILE="/tmp/ultrawide_manager.log"
STATE_FILE="/tmp/ultrawide_manager.state"

log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

debug() {
    if [[ "${DEBUG:-1}" == "1" ]]; then
        local msg="[$(date '+%H:%M:%S')] [DEBUG] $*"
        echo "$msg"
        echo "$msg" >> "$LOG_FILE"
    fi
}

log_windows() {
    local workspace
    workspace=$(get_target_workspace)
    
    if [[ -z "$workspace" ]]; then
        debug "No target workspace found"
        return
    fi
    
    local all_clients
    all_clients=$(hyprctl clients -j)
    
    local tiled_windows floating_windows
    tiled_windows=$(echo "$all_clients" | jq "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == false)]")
    floating_windows=$(echo "$all_clients" | jq "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == true)]")
    
    local tiled_count floating_count
    tiled_count=$(echo "$tiled_windows" | jq 'length')
    floating_count=$(echo "$floating_windows" | jq 'length')
    
    log "=== WINDOW STATUS (workspace $workspace) ==="
    log "Tiled: $tiled_count | Floating: $floating_count | Total: $((tiled_count + floating_count))"
    
    if [[ $tiled_count -gt 0 ]]; then
        log "--- Tiled Windows ---"
        echo "$tiled_windows" | jq -r '.[] | "  \(.address) | \(.class) | \(.title[0:30]) | pos:(\(.at[0]),\(.at[1])) | size:(\(.size[0])x\(.size[1]))"' | while read -r line; do
            log "$line"
        done
    fi
    
    if [[ $floating_count -gt 0 ]]; then
        log "--- Floating Windows ---"
        echo "$floating_windows" | jq -r '.[] | "  \(.address) | \(.class) | \(.title[0:30]) | pos:(\(.at[0]),\(.at[1])) | size:(\(.size[0])x\(.size[1]))"' | while read -r line; do
            log "$line"
        done
    fi
    log "================================"
}

# === HYPRLAND HELPERS ===
get_monitor_info() {
    hyprctl monitors -j | jq -r ".[] | select(.description == \"$MONITOR_DESC\")"
}

get_monitor_x_offset() {
    local info
    info=$(get_monitor_info)
    if [[ -n "$info" ]]; then
        echo "$info" | jq -r '.x'
    else
        echo "0"
    fi
}

get_target_workspace() {
    local info
    info=$(get_monitor_info)
    if [[ -n "$info" ]]; then
        echo "$info" | jq -r '.activeWorkspace.id'
    else
        echo ""
    fi
}

is_on_target_monitor() {
    local workspace
    workspace=$(get_target_workspace)
    [[ -n "$workspace" ]]
}

get_tiled_windows() {
    local workspace
    workspace=$(get_target_workspace)
    if [[ -z "$workspace" ]]; then
        echo "[]"
        return
    fi
    hyprctl clients -j | jq "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == false)]"
}

get_window_count() {
    local windows
    windows=$(get_tiled_windows)
    echo "$windows" | jq 'length'
}

get_focused_window() {
    hyprctl activewindow -j | jq -r '.address // empty'
}

# === ZONE DETECTION ===
# Determines which zone a window is in based on its center X position
get_window_zone() {
    local window_addr=$1
    local monitor_offset
    monitor_offset=$(get_monitor_x_offset)
    
    local window_info
    window_info=$(hyprctl clients -j | jq ".[] | select(.address == \"$window_addr\")")
    
    if [[ -z "$window_info" ]]; then
        echo "unknown"
        return
    fi
    
    local window_x window_width window_center_x relative_x
    window_x=$(echo "$window_info" | jq -r '.at[0]')
    window_width=$(echo "$window_info" | jq -r '.size[0]')
    window_center_x=$((window_x + window_width / 2))
    relative_x=$((window_center_x - monitor_offset))
    
    if [[ $relative_x -lt $LEFT_ZONE_END ]]; then
        echo "left"
    elif [[ $relative_x -lt $CENTER_ZONE_END ]]; then
        echo "center"
    else
        echo "right"
    fi
}

# Get mouse position relative to target monitor
get_mouse_zone() {
    local monitor_offset
    monitor_offset=$(get_monitor_x_offset)
    
    local mouse_x
    mouse_x=$(hyprctl cursorpos -j | jq -r '.x')
    
    local relative_x=$((mouse_x - monitor_offset))
    
    if [[ $relative_x -lt $LEFT_ZONE_END ]]; then
        echo "left"
    elif [[ $relative_x -lt $CENTER_ZONE_END ]]; then
        echo "center"
    else
        echo "right"
    fi
}

# === GAP MANAGEMENT ===
set_gaps() {
    local workspace left right top bottom
    workspace=$(get_target_workspace)
    left=${1:-0}
    right=${2:-0}
    top=${3:-$OUTER_GAP}
    bottom=${4:-$OUTER_GAP}
    
    if [[ -n "$workspace" ]]; then
        # Format: gapsout:top right bottom left
        hyprctl keyword "workspace $workspace,gapsout:$top $right $bottom $left" >/dev/null 2>&1
        debug "Set gaps: L=$left R=$right T=$top B=$bottom"
    fi
}

reset_gaps() {
    local workspace
    workspace=$(get_target_workspace)
    if [[ -n "$workspace" ]]; then
        hyprctl keyword "workspace $workspace,gapsout:$OUTER_GAP" >/dev/null 2>&1
        debug "Reset gaps to default"
    fi
}

# === WINDOW POSITIONING ===
# Tolerance for position/size comparison (pixels)
POSITION_TOLERANCE=50

# Check if a window is already at the expected position/size
is_window_correct() {
    local window_addr=$1
    local expected_x=$2
    local expected_y=$3
    local expected_w=$4
    local expected_h=$5
    
    local window_info
    window_info=$(hyprctl clients -j | jq ".[] | select(.address == \"$window_addr\")")
    
    if [[ -z "$window_info" ]]; then
        return 1
    fi
    
    local actual_x actual_y actual_w actual_h
    actual_x=$(echo "$window_info" | jq -r '.at[0]')
    actual_y=$(echo "$window_info" | jq -r '.at[1]')
    actual_w=$(echo "$window_info" | jq -r '.size[0]')
    actual_h=$(echo "$window_info" | jq -r '.size[1]')
    
    local dx dy dw dh
    dx=$(( actual_x - expected_x ))
    dy=$(( actual_y - expected_y ))
    dw=$(( actual_w - expected_w ))
    dh=$(( actual_h - expected_h ))
    
    # Absolute values
    [[ $dx -lt 0 ]] && dx=$(( -dx ))
    [[ $dy -lt 0 ]] && dy=$(( -dy ))
    [[ $dw -lt 0 ]] && dw=$(( -dw ))
    [[ $dh -lt 0 ]] && dh=$(( -dh ))
    
    if [[ $dx -le $POSITION_TOLERANCE && $dy -le $POSITION_TOLERANCE && $dw -le $POSITION_TOLERANCE && $dh -le $POSITION_TOLERANCE ]]; then
        debug "is_window_correct $window_addr: OK (actual=${actual_x},${actual_y} ${actual_w}x${actual_h} vs expected=${expected_x},${expected_y} ${expected_w}x${expected_h} | dx=$dx dy=$dy dw=$dw dh=$dh)"
        return 0  # Window is correct
    else
        debug "is_window_correct $window_addr: MISMATCH (actual=${actual_x},${actual_y} ${actual_w}x${actual_h} vs expected=${expected_x},${expected_y} ${expected_w}x${expected_h} | dx=$dx dy=$dy dw=$dw dh=$dh)"
        return 1  # Window needs adjustment
    fi
}

# Calculate expected position for a zone (returns: x y width height)
get_zone_geometry() {
    local zone=$1
    local monitor_offset
    monitor_offset=$(get_monitor_x_offset)
    
    local x y width height
    y=$OUTER_GAP
    height=$((MONITOR_HEIGHT - 2 * OUTER_GAP))
    
    case "$zone" in
        left)
            x=$((monitor_offset + OUTER_GAP))
            width=$((LEFT_ZONE_WIDTH - OUTER_GAP - INNER_GAP / 2))
            ;;
        center)
            x=$((monitor_offset + LEFT_ZONE_WIDTH + INNER_GAP / 2))
            width=$((CENTER_ZONE_WIDTH - INNER_GAP))
            ;;
        right)
            x=$((monitor_offset + LEFT_ZONE_WIDTH + CENTER_ZONE_WIDTH + INNER_GAP / 2))
            width=$((RIGHT_ZONE_WIDTH - OUTER_GAP - INNER_GAP / 2))
            ;;
        *)
            x=$((monitor_offset + LEFT_ZONE_WIDTH + INNER_GAP / 2))
            width=$((CENTER_ZONE_WIDTH - INNER_GAP))
            ;;
    esac
    
    echo "$x $y $width $height"
}

# Resize a window to fit a specific zone width
# Resize a window to fit a specific zone width
# Positioning is handled by gaps + dwindle natural tiling
position_window_in_zone() {
    local window_addr=$1
    local zone=$2
    
    local geometry
    geometry=$(get_zone_geometry "$zone")
    local x y width height
    read x y width height <<< "$geometry"
    
    # Check if window is already the correct size and position
    if is_window_correct "$window_addr" "$x" "$y" "$width" "$height"; then
        debug "Window $window_addr already correct in $zone, skipping"
        return
    fi
    
    debug "Resizing $window_addr for $zone: w=$width h=$height"
    
    hyprctl dispatch resizewindowpixel "exact $width $height,address:$window_addr" >/dev/null 2>&1
}

# Verify window sizes are correct and fix if needed
verify_and_fix_layout() {
    local min_width=500  # Minimum acceptable width for any window
    
    local workspace
    workspace=$(get_target_workspace)
    if [[ -z "$workspace" ]]; then
        return
    fi
    
    local windows
    windows=$(get_tiled_windows)
    local count
    count=$(echo "$windows" | jq 'length')
    
    if [[ $count -lt 1 || $count -gt 3 ]]; then
        return
    fi
    
    # Check each window's width
    local needs_fix=false
    local window_info
    while IFS= read -r window_info; do
        local addr width
        addr=$(echo "$window_info" | jq -r '.address')
        width=$(echo "$window_info" | jq -r '.size[0]')
        
        if [[ $width -lt $min_width ]]; then
            log "WARNING: Window $addr has invalid width: ${width}px (min: ${min_width}px)"
            needs_fix=true
            break
        fi
    done < <(echo "$windows" | jq -c '.[]')
    
    if [[ "$needs_fix" == "true" ]]; then
        log "Detected invalid window sizes, re-applying layout..."
        # Force re-apply by clearing layout state
        CURRENT_LAYOUT=""
        LAST_TILED_ADDRESSES=""
        
        case $count in
            1) apply_single_window_layout ;;
            2) apply_dual_window_layout ;;
            3) apply_triple_window_layout ;;
        esac
    fi
}

# === LAYOUT HANDLERS ===
apply_single_window_layout() {
    log "Applying single window layout (centered)"
    
    local windows
    windows=$(get_tiled_windows)
    local window_addr
    window_addr=$(echo "$windows" | jq -r '.[0].address')
    
    if [[ -z "$window_addr" || "$window_addr" == "null" ]]; then
        return
    fi
    
    # Set gaps on both sides
    set_gaps $LEFT_ZONE_WIDTH $RIGHT_ZONE_WIDTH $OUTER_GAP $OUTER_GAP
    
    CURRENT_LAYOUT="single"
    WINDOW_ZONES["$window_addr"]="center"
}

apply_dual_window_layout() {
    local preferred_side=${1:-""}
    
    local windows
    windows=$(get_tiled_windows)
    
    # Sort windows by X position
    local sorted_windows
    sorted_windows=$(echo "$windows" | jq 'sort_by(.at[0])')
    
    local left_window right_window
    left_window=$(echo "$sorted_windows" | jq -r '.[0].address')
    right_window=$(echo "$sorted_windows" | jq -r '.[1].address')
    
    if [[ -z "$left_window" || "$left_window" == "null" || \
          -z "$right_window" || "$right_window" == "null" ]]; then
        debug "apply_dual: not enough tiled windows, skipping"
        return
    fi
    if [[ -z "$preferred_side" ]]; then
        # Check where windows currently are
        local left_zone right_zone
        left_zone=$(get_window_zone "$left_window")
        right_zone=$(get_window_zone "$right_window")
        
        debug "Current zones - left_window: $left_zone, right_window: $right_zone"
        
        # If one is clearly in a side zone, use that configuration
        if [[ "$left_zone" == "left" ]]; then
            preferred_side="left"
        elif [[ "$right_zone" == "right" ]]; then
            preferred_side="right"
        else
            # Default: use mouse position to decide
            local mouse_zone
            mouse_zone=$(get_mouse_zone)
            if [[ "$mouse_zone" == "left" ]]; then
                preferred_side="left"
            else
                preferred_side="right"
            fi
        fi
    fi
    
    # Check if windows are already in correct positions for this layout
    local zone1 zone2
    if [[ "$preferred_side" == "left" ]]; then
        zone1="left"
        zone2="center"
    else
        zone1="center"
        zone2="right"
    fi
    
    local geom1 geom2
    geom1=$(get_zone_geometry "$zone1")
    geom2=$(get_zone_geometry "$zone2")
    
    local x1 y1 w1 h1 x2 y2 w2 h2
    read x1 y1 w1 h1 <<< "$geom1"
    read x2 y2 w2 h2 <<< "$geom2"
    
    if is_window_correct "$left_window" "$x1" "$y1" "$w1" "$h1" && \
       is_window_correct "$right_window" "$x2" "$y2" "$w2" "$h2"; then
        debug "apply_dual: SKIPPING - preferred_side=$preferred_side left_window=$left_window right_window=$right_window zone1=$zone1 zone2=$zone2"
        debug "Dual layout ($preferred_side) already correct, skipping"
        CURRENT_LAYOUT="dual-$preferred_side"
        # Store CURRENT zone for each window (for drag detection)
        WINDOW_ZONES["$left_window"]=$(get_window_zone "$left_window")
        WINDOW_ZONES["$right_window"]=$(get_window_zone "$right_window")
        return
    fi
    
    log "Applying dual window layout (side: ${preferred_side:-auto})"
    
    if [[ "$preferred_side" == "left" ]]; then
        # left_window (lower X) → left zone, right_window (higher X) → center zone
        # dwindle always resizes the lower-X window regardless of address parameter.
        # So we resize left_window to left zone width; right_window (center) gets the remainder.
        set_gaps 0 $RIGHT_ZONE_WIDTH $OUTER_GAP $OUTER_GAP
        position_window_in_zone "$left_window" "left"
        WINDOW_ZONES["$left_window"]="left"
        WINDOW_ZONES["$right_window"]="center"
        CURRENT_LAYOUT="dual-left"
    else
        # left_window (lower X) → center zone, right_window (higher X) → right zone
        # We resize left_window to center zone width; right_window (right) gets the remainder.
        set_gaps $LEFT_ZONE_WIDTH 0 $OUTER_GAP $OUTER_GAP
        position_window_in_zone "$left_window" "center"
        WINDOW_ZONES["$left_window"]="center"
        WINDOW_ZONES["$right_window"]="right"
        CURRENT_LAYOUT="dual-right"
    fi
}

apply_triple_window_layout() {
    local windows
    windows=$(get_tiled_windows)
    
    # Sort windows by X position
    local sorted_windows
    sorted_windows=$(echo "$windows" | jq 'sort_by(.at[0])')
    
    local left_window center_window right_window
    left_window=$(echo "$sorted_windows" | jq -r '.[0].address')
    center_window=$(echo "$sorted_windows" | jq -r '.[1].address')
    right_window=$(echo "$sorted_windows" | jq -r '.[2].address')
    
    if [[ -z "$left_window" || "$left_window" == "null" ]]; then
        return
    fi
    
    # Check if all windows are already in correct positions
    local left_geom center_geom right_geom
    left_geom=$(get_zone_geometry "left")
    center_geom=$(get_zone_geometry "center")
    right_geom=$(get_zone_geometry "right")
    
    local lx ly lw lh cx cy cw ch rx ry rw rh
    read lx ly lw lh <<< "$left_geom"
    read cx cy cw ch <<< "$center_geom"
    read rx ry rw rh <<< "$right_geom"
    
    if is_window_correct "$left_window" "$lx" "$ly" "$lw" "$lh" && \
       is_window_correct "$center_window" "$cx" "$cy" "$cw" "$ch" && \
       is_window_correct "$right_window" "$rx" "$ry" "$rw" "$rh"; then
        debug "Triple layout already correct, skipping"
        CURRENT_LAYOUT="triple"
        # Store CURRENT zone for each window (for drag detection)
        # Use get_window_zone to get actual current zone, not assumed position
        WINDOW_ZONES["$left_window"]=$(get_window_zone "$left_window")
        WINDOW_ZONES["$center_window"]=$(get_window_zone "$center_window")
        WINDOW_ZONES["$right_window"]=$(get_window_zone "$right_window")
        return
    fi
    
    log "Applying triple window layout"
    
    # No side gaps needed - windows fill all zones
    set_gaps 0 0 $OUTER_GAP $OUTER_GAP
    
    # Resize outer windows first to pin them, then center fills the remainder
    position_window_in_zone "$left_window" "left"
    position_window_in_zone "$right_window" "right"
    position_window_in_zone "$center_window" "center"
    
    # After positioning, store the TARGET zones (what we just set them to)
    WINDOW_ZONES["$left_window"]="left"
    WINDOW_ZONES["$center_window"]="center"
    WINDOW_ZONES["$right_window"]="right"
    CURRENT_LAYOUT="triple"
}

apply_default_layout() {
    log "Applying default layout (4+ windows)"
    reset_gaps
    WINDOW_ZONES=()
    CURRENT_LAYOUT="default"
}

# Track last tiled window count to detect actual changes
LAST_TILED_COUNT=""
LAST_TILED_ADDRESSES=""

get_tiled_window_info() {
    local windows
    windows=$(get_tiled_windows)
    local count
    count=$(echo "$windows" | jq 'length')
    local addresses
    addresses=$(echo "$windows" | jq -r '[.[].address] | sort | join(",")')
    echo "$count:$addresses"
}

# === MAIN LAYOUT LOGIC ===
evaluate_layout() {
    # Prevent re-entry while layout is settling (but auto-expire after 7 seconds)
    if [[ -f "$SETTLING_FILE" ]]; then
        local file_age
        file_age=$(( $(date +%s) - $(stat -c %Y "$SETTLING_FILE" 2>/dev/null || echo 0) ))
        if [[ $file_age -lt 7 ]]; then
            debug "Layout settling, skipping evaluation"
            return
        else
            debug "Settling file stale ($file_age sec), removing"
            rm -f "$SETTLING_FILE"
        fi
    fi
    
    if ! is_on_target_monitor; then
        debug "Not on target monitor, skipping"
        return
    fi
    
    local count
    count=$(get_window_count)
    
    local current_info
    current_info=$(get_tiled_window_info)
    local current_addresses
    current_addresses="${current_info#*:}"
    
    # Determine expected layout for this window count
    local expected_layout=""
    case $count in
        0) expected_layout="" ;;
        1) expected_layout="single" ;;
        2) expected_layout="dual-left" ;; # or dual-right, but we check prefix
        3) expected_layout="triple" ;;
        *) expected_layout="default" ;;
    esac
    
    # Skip if layout type matches and window addresses haven't changed
    # For dual layouts, check prefix since it can be dual-left or dual-right
    local dominated_layout="${CURRENT_LAYOUT%-*}"  # Remove -left/-right suffix
    local expected_prefix="${expected_layout%-*}"
    
    if [[ "$current_addresses" == "$LAST_TILED_ADDRESSES" && -n "$LAST_TILED_ADDRESSES" ]]; then
        if [[ "$dominated_layout" == "$expected_prefix" || "$CURRENT_LAYOUT" == "$expected_layout" ]]; then
            debug "Layout unchanged (count=$count, layout=$CURRENT_LAYOUT, zones=${#WINDOW_ZONES[@]}), skipping"
            # Ensure WINDOW_ZONES is populated for drag detection (it may have been cleared by focusedmon etc)
            if [[ ${#WINDOW_ZONES[@]} -eq 0 && $count -gt 0 && $count -le 3 ]]; then
                debug "Repopulating WINDOW_ZONES from current positions"
                local windows
                windows=$(get_tiled_windows)
                local addr zone
                while IFS= read -r addr; do
                    zone=$(get_window_zone "$addr")
                    WINDOW_ZONES["$addr"]="$zone"
                done < <(echo "$windows" | jq -r '.[].address')
            fi
            return
        fi
    fi
    
    debug "Evaluating layout: $count windows, current layout: $CURRENT_LAYOUT"
    log_windows
    
    # Update tracking
    LAST_TILED_COUNT="$count"
    LAST_TILED_ADDRESSES="$current_addresses"
    
    # Set settling flag to prevent re-entry during layout
    touch "$SETTLING_FILE"
    
    case $count in
        0)
            reset_gaps
            WINDOW_ZONES=()
            CURRENT_LAYOUT=""
            ;;
        1)
            apply_single_window_layout
            ;;
        2)
            apply_dual_window_layout
            ;;
        3)
            apply_triple_window_layout
            ;;
        *)
            apply_default_layout
            ;;
    esac
    
    # Update position tracking AFTER layout so we don't detect our own changes
    LAST_WINDOW_POSITIONS=$(get_window_positions_hash)
    
    # Clear settling flag
    rm -f "$SETTLING_FILE"
}

# Debounced layout evaluation to handle rapid events
# NOTE: evaluate_layout is called directly (not in subshell) so variables are preserved
evaluate_layout_debounced() {
    local delay=${1:-150}
    
    # Kill any pending evaluation timer
    if [[ -n "$DEBOUNCE_PID" ]] && kill -0 "$DEBOUNCE_PID" 2>/dev/null; then
        kill "$DEBOUNCE_PID" 2>/dev/null || true
    fi
    
    # Write a trigger file after the delay; the event loop will pick it up
    (
        sleep "0.${delay}"
        touch "/tmp/ultrawide_manager.trigger"
    ) &
    DEBOUNCE_PID=$!
}

# === EVENT HANDLERS ===
handle_open_window() {
    local window_addr=$1
    debug "Window opened: $window_addr"
    
    # Check if this is a floating window - if so, ignore
    local is_floating
    is_floating=$(hyprctl clients -j 2>/dev/null | jq -r ".[] | select(.address == \"$window_addr\") | .floating")
    
    if [[ "$is_floating" == "true" ]]; then
        debug "Ignoring floating window: $window_addr"
        return
    fi
    
    evaluate_layout_debounced 200
}

handle_close_window() {
    local window_addr=$1
    debug "Window closed: $window_addr"
    
    # Clean up tracking
    unset "WINDOW_ZONES[$window_addr]" 2>/dev/null || true
    
    # Only re-evaluate if this was a tracked (tiled) window
    # Since window is closed, we can't check if it was floating
    # But evaluate_layout will skip if nothing changed
    evaluate_layout_debounced 150
}

handle_move_window() {
    local event_data=$1
    debug "Window moved: $event_data"
    
    # Re-evaluate after move completes
    evaluate_layout_debounced 300
}

handle_workspace_change() {
    debug "Workspace changed"
    
    # Reset state and re-evaluate
    WINDOW_ZONES=()
    evaluate_layout_debounced 100
}

handle_floating_change() {
    local window_addr=$1
    debug "Floating mode changed: $window_addr"
    
    # Clean up if window became floating
    unset "WINDOW_ZONES[$window_addr]" 2>/dev/null || true
    
    # Force re-evaluation even if addresses haven't changed: when a window goes
    # float→tile, dwindle resets sizes to 50/50, so the layout must be re-applied
    LAST_TILED_ADDRESSES=""
    
    evaluate_layout_debounced 200
}

handle_urgent() {
    # Re-apply current layout to fix any drift
    evaluate_layout_debounced 100
}

# Track last known window positions to detect drags
LAST_WINDOW_POSITIONS=""

get_window_positions_hash() {
    local windows
    windows=$(get_tiled_windows)
    # Create a simple hash of window positions
    echo "$windows" | jq -r '[.[] | "\(.address):\(.at[0])"] | sort | join(",")'
}

save_positions_to_file() {
    local positions
    positions=$(get_window_positions_hash)
    echo "$positions" > "$STATE_FILE"
}

load_positions_from_file() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo ""
    fi
}

handle_focus_change() {
    debug "focus_change called: CURRENT_LAYOUT='$CURRENT_LAYOUT' settling=$([ -f "$SETTLING_FILE" ] && echo yes || echo no)"
    # Skip if we're in settling period
    if [[ -f "$SETTLING_FILE" ]]; then
        local file_age
        file_age=$(( $(date +%s) - $(stat -c %Y "$SETTLING_FILE" 2>/dev/null || echo 0) ))
        if [[ $file_age -lt 7 ]]; then
            debug "focus_change: skipping (settling, age=${file_age}s)"
            return
        fi
    fi
    
    if ! is_on_target_monitor; then
        debug "focus_change: skipping (not on target monitor)"
        return
    fi
    
    local count
    count=$(get_window_count)
    if [[ $count -lt 1 || $count -gt 3 ]]; then
        return
    fi
    
    # Only check if we have an established layout
    if [[ -z "$CURRENT_LAYOUT" ]]; then
        return
    fi
    
    # Check if any window is out of its expected position
    # If so, user dragged something - re-apply layout
    local needs_relayout=false
    
    case "$CURRENT_LAYOUT" in
        triple)
            local windows sorted_windows
            windows=$(get_tiled_windows)
            local actual_count
            actual_count=$(echo "$windows" | jq 'length')
            if [[ $actual_count -ne 3 ]]; then
                debug "focus_change: layout=triple but actual tiled count=$actual_count, skipping"
                return
            fi
            sorted_windows=$(echo "$windows" | jq 'sort_by(.at[0])')
            local w0 w1 w2
            w0=$(echo "$sorted_windows" | jq -r '.[0].address')
            w1=$(echo "$sorted_windows" | jq -r '.[1].address')
            w2=$(echo "$sorted_windows" | jq -r '.[2].address')
            local lg cg rg lx ly lw lh cx cy cw ch rx ry rw rh
            lg=$(get_zone_geometry "left");   read lx ly lw lh <<< "$lg"
            cg=$(get_zone_geometry "center"); read cx cy cw ch <<< "$cg"
            rg=$(get_zone_geometry "right");  read rx ry rw rh <<< "$rg"
            debug "focus_change triple: w0=$w0 vs left(x=$lx,w=$lw), w1=$w1 vs center(x=$cx,w=$cw), w2=$w2 vs right(x=$rx,w=$rw)"
            if ! is_window_correct "$w0" "$lx" "$ly" "$lw" "$lh" || \
               ! is_window_correct "$w1" "$cx" "$cy" "$cw" "$ch" || \
               ! is_window_correct "$w2" "$rx" "$ry" "$rw" "$rh"; then
                needs_relayout=true
            fi
            ;;
        dual-left|dual-right)
            local windows sorted_windows
            windows=$(get_tiled_windows)
            local actual_count
            actual_count=$(echo "$windows" | jq 'length')
            if [[ $actual_count -ne 2 ]]; then
                debug "focus_change: layout=$CURRENT_LAYOUT but actual tiled count=$actual_count, skipping"
                return
            fi
            sorted_windows=$(echo "$windows" | jq 'sort_by(.at[0])')
            local w0 w1
            w0=$(echo "$sorted_windows" | jq -r '.[0].address')
            w1=$(echo "$sorted_windows" | jq -r '.[1].address')
            local side="${CURRENT_LAYOUT#dual-}"
            local z1 z2
            [[ "$side" == "left" ]] && z1="left" && z2="center" || z1="center" && z2="right"
            local g1 g2 x1 y1 ww1 h1 x2 y2 ww2 h2
            g1=$(get_zone_geometry "$z1"); read x1 y1 ww1 h1 <<< "$g1"
            g2=$(get_zone_geometry "$z2"); read x2 y2 ww2 h2 <<< "$g2"
            debug "focus_change $CURRENT_LAYOUT: w0=$w0 vs $z1(x=$x1,w=$ww1), w1=$w1 vs $z2(x=$x2,w=$ww2)"
            if ! is_window_correct "$w0" "$x1" "$y1" "$ww1" "$h1" || \
               ! is_window_correct "$w1" "$x2" "$y2" "$ww2" "$h2"; then
                needs_relayout=true
            fi
            ;;
        single)
            return
            ;;
    esac
    
    if [[ "$needs_relayout" == "true" ]]; then
        debug "Window out of position detected, re-applying layout"
        CURRENT_LAYOUT=""
        LAST_TILED_ADDRESSES=""
        evaluate_layout_debounced 200
    fi
}

# === MANUAL CONTROLS (can be called via hyprctl dispatch exec) ===
# These allow manual override of window placement

cmd_move_to_center() {
    local window_addr
    window_addr=$(get_focused_window)
    if [[ -n "$window_addr" ]]; then
        WINDOW_ZONES["$window_addr"]="center"
        evaluate_layout
    fi
}

cmd_move_to_left() {
    local window_addr
    window_addr=$(get_focused_window)
    if [[ -n "$window_addr" ]]; then
        WINDOW_ZONES["$window_addr"]="left"
        evaluate_layout
    fi
}

cmd_move_to_right() {
    local window_addr
    window_addr=$(get_focused_window)
    if [[ -n "$window_addr" ]]; then
        WINDOW_ZONES["$window_addr"]="right"
        evaluate_layout
    fi
}

cmd_swap_sides() {
    local count
    count=$(get_window_count)
    
    if [[ $count -eq 2 ]]; then
        if [[ "$CURRENT_LAYOUT" == "dual-left" ]]; then
            apply_dual_window_layout "right"
        else
            apply_dual_window_layout "left"
        fi
    fi
}

cmd_refresh() {
    log "Manual refresh triggered"
    WINDOW_ZONES=()
    evaluate_layout
}

# === EVENT LOOP ===
process_event() {
    local line=$1
    local event_type event_data
    
    # Parse event (format: EVENT>>DATA or EVENT>DATA)
    if [[ "$line" == *">>"* ]]; then
        event_type="${line%%>>*}"
        event_data="${line#*>>}"
    else
        event_type="${line%%>*}"
        event_data="${line#*>}"
    fi
    
    debug "Event: $event_type >> $event_data"
    
    case "$event_type" in
        openwindow)
            local window_addr
            window_addr=$(echo "$event_data" | cut -d',' -f1)
            handle_open_window "0x$window_addr"
            ;;
        closewindow)
            handle_close_window "0x$event_data"
            ;;
        movewindow|movewindowv2)
            handle_move_window "$event_data"
            ;;
        workspace|workspacev2)
            handle_workspace_change
            ;;
        changefloatingmode)
            local window_addr
            window_addr=$(echo "$event_data" | cut -d',' -f1)
            handle_floating_change "0x$window_addr"
            ;;
        focusedmon)
            # Monitor focus changed - just re-evaluate, don't reset state
            # (workspace/workspacev2 handles actual workspace switches on target monitor)
            evaluate_layout_debounced 100
            ;;
        activewindow|activewindowv2)
            handle_focus_change
            ;;
        urgent)
            handle_urgent
            ;;
        layoutchange)
            # Layout changed within workspace (not always fired but worth catching)
            debug "Layout change detected"
            evaluate_layout_debounced 200
            ;;
    esac
}

# === COMMAND LINE INTERFACE ===
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat <<EOF
Hyprland Ultra-wide Window Manager v2

Usage: $0 [command]

Commands:
  (none)     Start the window manager daemon
  refresh    Force refresh the current layout
  center     Move focused window to center zone
  left       Move focused window to left zone
  right      Move focused window to right zone
  swap       Swap the side panel position (for 2-window layouts)
  status     Show current status and recent log
  windows    Show current window positions (alias: w)
  log        Follow the log file in real-time
  kill       Kill the running instance
  unlock     Kill running instance and clear all lock/temp files

Environment:
  DEBUG=1    Enable debug output (default: on)
  DEBUG=0    Disable debug output

Log file: /tmp/ultrawide_manager.log

EOF
    exit 0
fi

case "${1:-}" in
    refresh)
        cmd_refresh
        exit 0
        ;;
    center)
        cmd_move_to_center
        exit 0
        ;;
    left)
        cmd_move_to_left
        exit 0
        ;;
    right)
        cmd_move_to_right
        exit 0
        ;;
    swap)
        cmd_swap_sides
        exit 0
        ;;
    status)
        echo "Current layout: $CURRENT_LAYOUT"
        echo "Window zones:"
        for addr in "${!WINDOW_ZONES[@]}"; do
            echo "  $addr -> ${WINDOW_ZONES[$addr]}"
        done
        echo ""
        echo "Recent log:"
        tail -30 /tmp/ultrawide_manager.log 2>/dev/null || echo "(no log yet)"
        exit 0
        ;;
    windows|w)
        # Quick window dump without needing the daemon running
        workspace=$(hyprctl monitors -j | jq -r ".[] | select(.description == \"$MONITOR_DESC\") | .activeWorkspace.id")
        if [[ -n "$workspace" ]]; then
            echo "=== Windows on workspace $workspace ==="
            all=$(hyprctl clients -j)
            tiled=$(echo "$all" | jq "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == false)]")
            floating=$(echo "$all" | jq "[.[] | select(.workspace.id == $workspace and .mapped == true and .floating == true)]")
            
            tiled_count=$(echo "$tiled" | jq 'length')
            floating_count=$(echo "$floating" | jq 'length')
            
            echo "Tiled: $tiled_count | Floating: $floating_count"
            echo ""
            echo "--- Tiled ---"
            echo "$tiled" | jq -r '.[] | "\(.address) | \(.class[0:20]) | pos:(\(.at[0]),\(.at[1])) | size:\(.size[0])x\(.size[1])"'
            echo ""
            echo "--- Floating ---"
            echo "$floating" | jq -r '.[] | "\(.address) | \(.class[0:20]) | pos:(\(.at[0]),\(.at[1])) | size:\(.size[0])x\(.size[1])"'
        else
            echo "Target monitor not found"
        fi
        exit 0
        ;;
    log|logs)
        tail -f /tmp/ultrawide_manager.log
        exit 0
        ;;
    kill)
        LOCK_FILE="/tmp/ultrawide_manager.lock"
        if [[ -s "$LOCK_FILE" ]]; then
            existing_pid=$(cat "$LOCK_FILE" 2>/dev/null)
            if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
                echo "Killing running instance (PID: $existing_pid)..."
                kill "$existing_pid"
            else
                echo "No running instance found (stale lock)"
            fi
        else
            echo "No lock file found"
        fi
        exit 0
        ;;
    unlock)
        LOCK_FILE="/tmp/ultrawide_manager.lock"
        if [[ -s "$LOCK_FILE" ]]; then
            existing_pid=$(cat "$LOCK_FILE" 2>/dev/null)
            if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
                echo "Killing running instance (PID: $existing_pid)..."
                kill "$existing_pid"
                sleep 0.5
            else
                echo "No running instance found (stale lock)"
            fi
        else
            echo "No lock file found"
        fi
        rm -f /tmp/ultrawide_manager.lock \
              /tmp/ultrawide_manager.settling \
              /tmp/ultrawide_manager.fifo \
              /tmp/ultrawide_manager.trigger
        echo "Cleared all lock/temp files"
        exit 0
        ;;
esac

# === MAIN ===
LOCK_FILE="/tmp/ultrawide_manager.lock"

# Use flock for atomic locking
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
    echo "Another instance is already running (lock held)"
    exit 1
fi

# Double-check: if there's a PID in the lock file and it's running, exit
if [[ -s "$LOCK_FILE" ]]; then
    existing_pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [[ -n "$existing_pid" && "$existing_pid" != "$$" ]] && kill -0 "$existing_pid" 2>/dev/null; then
        echo "Another instance is already running (PID: $existing_pid)"
        exit 1
    fi
fi

main() {
    # Write our PID to lock file (for informational purposes)
    echo $$ > "$LOCK_FILE"
    
    # Clear any stale settling file
    rm -f "$SETTLING_FILE"
    
    # Clear log on start
    echo "=== Ultrawide Manager v2 Started $(date) ===" > "$LOG_FILE"
    
    log "Starting Hyprland Ultra-wide Window Manager v2 (PID: $$)"
    log "Target monitor: $MONITOR_DESC"
    log "Resolution: ${MONITOR_WIDTH}x${MONITOR_HEIGHT}"
    log "Zones: LEFT=${LEFT_ZONE_PCT}% CENTER=${CENTER_ZONE_PCT}% RIGHT=${RIGHT_ZONE_PCT}%"
    log "Zone widths: L=${LEFT_ZONE_WIDTH}px C=${CENTER_ZONE_WIDTH}px R=${RIGHT_ZONE_WIDTH}px"
    
    # Initial layout evaluation
    LAST_WINDOW_POSITIONS=$(get_window_positions_hash)
    evaluate_layout
    
    log "Listening for Hyprland events..."
    
    # Connect to Hyprland socket
    local socket_path="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
    
    if [[ ! -S "$socket_path" ]]; then
        log "ERROR: Hyprland socket not found at $socket_path"
        exit 1
    fi
    
    # Use a temp fifo to avoid subshell (pipe | while creates subshell, losing variable writes)
    local FIFO="/tmp/ultrawide_manager.fifo"
    rm -f "$FIFO"
    mkfifo "$FIFO"
    
    socat -U - "UNIX-CONNECT:$socket_path" > "$FIFO" &
    local SOCAT_PID=$!
    
    local TRIGGER_FILE="/tmp/ultrawide_manager.trigger"
    rm -f "$TRIGGER_FILE"
    
    # Main event loop - reads from fifo directly in main shell so variables are preserved
    while read -r line; do
        # Check for pending debounced evaluation
        if [[ -f "$TRIGGER_FILE" ]]; then
            rm -f "$TRIGGER_FILE"
            evaluate_layout
        fi
        process_event "$line"
    done < "$FIFO"
    
    kill "$SOCAT_PID" 2>/dev/null || true
    rm -f "$FIFO"
}

# Cleanup on exit
cleanup() {
    if [[ -n "$DEBOUNCE_PID" ]] && kill -0 "$DEBOUNCE_PID" 2>/dev/null; then
        kill "$DEBOUNCE_PID" 2>/dev/null || true
    fi
    rm -f "$LOCK_FILE"
    rm -f "$SETTLING_FILE"
    rm -f "/tmp/ultrawide_manager.fifo"
    rm -f "/tmp/ultrawide_manager.trigger"
    log "Shutting down"
}
trap cleanup EXIT

main
