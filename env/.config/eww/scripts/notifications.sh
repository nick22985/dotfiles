#!/bin/bash
# Notification history for the control center's Notifications page.
#   listen         {"count", "items"} as JSON whenever the history changes
#   dismiss <id>   close one notification
#   open <id>      focus the window of the app that sent it, then close it
#   clear          close every notification
#
# swaync has no way to list its notifications, so the listener watches the notification traffic on
# the session bus instead: every Notify call is kept, and a notification goes when swaync reports it
# dismissed or closed. Popups that time out stay, as they do in swaync's own panel. Closing goes
# through swaync too, so both lists agree. The history lives in the runtime directory, so it
# survives an eww restart but not a reboot.
#
# Notifications come from other programs, so their text is only ever shown as label text and
# commands carry the numeric id.
# shellcheck disable=SC2016 # the single-quoted strings are jq programs

RUNTIME="${XDG_RUNTIME_DIR:-/tmp}"
STATE="$RUNTIME/eww-notifications.json"
LOCK="$RUNTIME/eww-notifications.lock"
LIMIT=50
BUS_NAME=org.freedesktop.Notifications
ICON_DIRS=("$HOME/.local/share/icons" /usr/share/icons)
ICON_SIZES=(scalable 48x48 64x64 128x128 256x256 32x32 48)
ICON_KINDS=(apps status devices categories actions)

# Each bus message as one tab-separated line: a Notify call as
# "call, sender and cookie, icon candidates, entry", its reply as "reply, destination and cookie, id",
# and a close as "closed, id". Transient notifications are skipped, as swaync doesn't keep them.
BUS_FILTER='
def hint($k): .[$k] | if type == "object" then .data else null end;
def plain($limit):
    gsub("<[^>]*>"; " ")
    | gsub("&lt;"; "<") | gsub("&gt;"; ">") | gsub("&quot;"; "\"") | gsub("&apos;"; "\u0027")
    | gsub("&#(?<n>[0-9]+);"; [.n | tonumber] | implode) | gsub("&amp;"; "&")
    | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ")
    | if length > $limit then .[:$limit - 1] + "…" else . end
    # A break chance inside long runs such as links, so one long word cannot widen the panel.
    | gsub("(?<run>\\S{24})(?=\\S)"; "\(.run)​");
fromjson? | (.payload.data // []) as $d
| if .type == "method_call" and .member == "Notify" and ($d | length) == 8 then
    ($d[6] | if type == "object" then . else {} end) as $h
    | select(($h | hint("transient")) | not)
    | ($h | hint("desktop-entry") // "") as $desktop
    | ["call", "\(.sender) \(.cookie)",
       ([($h | hint("image-path") // ""), $d[2], $desktop, ($desktop | ascii_downcase)] | join("\u001f")),
       ({id: 0,
         sync: ($h | hint("x-canonical-private-synchronous") // ""),
         app: ($d[0] | plain(40)),
         desktop: $desktop,
         summary: ($d[3] | plain(80)),
         body: ($d[4] | plain(160)),
         icon: "",
         urgency: ({"0": "low", "2": "critical"}[($h | hint("urgency") // 1) | tostring] // "normal"),
         time: ((.["timestamp-realtime"] // (now * 1e6)) / 1e6 | floor)} | tojson)]
  elif .type == "method_return" and ($d | length) == 1 then
    ["reply", "\(.destination) \(.reply_cookie)", ($d[0] | tostring)]
  elif .type == "signal" and .member == "NotificationClosed" and ($d | length) == 2 and ([2, 3, 4] | index($d[1])) then
    ["closed", ($d[0] | tostring)]
  else empty end
| join("\t")'

# Runs the given command with the history locked.
locked() {
    mkdir -p "$RUNTIME"
    (
        flock 9
        "$@"
    ) 9>"$LOCK"
}

change() {
    [[ -f "$STATE" ]] || echo "[]" > "$STATE"
    local program="$1"
    shift
    locked edit_history_with "$program" "$@"
}

# Replaces the history with the output of a jq program run over it.
edit_history_with() {
    local program="$1" items
    shift
    items="$(jq -c --argjson limit "$LIMIT" "$@" "($program) | .[:\$limit]" "$STATE" 2>/dev/null)"
    [[ "$(jq -r 'type' <<< "$items" 2>/dev/null)" == array ]] || items="[]"
    printf '%s\n' "$items" > "$STATE.part" && mv "$STATE.part" "$STATE"
}

render() {
    jq -c --argjson now "$(date +%s)" '
        def ago:
            ($now - .) as $s
            | if $s < 60 then "now"
              elif $s < 3600 then "\($s / 60 | floor)m"
              elif $s < 86400 then "\($s / 3600 | floor)h"
              elif $s < 6 * 86400 then strflocaltime("%a")
              else strflocaltime("%d %b") end;
        if type == "array" then . else [] end
        | {count: length, items: map({id, app, summary, body, icon, urgency, ago: (.time | ago)})}' "$STATE" 2>/dev/null \
        || echo '{"count":0,"items":[]}'
}

push() {
    eww update notifications="$(render)" 2>/dev/null
}

icon_theme() {
    sed -n 's/^gtk-icon-theme-name[[:space:]]*=[[:space:]]*"\?\([^"]*\)"\?[[:space:]]*$/\1/p' \
        ~/.config/gtk-3.0/settings.ini /etc/gtk-3.0/settings.ini 2>/dev/null | head -n1
}

# A file for an icon given as a path, a file:// url or a theme icon name. Icons are shown through a
# CSS url(), so only plain names and paths are taken.
find_icon() {
    local name="${1#file://}" theme base size kind extension
    [[ -n "$name" ]] || return 1
    if [[ "$name" == /* ]]; then
        [[ "$name" =~ ^[[:alnum:]_./+\ -]+$ && -f "$name" ]] && printf '%s\n' "$name"
        return
    fi
    [[ "$name" =~ ^[[:alnum:]_.+-]+$ ]] || return 1
    for theme in $(icon_theme) hicolor Adwaita; do
        for base in "${ICON_DIRS[@]}"; do
            for size in "${ICON_SIZES[@]}"; do
                for kind in "${ICON_KINDS[@]}"; do
                    for extension in svg png; do
                        [[ -f "$base/$theme/$size/$kind/$name.$extension" ]] && { printf '%s\n' "$base/$theme/$size/$kind/$name.$extension"; return; }
                    done
                done
            done
        done
    done
    for extension in svg png; do
        [[ -f "/usr/share/pixmaps/$name.$extension" ]] && { printf '%s\n' "/usr/share/pixmaps/$name.$extension"; return; }
    done
    return 1
}

first_icon() {
    local candidate
    while IFS= read -r -d $'\x1f' candidate; do
        find_icon "$candidate" && return
    done <<< "$1"$'\x1f'
}

# Every message to and from the notification server, restarting busctl if it stops.
bus_stream() {
    while true; do
        stdbuf -oL busctl --user monitor --json=short "$BUS_NAME" 2>/dev/null
        sleep 2
    done | jq -R -r --unbuffered "$BUS_FILTER"
}

listen() {
    local kind key rest icons entry output last=""
    declare -A pending=()
    # Whatever swaync dropped while eww wasn't running is gone for good.
    [[ "$(swaync-client -c 2>/dev/null)" == 0 ]] && change '[]'
    while true; do
        output="$(render)"
        [[ "$output" != "$last" ]] && printf '%s\n' "$output"
        last="$output"
        # Wake every half minute anyway, so the "5m" times keep up.
        IFS=$'\t' read -r -t 30 kind key rest || continue
        case "$kind" in
            call)
                IFS=$'\t' read -r icons entry <<< "$rest"
                (( ${#pending[@]} > 100 )) && pending=()
                pending["$key"]="$(jq -c --arg icon "$(first_icon "$icons")" '.icon = $icon' <<< "$entry" 2>/dev/null)"
                ;;
            reply)
                entry="${pending["$key"]}"
                [[ -n "$entry" ]] || continue
                unset 'pending[$key]'
                # The new one goes on top, in place of any it replaces.
                change '($new | .id = $id) as $n | [$n] + map(select(.id != $n.id and ($n.sync == "" or .sync != $n.sync or .app != $n.app)))' \
                    --argjson new "$entry" --argjson id "$rest"
                ;;
            closed)
                change 'map(select(.id != $id))' --argjson id "$key"
                ;;
        esac
    done < <(bus_stream)
}

valid_id() {
    [[ "$1" =~ ^[0-9]+$ ]] || { echo "Invalid notification id: $1" >&2; exit 1; }
}

dismiss() {
    gdbus call --session --dest "$BUS_NAME" --object-path /org/freedesktop/Notifications \
        --method "$BUS_NAME.CloseNotification" "$1" >/dev/null 2>&1
    change 'map(select(.id != $id))' --argjson id "$1"
    push
}

# Focuses the most recently used window whose class matches the sending app, if there is one.
open_app() {
    local names address
    names="$(jq -c --argjson id "$1" '[.[] | select(.id == $id) | .desktop, .app | select(. != "") | ascii_downcase]' "$STATE" 2>/dev/null)"
    address="$(hyprctl -j clients 2>/dev/null | jq -r --argjson names "${names:-[]}" '
        [.[] | select((.class | ascii_downcase) as $c | $names | index($c))] | min_by(.focusHistoryID) | .address // empty' 2>/dev/null)"
    [[ -n "$address" ]] && hyprctl dispatch focuswindow "address:$address" >/dev/null 2>&1
    dismiss "$1"
}

clear_all() {
    swaync-client -C -sw >/dev/null 2>&1
    change '[]'
    push
}

case "$1" in
    listen) listen ;;
    dismiss) valid_id "$2"; dismiss "$2" ;;
    open) valid_id "$2"; open_app "$2" ;;
    clear) clear_all ;;
    *)
        echo "Usage: $0 {listen|dismiss <id>|open <id>|clear}" >&2
        exit 1
        ;;
esac
