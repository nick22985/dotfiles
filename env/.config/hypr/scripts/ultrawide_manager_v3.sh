#!/usr/bin/env bash

set -uo pipefail

GAPS_IN=${ULTRAWIDE_GAPS_IN:-5}
GAPS_OUT=${ULTRAWIDE_GAPS_OUT:-20}
BORDER=0

MONITOR_DESC_PREFIX="${ULTRAWIDE_MONITOR_DESC_PREFIX:-Samsung Electric Company Odyssey G95NC}"

FRAC_LEFT=0.25
FRAC_RIGHT=0.75

MOVE_CANDIDATES=(
    'hl.dsp.window.swap({ direction = "%s" })'
    'swapwindow %s'
    'hl.dsp.swapwindow("%s")'
    'hl.dsp.window.move({ direction = "%s" })'
    'movewindow %s'
)

MOVE_DISPATCH_FMT=''
[[ -n "${ULTRAWIDE_MOVE_DISPATCH:-}" ]] && MOVE_DISPATCH_FMT="$ULTRAWIDE_MOVE_DISPATCH"

RESIZE_SIGN_LEFT="${ULTRAWIDE_RESIZE_SIGN_LEFT:-1}"
RESIZE_SIGN_RIGHT="${ULTRAWIDE_RESIZE_SIGN_RIGHT:--1}"

HANDLED_EVENT_RE='^(openwindow|closewindow|movewindowv2|changefloatingmode|workspacev2|fullscreen|configreloaded|monitoradded|monitoraddedv2|monitorremoved|monitorremovedv2|openlayer|closelayer)>>'

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/ultrawide"
FIFO="$RUNTIME_DIR/cmd.fifo"
LOCK_FILE="$RUNTIME_DIR/daemon.lock"
SIDE_FILE="$RUNTIME_DIR/side"
LOG_FILE="${ULTRAWIDE_LOG:-$HOME/.cache/ultrawide_manager_v3.log}"

BURST_DRAIN_SECS=${ULTRAWIDE_BURST_DRAIN:-0.08}

DRAG_BIND="${ULTRAWIDE_DRAG_BIND-SUPER, mouse:272}"
SELF="$(readlink -f "${BASH_SOURCE[0]}")"

SIDE="${ULTRAWIDE_SIDE:-right}"

publish_side() {
    mkdir -p "$RUNTIME_DIR" 2>/dev/null
    printf '%s\n' "$SIDE" >"$SIDE_FILE" 2>/dev/null
}

PREV_LEFT=""
PREV_CENTER=""
PREV_RIGHT=""

PREV_GEOM=""

LAST_GAPS=""

SETTLE_POLLS=${ULTRAWIDE_SETTLE_POLLS:-15}
SETTLE_INTERVAL=${ULTRAWIDE_SETTLE_INTERVAL:-0.02}

APPLY_DEPTH=0
APPLY_MAX_ROUNDS=3

log() {
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

read_monitor() {
    hyprctl monitors -j 2>/dev/null | jq -r --arg p "$MONITOR_DESC_PREFIX" '
        [ .[] | select((.description // "") | startswith($p)) ] | .[0] // empty
        | [ .name, .description, .x, .y, .width, .height, .scale, (.transform // 0),
            .reserved[0], .reserved[1], .reserved[2], .reserved[3],
            .activeWorkspace.id, .activeWorkspace.name ]
        | @tsv'
}

read_windows() {
    local ws_id=$1
    hyprctl clients -j 2>/dev/null | jq -r --argjson ws "$ws_id" '
        [ .[]
          | select(.workspace.id == $ws)
          | select(.mapped)
          | select((.hidden // false) | not)
          | select((.floating // false) | not)
        ]
        | sort_by(.at[0]) | .[]
        | [ .address, .at[0], .at[1], .size[0], .size[1],
            (if (.fullscreen // 0) == 0 or (.fullscreen // 0) == false then 0 else 1 end) ]
        | @tsv'
}

layout_signature() {
    local a wx wy ww rest out=""
    while IFS=$'\t' read -r a wx wy ww rest; do
        [[ -n "$a" ]] && out="${out}${a}:${wx}:${ww} "
    done < <(read_windows "$1")
    printf '%s\n' "$out"
}

settle_layout() {
    local ws_id=$1 before=$2 i
    for ((i = 0; i < SETTLE_POLLS; i++)); do
        sleep "$SETTLE_INTERVAL"
        [[ "$(layout_signature "$ws_id")" != "$before" ]] && return 0
    done
    log "settle: no layout change after $(awk -v p="$SETTLE_POLLS" -v i="$SETTLE_INTERVAL" \
        'BEGIN { printf "%.0f", p * i * 1000 }')ms"
    return 1
}

focused_address() {
    hyprctl activewindow -j 2>/dev/null | jq -r '.address // empty'
}

usable_box() {
    local x=$1 y=$2 w=$3 h=$4 scale=$5 transform=$6 rl=$7 rt=$8 rr=$9 rb=${10}
    awk -v x="$x" -v y="$y" -v w="$w" -v h="$h" -v s="$scale" -v t="$transform" \
        -v rl="$rl" -v rt="$rt" -v rr="$rr" -v rb="$rb" '
        BEGIN {
            if (s <= 0) s = 1
            lw = w / s; lh = h / s
            if (t % 2 == 1) { tmp = lw; lw = lh; lh = tmp }
            printf "%d %d %d %d\n", x + rl, y + rt, lw - rl - rr, lh - rt - rb
        }'
}

read_border() {
    local raw
    raw=$(hyprctl getoption general:border_size 2>/dev/null) || return 0
    raw=$(sed -n 's/^int:[[:space:]]*\([0-9]\+\).*/\1/p' <<<"$raw" | head -1)
    [[ -n "$raw" ]] && BORDER=$raw
    return 0
}

frac_px() {
    awk -v uw="$1" -v f="$2" 'BEGIN { printf "%d\n", int(uw * f + 0.5) }'
}

send_batch() {
    (($# == 0)) && return 0

    local cmd joined out
    for cmd in "$@"; do
        if [[ "$cmd" == *";"* ]]; then
            log "apply: refusing batch, ';' in: $cmd"
            return 1
        fi
    done

    printf -v joined '%s ; ' "$@"
    joined="${joined% ; }"

    out=$(hyprctl --batch "$joined" 2>&1)
    if [[ "$out" == *[Ii]nvalid* || "$out" == *[Uu]nknown* || "$out" == *rror* ]]; then
        log "apply: hyprctl rejected something: $out"
        log "apply: batch was: $joined"
    fi
    return 0
}

apply() {
    local force="${1:-}"
    local mon
    mon=$(read_monitor)
    if [[ -z "$mon" ]]; then
        return 0
    fi

    local m_name m_desc m_x m_y m_w m_h m_scale m_tf rl rt rr rb ws_id ws_name
    IFS=$'\t' read -r m_name m_desc m_x m_y m_w m_h m_scale m_tf \
        rl rt rr rb ws_id ws_name <<<"$mon"

    if [[ "$ws_name" == special:* ]]; then
        return 0
    fi

    read_border

    local geom="${m_w}x${m_h}@${m_scale}/${m_tf} r=${rl},${rt},${rr},${rb}"
    if [[ -n "$PREV_GEOM" && "$geom" != "$PREV_GEOM" ]]; then
        log "geometry changed: $PREV_GEOM -> $geom; forcing a full re-apply"
        force=force
        LAST_GAPS=""
    fi
    PREV_GEOM="$geom"

    local ux uy uw uh
    read -r ux uy uw uh <<<"$(usable_box "$m_x" "$m_y" "$m_w" "$m_h" "$m_scale" "$m_tf" "$rl" "$rt" "$rr" "$rb")"
    if ((uw <= 0 || uh <= 0)); then
        log "apply: nonsensical usable box ${uw}x${uh}, skipping"
        return 0
    fi

    local -a addrs=() heights=() widths=() xs=()
    local a wx wy ww wh fs
    local any_fullscreen=0
    while IFS=$'\t' read -r a wx wy ww wh fs; do
        [[ -z "$a" ]] && continue
        ((fs != 0)) && any_fullscreen=1
        addrs+=("$a"); heights+=("$wh"); widths+=("$ww"); xs+=("$wx")
    done < <(read_windows "$ws_id")

    if ((any_fullscreen)); then
        return 0
    fi

    local n=${#addrs[@]}

    if ((n == 2)) && [[ -n "$PREV_LEFT" && -n "$PREV_CENTER" && -n "$PREV_RIGHT" ]]; then
        local have_pl=0 have_pc=0 have_pr=0
        for a in "${addrs[@]}"; do
            [[ "$a" == "$PREV_LEFT" ]] && have_pl=1
            [[ "$a" == "$PREV_CENTER" ]] && have_pc=1
            [[ "$a" == "$PREV_RIGHT" ]] && have_pr=1
        done
        if ((have_pl && have_pc && !have_pr)); then
            set_side left
        elif ((have_pc && have_pr && !have_pl)); then
            set_side right
        fi
    fi

    local cur_left="" cur_center="" cur_right=""
    local gap_l=$GAPS_OUT gap_r=$GAPS_OUT
    local empty_gap
    empty_gap=$(( $(frac_px "$uw" "$FRAC_LEFT") + GAPS_IN ))

    case $n in
        0)
            : ;;
        1)
            cur_center="${addrs[0]}"
            gap_l=$empty_gap; gap_r=$empty_gap ;;
        2)
            if [[ "$SIDE" == "left" ]]; then
                cur_left="${addrs[0]}"; cur_center="${addrs[1]}"
                gap_r=$empty_gap
            else
                cur_center="${addrs[0]}"; cur_right="${addrs[1]}"
                gap_l=$empty_gap
            fi ;;
        3)
            cur_left="${addrs[0]}"; cur_center="${addrs[1]}"; cur_right="${addrs[2]}" ;;
        *)
            : ;;
    esac

    local gaps_changed=0

    local gaps_match=0
    if ((n > 0)); then
        local obs_l=$(( xs[0] - ux - BORDER ))
        local obs_r=$(( (ux + uw) - (xs[n - 1] + widths[n - 1] + BORDER) ))
        local dl=$(( obs_l - gap_l )) dr=$(( obs_r - gap_r ))
        ((dl < 0)) && dl=$(( -dl ))
        ((dr < 0)) && dr=$(( -dr ))
        ((dl <= 2 && dr <= 2)) && gaps_match=1
    fi

    local gaps_key="${ws_id}:${gap_l}:${gap_r}"
    if ((gaps_match)); then
        LAST_GAPS="$gaps_key"
    fi
    if [[ "$gaps_key" != "$LAST_GAPS" ]]; then
        gaps_changed=1
        local sig_before
        sig_before=$(layout_signature "$ws_id")
        send_batch "eval hl.workspace_rule({ workspace = \"${ws_name}\", monitor = \"desc:${m_desc}\", gaps_out = { top = ${GAPS_OUT}, right = ${gap_r}, bottom = ${GAPS_OUT}, left = ${gap_l} } })" || return 1
        LAST_GAPS="$gaps_key"

        settle_layout "$ws_id" "$sig_before" || true

        local -a re_addrs=() re_heights=() re_widths=()
        while IFS=$'\t' read -r a wx wy ww wh fs; do
            [[ -z "$a" ]] && continue
            re_addrs+=("$a"); re_heights+=("$wh"); re_widths+=("$ww")
        done < <(read_windows "$ws_id")
        if [[ "${re_addrs[*]:-}" != "${addrs[*]:-}" ]]; then
            log "apply: window set changed while the gap rule was landing" \
                "(${#addrs[@]} -> ${#re_addrs[@]}); leaving it to the next pass"
            return 0
        fi
        heights=("${re_heights[@]:-}"); widths=("${re_widths[@]:-}")
    fi

    local b25 b75 content_left content_right
    b25=$(( ux + $(frac_px "$uw" "$FRAC_LEFT") ))
    b75=$(( ux + $(frac_px "$uw" "$FRAC_RIGHT") ))
    content_left=$(( ux + gap_l + BORDER ))
    content_right=$(( ux + uw - gap_r - BORDER ))

    local expected_h=$(( uh - 2 * (GAPS_OUT + BORDER) ))
    local -a resizes=()

    local enforce_all=0
    [[ "$force" == "force" ]] && enforce_all=1
    ((gaps_changed)) && enforce_all=1

    if [[ -n "$cur_left" ]]; then
        if ((enforce_all)) || [[ "$cur_left" != "$PREV_LEFT" || "$cur_center" != "$PREV_CENTER" ]]; then
            add_boundary_resize resizes "$cur_left" $(( (b25 - GAPS_IN - BORDER) - content_left )) \
                "${widths[0]}" "$RESIZE_SIGN_LEFT" "${heights[0]}" "$expected_h" "left|center"
        fi
    fi
    if [[ -n "$cur_right" ]]; then
        if ((enforce_all)) || [[ "$cur_right" != "$PREV_RIGHT" || "$cur_center" != "$PREV_CENTER" ]]; then
            add_boundary_resize resizes "$cur_right" $(( content_right - (b75 + GAPS_IN + BORDER) )) \
                "${widths[$((n - 1))]}" "$RESIZE_SIGN_RIGHT" "${heights[$((n - 1))]}" "$expected_h" "center|right"
        fi
    fi

    local emitted_resizes=${#resizes[@]}

    PREV_LEFT="$cur_left"; PREV_CENTER="$cur_center"; PREV_RIGHT="$cur_right"

    if ((emitted_resizes > 0)); then
        local sig_before
        sig_before=$(layout_signature "$ws_id")
        send_batch "${resizes[@]}" || return 1
        settle_layout "$ws_id" "$sig_before" || true
    fi

    if ((emitted_resizes > 0 || gaps_changed)); then
        if ((APPLY_DEPTH < APPLY_MAX_ROUNDS)); then
            ((APPLY_DEPTH++))
            apply force
            ((APPLY_DEPTH--))
        else
            log "apply: still emitting resizes after $APPLY_MAX_ROUNDS rounds; giving up this pass"
        fi
    fi
}

add_boundary_resize() {
    local -n out=$1
    local addr=$2 width=$3 cur_width=$4 sign=$5 height=$6 expected_h=$7 label=$8

    if ((width < 100)); then
        log "boundary $label: computed width $width is implausible, skipping"
        return 0
    fi
    local diff=$(( height - expected_h ))
    ((diff < 0)) && diff=$(( -diff ))
    if ((diff > 4)); then
        log "boundary $label: owner $addr is ${height}px tall, expected ${expected_h}px" \
            "(window is inside a split); skipping"
        return 0
    fi

    local dx=$(( sign * (width - cur_width) ))
    ((dx == 0)) && return 0

    log "boundary $label: $addr ${cur_width}px -> ${width}px (dx ${dx}, sign ${sign})"
    out+=("dispatch hl.dsp.window.resize({ x = ${dx}, y = 0, relative = true, window = \"address:${addr}\" })")
}

set_side() {
    [[ "$SIDE" == "$1" ]] && return 0
    SIDE="$1"
    publish_side
    log "side: SIDE=$SIDE"
    LAST_GAPS=""
}

cmd_swap() {
    if [[ "$SIDE" == "left" ]]; then set_side right; else set_side left; fi
    apply force
}

slot_of() {
    local ws_id=$1 addr=$2 a rest i=0
    while IFS=$'\t' read -r a rest; do
        [[ -z "$a" ]] && continue
        [[ "$a" == "$addr" ]] && { printf '%s\n' "$i"; return 0; }
        ((i++))
    done < <(read_windows "$ws_id")
    printf '%s\n' "-1"
}

move_one_step() {
    local ws_id=$1 addr=$2 dir=$3
    local want before after sig fmt
    before=$(slot_of "$ws_id" "$addr")
    ((before < 0)) && return 1
    if [[ "$dir" == "r" ]]; then want=$(( before + 1 )); else want=$(( before - 1 )); fi

    local -a cands=()
    [[ -n "$MOVE_DISPATCH_FMT" ]] && cands=("$MOVE_DISPATCH_FMT")
    cands+=("${MOVE_CANDIDATES[@]}")

    for fmt in "${cands[@]}"; do
        sig=$(layout_signature "$ws_id")
        send_batch "dispatch $(printf "$fmt" "$dir")" || continue
        settle_layout "$ws_id" "$sig" || true
        after=$(slot_of "$ws_id" "$addr")

        if ((after == want)); then
            if [[ "$MOVE_DISPATCH_FMT" != "$fmt" ]]; then
                MOVE_DISPATCH_FMT="$fmt"
                log "move: using dispatcher '$fmt'"
            fi
            return 0
        fi
        if ((after < 0)); then
            log "move: '$fmt' removed $addr from workspace $ws_id; aborting"
            return 1
        fi
        ((after != before)) && log "move: '$fmt' put $addr at slot $after, wanted $want"
    done

    log "move: no dispatcher moved $addr from slot $before ($dir);" \
        "tried ${#cands[@]} forms -- pin one with \$ULTRAWIDE_MOVE_DISPATCH"
    return 1
}

cmd_move_zone() {
    local target=$1
    local mon
    mon=$(read_monitor) || return 0
    [[ -z "$mon" ]] && return 0

    local _n _d _x _y _w _h _s _t _rl _rt _rr _rb ws_id ws_name
    IFS=$'\t' read -r _n _d _x _y _w _h _s _t _rl _rt _rr _rb ws_id ws_name <<<"$mon"

    local focused
    focused=$(focused_address)
    [[ -z "$focused" ]] && return 0

    local -a addrs=()
    local a rest
    while IFS=$'\t' read -r a rest; do
        [[ -n "$a" ]] && addrs+=("$a")
    done < <(read_windows "$ws_id")

    local n=${#addrs[@]}
    ((n < 2 || n > 3)) && return 0

    local from=-1 i
    for i in "${!addrs[@]}"; do
        [[ "${addrs[$i]}" == "$focused" ]] && from=$i
    done
    ((from < 0)) && return 0

    local to
    case "$n:$SIDE:$target" in
        2:right:center) to=0 ;;
        2:right:right)  to=1 ;;
        2:right:left)   set_side left;  to=0 ;;
        2:left:left)    to=0 ;;
        2:left:center)  to=1 ;;
        2:left:right)   set_side right; to=1 ;;
        3:*:left)       to=0 ;;
        3:*:center)     to=1 ;;
        3:*:right)      to=2 ;;
        *)              return 0 ;;
    esac

    if ((from == to)); then
        apply force
        return 0
    fi

    local dir="r" steps=$(( to - from ))
    if ((steps < 0)); then dir="l"; steps=$(( -steps )); fi
    log "move: $focused to $target (slot $from -> $to), $steps x '$dir'"

    for ((i = 0; i < steps; i++)); do
        move_one_step "$ws_id" "$focused" "$dir" || break
    done

    apply force
}

cmd_status() {
    if [[ -r "$SIDE_FILE" ]]; then
        local published
        published=$(<"$SIDE_FILE")
        [[ "$published" == "left" || "$published" == "right" ]] && SIDE="$published"
    fi

    read_border

    local mon
    mon=$(read_monitor)
    if [[ -z "$mon" ]]; then
        echo "ultrawide monitor (desc prefix '$MONITOR_DESC_PREFIX') not found"
        return 1
    fi

    local m_name m_desc m_x m_y m_w m_h m_scale m_tf rl rt rr rb ws_id ws_name
    IFS=$'\t' read -r m_name m_desc m_x m_y m_w m_h m_scale m_tf \
        rl rt rr rb ws_id ws_name <<<"$mon"

    local ux uy uw uh
    read -r ux uy uw uh <<<"$(usable_box "$m_x" "$m_y" "$m_w" "$m_h" "$m_scale" "$m_tf" "$rl" "$rt" "$rr" "$rb")"

    echo "monitor    $m_name  ($m_desc)"
    echo "mode       ${m_w}x${m_h} @ scale $m_scale, transform $m_tf, origin ${m_x},${m_y}"
    echo "reserved   L=$rl T=$rt R=$rr B=$rb   <- T should be 33 with the eww topbar up"
    echo "gaps       out=$GAPS_OUT in=$GAPS_IN border=$BORDER   <- outer inset $(( GAPS_OUT + BORDER )), neighbours $(( 2 * (GAPS_IN + BORDER) )) apart"
    echo "usable     ${uw}x${uh} at ${ux},${uy}"
    echo "boundaries left|center = $(( ux + $(frac_px "$uw" "$FRAC_LEFT") ))   center|right = $(( ux + $(frac_px "$uw" "$FRAC_RIGHT") ))"
    echo "workspace  $ws_id ($ws_name)"
    if [[ -p "$FIFO" ]]; then
        echo "daemon     running"
    else
        echo "daemon     not running"
    fi
    echo "side       $SIDE"
    echo
    printf '%-20s %9s %9s %9s %9s %s\n' ADDRESS X Y W H FULLSCREEN
    local a wx wy ww wh fs
    while IFS=$'\t' read -r a wx wy ww wh fs; do
        [[ -z "$a" ]] && continue
        printf '%-20s %9s %9s %9s %9s %s\n' "$a" "$wx" "$wy" "$ww" "$wh" "$fs"
    done < <(read_windows "$ws_id")
    echo
    echo "expected tiled height: $(( uh - 2 * (GAPS_OUT + BORDER) ))  (a window shorter than this owns no boundary)"
}

PROBE_FAIL=0
PROBE_SKIP=0

probe_say() { printf '  %s\n' "$*"; }
probe_pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
probe_fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; PROBE_FAIL=1; }
probe_skip() { printf '  \033[33mSKIP\033[0m %s\n' "$*"; PROBE_SKIP=1; }

probe_settle() { sleep 0.35; }

probe_abs() { local v=$1; ((v < 0)) && v=$(( -v )); echo "$v"; }

win_width() {
    hyprctl clients -j 2>/dev/null | jq -r --arg a "$1" \
        '.[] | select(.address == $a) | .size[0]' 2>/dev/null
}

win_order() {
    local a rest out=""
    while IFS=$'\t' read -r a rest; do
        [[ -n "$a" ]] && out="${out}${a}:"
    done < <(read_windows "$1")
    printf '%s\n' "$out"
}

resize_to() {
    hyprctl dispatch \
        "hl.dsp.window.resize({ x = $2, y = $3, relative = false, window = \"address:$1\" })" \
        >/dev/null 2>&1
}

probe_resize() {
    local rel=false
    [[ "$2" == rel ]] && rel=true
    hyprctl dispatch \
        "hl.dsp.window.resize({ x = $3, y = $4, relative = $rel, window = \"address:$1\" })" 2>&1
}

probe_restore_width() {
    local addr=$1 want=$2 h=$3
    local now before sign=1 i

    for ((i = 0; i < 5; i++)); do
        now=$(win_width "$addr")
        [[ -z "$now" ]] && return 0
        (( $(probe_abs $(( now - want ))) <= 2 )) && return 0

        before=$now
        probe_resize "$addr" rel $(( sign * (want - now) )) 0 >/dev/null
        probe_settle
        now=$(win_width "$addr")
        [[ -z "$now" ]] && return 0
        if (( $(probe_abs $(( now - want ))) > $(probe_abs $(( before - want ))) )); then
            sign=$(( -sign ))
        fi
    done

    now=$(win_width "$addr")
    probe_say "warning: could not restore $addr to ${want}px (stuck at ${now}px)."
}

probe_try_resize() {
    local addr=$1 mode=$2 value=$3 h=$4 w0=$5
    local want reply landed verdict
    if [[ "$mode" == abs ]]; then want=$value; else want=$(( w0 + value )); fi

    reply=$(probe_resize "$addr" "$mode" "$value" "$h")
    probe_settle
    landed=$(win_width "$addr")
    [[ -z "$landed" ]] && landed=0

    if (( $(probe_abs $(( landed - want ))) <= 8 )); then
        verdict=EXACT
    elif (( $(probe_abs $(( landed - (2 * w0 - want) ))) <= 8 )); then
        verdict=INVERTED
    elif (( $(probe_abs $(( landed - w0 ))) <= 8 )); then
        verdict=NOCHANGE
    else
        verdict=UNEXPECTED
    fi

    probe_restore_width "$addr" "$w0" "$h"
    printf '%s %s %s\n' "$landed" "$verdict" "${reply//$'\n'/ }"
}

cmd_probe() {
    read_border

    local force_flag="${1:-}"
    command -v jq      >/dev/null || die "probe: jq not found"
    command -v hyprctl >/dev/null || die "probe: hyprctl not found"
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || die "probe: not inside a Hyprland session"

    if [[ -p "$FIFO" ]]; then
        die "probe: the v3 daemon is running and would react to these checks. Stop it first: $0 kill"
    fi
    if [[ "$force_flag" != "--force" ]] \
       && { pgrep -f 'ultrawide_manager\.sh' >/dev/null 2>&1 \
            || pgrep -f 'ultrawide_manager_new\.sh' >/dev/null 2>&1; }; then
        echo "An older ultrawide_manager is running. It rewrites geometry and juggles"
        echo "focus while these checks measure, which makes every result meaningless:"
        echo "a resize reads back as the wrong delta, and its focus events look like"
        echo "self-triggering. Stop it first:"
        echo
        echo "    pkill -f ultrawide_manager"
        echo
        echo "(then re-run. Use 'probe --force' to measure anyway.)"
        return 1
    fi

    local mon
    mon=$(read_monitor)
    [[ -z "$mon" ]] && die "probe: ultrawide monitor (desc prefix '$MONITOR_DESC_PREFIX') not found"

    local m_name m_desc m_x m_y m_w m_h m_scale m_tf rl rt rr rb ws_id ws_name
    IFS=$'\t' read -r m_name m_desc m_x m_y m_w m_h m_scale m_tf \
        rl rt rr rb ws_id ws_name <<<"$mon"

    local -a addrs=() heights=() widths=() xs=()
    local a wx wy ww wh fs
    while IFS=$'\t' read -r a wx wy ww wh fs; do
        [[ -z "$a" ]] && continue
        addrs+=("$a"); widths+=("$ww"); heights+=("$wh"); xs+=("$wx")
    done < <(read_windows "$ws_id")
    local n=${#addrs[@]}

    local uw uh ux uy
    read -r ux uy uw uh <<<"$(usable_box "$m_x" "$m_y" "$m_w" "$m_h" "$m_scale" "$m_tf" "$rl" "$rt" "$rr" "$rb")"
    local expected_h=$(( uh - 2 * (GAPS_OUT + BORDER) ))

    echo "monitor $m_name, workspace $ws_id ($ws_name), $n tiled window(s)"
    local k
    for ((k = 0; k < n; k++)); do
        printf '  %-20s x=%-6s w=%-6s h=%-6s%s\n' \
            "${addrs[$k]}" "${xs[$k]}" "${widths[$k]}" "${heights[$k]}" \
            "$( (( $(probe_abs $(( heights[k] - expected_h ))) > 4 )) && echo "   <- not full height (${expected_h} expected): inside a split" )"
    done
    echo

    echo "== 1. reserved area =="
    probe_say "reserved: [$rl,$rt,$rr,$rb]"
    if ((rt > 0)); then
        probe_pass "top is ${rt}px -- the eww topbar is accounted for."
    else
        probe_fail "top is 0. Either eww is not running, or its bar is not :exclusive." \
                   "Every height this script computes would be too tall by the bar's height," \
                   "and every resize would carry a stray vertical delta."
    fi
    echo

    echo "== 2. address targeting (decides whether v3 works at all) =="
    if ((n < 2)); then
        probe_skip "needs 2+ tiled windows on the ultrawide; found $n."
    else
        local right="${addrs[$((n-1))]}" left="${addrs[0]}"
        local rw0="${widths[$((n-1))]}" rh="${heights[$((n-1))]}"
        local lw0="${widths[0]}" lh="${heights[0]}"
        local delta=-200
        (( rw0 + delta < 300 || lw0 + delta < 300 )) && delta=200

        probe_say "resizing by address, both ends, both modes (delta ${delta}px)"
        local r_abs r_rel l_abs l_rel
        r_abs=$(probe_try_resize "$right" abs $(( rw0 + delta )) "$rh" "$rw0")
        r_rel=$(probe_try_resize "$right" rel "$delta"           "$rh" "$rw0")
        l_abs=$(probe_try_resize "$left"  abs $(( lw0 + delta )) "$lh" "$lw0")
        l_rel=$(probe_try_resize "$left"  rel "$delta"           "$lh" "$lw0")

        local rec lbl mode w0 want res landed verdict reply
        for rec in \
            "rightmost|absolute|$rw0|$(( rw0 + delta ))|$r_abs" \
            "rightmost|relative|$rw0|$(( rw0 + delta ))|$r_rel" \
            "leftmost |absolute|$lw0|$(( lw0 + delta ))|$l_abs" \
            "leftmost |relative|$lw0|$(( lw0 + delta ))|$l_rel"
        do
            IFS='|' read -r lbl mode w0 want res <<<"$rec"
            read -r landed verdict reply <<<"$res"
            printf '    %s %-8s %5s -> %-5s (wanted %5s)  %-9s %s\n' \
                "$lbl" "$mode" "$w0" "$landed" "$want" "$verdict" "$reply"
        done

        local rrv lrv sign_r sign_l
        read -r _ rrv _ <<<"$r_rel"
        read -r _ lrv _ <<<"$l_rel"
        case "$rrv" in EXACT) sign_r=1 ;; INVERTED) sign_r=-1 ;; *) sign_r="" ;; esac
        case "$lrv" in EXACT) sign_l=1 ;; INVERTED) sign_l=-1 ;; *) sign_l="" ;; esac

        if [[ -z "$sign_l" && -z "$sign_r" ]]; then
            probe_fail "neither end responded to a relative resize in a way this can" \
                       "read -- see the table and hyprctl's replies."
        else
            probe_say "addressing works: the window named by the address is the one that moved."
            [[ -z "$sign_l" ]] && probe_say "the leftmost window's sign could not be read."
            [[ -z "$sign_r" ]] && probe_say "the rightmost window's sign could not be read."

            local warned=0
            if (( $(probe_abs $(( heights[0] - expected_h ))) > 4 )); then
                probe_say "caution: the leftmost window is not full height, so the left" \
                          "measurement is of a boundary inside its zone, not the zone boundary."
                warned=1
            fi
            if (( $(probe_abs $(( heights[n-1] - expected_h ))) > 4 )); then
                probe_say "caution: the rightmost window is not full height, so the right" \
                          "measurement is of a boundary inside its zone, not the zone boundary."
                warned=1
            fi
            ((warned)) && probe_say "re-run with three full-height side-by-side windows for a clean reading."

            if [[ "$sign_l" == "$RESIZE_SIGN_LEFT" && "$sign_r" == "$RESIZE_SIGN_RIGHT" ]]; then
                probe_pass "both signs match what this script is set to" \
                           "(left $RESIZE_SIGN_LEFT, right $RESIZE_SIGN_RIGHT). The design holds."
            else
                probe_fail "this script is set to left=$RESIZE_SIGN_LEFT right=$RESIZE_SIGN_RIGHT," \
                           "but this Hyprland measures left=${sign_l:-?} right=${sign_r:-?}. Edit the top of this file:"
                probe_say "    RESIZE_SIGN_LEFT=\"\${ULTRAWIDE_RESIZE_SIGN_LEFT:-${sign_l:-1}}\""
                probe_say "    RESIZE_SIGN_RIGHT=\"\${ULTRAWIDE_RESIZE_SIGN_RIGHT:-${sign_r:--1}}\""
            fi
        fi
    fi
    echo

    echo "== 3. eval and dispatch in one --batch =="
    local batch_out inert_rule inert_dispatch
    inert_rule="eval hl.workspace_rule({ workspace = \"99\", gaps_out = { top = ${GAPS_OUT}, right = ${GAPS_OUT}, bottom = ${GAPS_OUT}, left = ${GAPS_OUT} } })"
    if ((n > 0)); then
        inert_dispatch="dispatch hl.dsp.window.resize({ x = ${widths[0]}, y = ${heights[0]}, relative = false, window = \"address:${addrs[0]}\" })"
    else
        inert_dispatch="$inert_rule"
        probe_say "no windows, so this only exercises eval, not the eval+dispatch mix."
    fi
    batch_out=$(hyprctl --batch "$inert_rule ; $inert_dispatch" 2>&1)
    probe_say "output: ${batch_out//$'\n'/ | }"
    if [[ "$batch_out" == *[Ii]nvalid* || "$batch_out" == *[Uu]nknown* ]]; then
        probe_fail "eval is not accepted inside --batch. Gaps and resizes must be" \
                   "issued as separate hyprctl calls, which risks a visible frame between them."
    else
        probe_pass "eval survives --batch."
    fi
    echo

    echo "== 4. workspace rule accumulation (highest priority) =="
    local before after i
    before=$(hyprctl workspacerules -j 2>/dev/null | jq 'length' 2>/dev/null)
    if [[ -z "$before" || "$before" == "null" ]]; then
        probe_skip "cannot read workspacerules."
    else
        for i in 1 2 3 4 5; do
            hyprctl eval "hl.workspace_rule({ workspace = \"99\", gaps_out = { top = ${GAPS_OUT}, right = ${GAPS_OUT}, bottom = ${GAPS_OUT}, left = ${GAPS_OUT} } })" >/dev/null 2>&1
        done
        after=$(hyprctl workspacerules -j 2>/dev/null | jq 'length' 2>/dev/null)
        probe_say "rules: $before -> $after after 5 identical eval calls"
        if [[ "$before" == "$after" ]]; then
            probe_pass "rules replace. Writing gaps per event is safe."
        else
            probe_fail "rules APPEND. v1 has been growing an unbounded rule vector" \
                       "every session, and v3 must stop writing gaps this way."
            probe_say "clear the junk with: hyprctl reload"
        fi
    fi
    echo

    echo "== 5. does our own writing re-trigger us? =="
    if ! command -v socat >/dev/null; then
        probe_skip "socat not found."
    elif ((n < 1)); then
        probe_skip "needs a window."
    else
        local sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
        local cap
        cap=$(mktemp)

        timeout 2 socat -U - "UNIX-CONNECT:$sock" >"$cap" 2>/dev/null &
        local cap_pid=$!
        sleep 0.4
        local probe_addr="${addrs[0]}" probe_w="${widths[0]}" probe_h="${heights[0]}"
        probe_resize "$probe_addr" abs $(( probe_w - 60 )) "$probe_h" >/dev/null
        probe_settle
        probe_restore_width "$probe_addr" "$probe_w" "$probe_h"
        wait "$cap_pid" 2>/dev/null
        local events relevant
        events=$(grep -c . "$cap" 2>/dev/null);                    events=${events:-0}
        relevant=$(grep -cE "$HANDLED_EVENT_RE" "$cap" 2>/dev/null); relevant=${relevant:-0}

        if ((relevant == 0)); then
            if ((events > 0)); then
                probe_say "$events event(s) seen, none of them handled by v3:"
                sort -u "$cap" | cut -d'>' -f1 | sort -u | sed 's/^/       /'
            fi
            probe_pass "a resize emits nothing v3 acts on -- the apply pass cannot" \
                       "re-trigger itself. No settling file, debounce PID or trigger" \
                       "file is needed."
        else
            probe_fail "a resize emitted $relevant event(s) that v3 handles:"
            grep -E "$HANDLED_EVENT_RE" "$cap" | sort -u | head -5 | sed 's/^/       /'
            probe_say "v3 would feed itself on these."
        fi

        : > "$cap"
        timeout 2 socat -U - "UNIX-CONNECT:$sock" >"$cap" 2>/dev/null &
        cap_pid=$!
        sleep 0.4
        hyprctl dispatch 'hl.dsp.window.float()' >/dev/null 2>&1; sleep 0.4
        hyprctl dispatch 'hl.dsp.window.float()' >/dev/null 2>&1
        wait "$cap_pid" 2>/dev/null
        if grep -q '^changefloatingmode' "$cap"; then
            probe_pass "float toggling emits changefloatingmode -- v3 hooks it."
        else
            probe_fail "float toggling emitted no changefloatingmode. SUPER+V would" \
                       "silently change the tiled count without v3 noticing. Saw:"
            sort -u "$cap" | cut -d'>' -f1 | sort -u | head -5 | sed 's/^/       /'
        fi
        rm -f "$cap"
    fi
    echo

    echo "== 6. move dispatcher (only left/center/right depend on this) =="
    if ((n < 2)); then
        probe_skip "needs 2+ tiled windows; found $n."
    else
        local focused idx=-1 j
        focused=$(focused_address)
        for j in "${!addrs[@]}"; do
            [[ "${addrs[$j]}" == "$focused" ]] && idx=$j
        done
        if ((idx < 0)); then
            probe_skip "the focused window is not tiled on this workspace."
        else
            probe_say "focused: $focused (index $idx of $n, counting from the left)"

            local -a dirs=()
            ((idx > 0))       && dirs+=(l left)
            ((idx < n - 1))   && dirs+=(r right)

            local before_order fmt d winner="" winner_dir="" reply saw_nothing_there=0
            before_order=$(win_order "$ws_id")
            for fmt in "$MOVE_DISPATCH_FMT" 'hl.dsp.window.swap({ direction = "%s" })'; do
                for d in "${dirs[@]}"; do
                    reply=$(hyprctl dispatch "$(printf "$fmt" "$d")" 2>&1)
                    probe_settle
                    if [[ "$before_order" != "$(win_order "$ws_id")" ]]; then
                        winner="$fmt"; winner_dir="$d"
                        printf '    %-48s moved   %s\n' "$(printf "$fmt" "$d")" "${reply//$'\n'/ }"
                        break 2
                    fi
                    [[ "$reply" == *"in that direction"* ]] && saw_nothing_there=1
                    printf '    %-48s no-op   %s\n' "$(printf "$fmt" "$d")" "${reply//$'\n'/ }"
                done
            done

            if [[ -n "$winner" ]]; then
                local back
                case "$winner_dir" in
                    l) back=r ;; r) back=l ;; left) back=right ;; right) back=left ;;
                esac
                hyprctl dispatch "$(printf "$winner" "$back")" >/dev/null 2>&1
                probe_settle
            fi

            if [[ -z "$winner" ]]; then
                probe_fail "no candidate dispatcher reordered the windows."
                if ((saw_nothing_there)); then
                    probe_say "every candidate reported no window in that direction, and the" \
                              "focused window has a neighbour in x-order that way -- so these $n" \
                              "windows are not all side by side. Check the box table at the top:"
                    probe_say "two windows sharing an x are"
                    probe_say "stacked vertically, which also makes check 2's reading a measurement" \
                              "of an intra-zone boundary. Close them down to three plain columns" \
                              "and re-run before trusting either check."
                else
                    probe_say "Pick a name from hyprctl's replies above and set MOVE_DISPATCH_FMT;" \
                              "only left/center/right are affected."
                fi
            elif [[ "$winner" == "$MOVE_DISPATCH_FMT" ]]; then
                probe_pass "'$(printf "$winner" "$winner_dir")' reorders windows."
            else
                probe_fail "MOVE_DISPATCH_FMT is wrong, but this works:"
                probe_say "    MOVE_DISPATCH_FMT='$winner'"
            fi
            if [[ -n "$winner" && "$(win_order "$ws_id")" != "$before_order" ]]; then
                probe_say "note: the window order was NOT restored -- '$winner' is not its own inverse."
            fi
        fi
    fi
    echo

    if ((PROBE_FAIL)); then
        echo "RESULT: at least one check FAILED -- read the notes above before running the daemon."
        return 1
    elif ((PROBE_SKIP)); then
        echo "RESULT: everything that could run passed, but some checks were skipped."
        echo "        Open 2+ tiled windows on the ultrawide and re-run for full coverage."
        return 0
    fi
    echo "RESULT: all six checks passed."
    return 0
}

handle_line() {
    local line=$1
    local event="${line%%>>*}"
    local data="${line#*>>}"

    if [[ "$event" == cmd ]]; then
        case "$data" in
            refresh)      log "cmd refresh"; apply force ;;
            swap)         cmd_swap ;;
            move:left)    cmd_move_zone left ;;
            move:center)  cmd_move_zone center ;;
            move:right)   cmd_move_zone right ;;
            quit)         log "cmd quit"; exit 0 ;;
            *)            log "unknown command: $data" ;;
        esac
        return
    fi

    [[ "$line" =~ $HANDLED_EVENT_RE ]] || return

    case "$event" in
        configreloaded|monitoradded|monitoraddedv2|monitorremoved|monitorremovedv2)
            LAST_GAPS="" ;;
    esac

    [[ "$event" == configreloaded ]] && register_drag_bind

    apply
}

register_drag_bind() {
    [[ -z "$DRAG_BIND" ]] && return 0
    send_batch "keyword bindr $DRAG_BIND, exec, $SELF refresh"
}

run_daemon() {
    command -v jq >/dev/null || die "jq not found"
    command -v socat >/dev/null || die "socat not found"
    command -v hyprctl >/dev/null || die "hyprctl not found"
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || die "not inside a Hyprland session"

    mkdir -p "$RUNTIME_DIR" "$(dirname "$LOG_FILE")"

    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        die "another ultrawide_manager_v3 daemon is already running"
    fi

    [[ -p "$FIFO" ]] || { rm -f "$FIFO"; mkfifo -m 600 "$FIFO"; }

    exec 3<>"$FIFO"

    local sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr/${HYPRLAND_INSTANCE_SIGNATURE}/.socket2.sock"
    [[ -S "$sock" ]] || die "Hyprland event socket not found at $sock"

    socat -U - "UNIX-CONNECT:$sock" >&3 2>/dev/null &
    local socat_pid=$!
    trap 'kill "$socat_pid" 2>/dev/null; rm -f "$FIFO" "$SIDE_FILE"' EXIT

    publish_side
    log "daemon started (pid $$, side=$SIDE)"
    apply force
    if [[ -n "$DRAG_BIND" ]]; then
        register_drag_bind
        log "drag bind: bindr $DRAG_BIND -> refresh"
    fi

    local line extra
    while IFS= read -r line <&3; do
        [[ -z "$line" ]] && continue

        if [[ "$line" == cmd\>\>* ]]; then
            handle_line "$line"
            continue
        fi

        [[ "$line" =~ $HANDLED_EVENT_RE ]] || continue

        local -a pending=("$line")
        while IFS= read -r -t "$BURST_DRAIN_SECS" extra <&3; do
            [[ -z "$extra" ]] && continue
            [[ "$extra" == cmd\>\>* || "$extra" =~ $HANDLED_EVENT_RE ]] && pending+=("$extra")
        done

        local seen_event="" item
        for item in "${pending[@]}"; do
            if [[ "$item" == cmd\>\>* ]]; then
                handle_line "$item"
            else
                seen_event="$item"
            fi
        done
        [[ -n "$seen_event" ]] && handle_line "$seen_event"
    done
}

send_command() {
    [[ -p "$FIFO" ]] || die "daemon not running (no $FIFO)"
    if ! timeout 1 sh -c "printf '%s\n' 'cmd>>$1' > '$FIFO'"; then
        die "daemon not running (write to $FIFO timed out)"
    fi
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 0
fi

case "${1:-daemon}" in
    daemon)             run_daemon ;;
    once)               LOG_FILE=/dev/stderr; apply force ;;
    refresh)            send_command refresh ;;
    swap)               send_command swap ;;
    left|center|right)  send_command "move:$1" ;;
    status)             cmd_status ;;
    probe)              cmd_probe "${2:-}" ;;
    kill)               send_command quit ;;
    -h|--help|help)
        cat <<'USAGE'
ultrawide_manager_v3.sh [command]

  (none)            run the daemon
  once              run ONE apply pass in this shell, no daemon, log to stderr
  refresh           force a full re-apply of gaps and both boundaries
  swap              flip which side a pair of windows occupies
  left|center|right move the focused window to that zone
  status            geometry, boundaries and current window boxes
  probe             run six checks against a live Hyprland before trusting this.
                    Refuses while an older ultrawide_manager is running, since
                    that makes every measurement meaningless; probe --force
                    measures anyway.
  kill              stop the running daemon

Suggested binds for conf/bindings.lua (not added automatically):

  local uw = "~/.config/hypr/scripts/ultrawide_manager_v3.sh"
  hl.bind("SUPER + CTRL + h", hl.dsp.exec_cmd(uw .. " left"))
  hl.bind("SUPER + CTRL + j", hl.dsp.exec_cmd(uw .. " center"))
  hl.bind("SUPER + CTRL + l", hl.dsp.exec_cmd(uw .. " right"))
  hl.bind("SUPER + CTRL + s", hl.dsp.exec_cmd(uw .. " swap"))
  hl.bind("SUPER + CTRL + r", hl.dsp.exec_cmd(uw .. " refresh"))
USAGE
        ;;
    *)
        die "unknown command '$1' (try --help)" ;;
esac
