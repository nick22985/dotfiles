#!/bin/bash
# Wi-Fi page of the control center.
#   list               networks as JSON, strongest access point per SSID, connected one first
#   rescan             scan, then push the new list to eww
#   toggle             turn the Wi-Fi radio on or off
#   connect <bssid>    join a saved or open network, or ask for the password
#   join <bssid>       join with the password read from stdin (sent by the prompt)
#   disconnect         drop the current Wi-Fi connection
#   cancel             close the password prompt
#
# SSIDs come from whoever runs the access point, so commands only ever carry the BSSID
# and look the SSID up again here; the SSID is only shown as label text.

BSSID_RE='^([0-9A-F]{2}:){5}[0-9A-F]{2}$'

wifi_device() {
    nmcli -t -f DEVICE,TYPE device 2>/dev/null | awk -F: '$2 == "wifi" { print $1; exit }'
}

# SSIDs of saved Wi-Fi profiles, one per line.
saved_ssids() {
    local uuid
    nmcli -t -f UUID,TYPE connection show 2>/dev/null | awk -F: '$2 == "802-11-wireless" { print $1 }' \
        | while read -r uuid; do
            nmcli -g 802-11-wireless.ssid connection show "$uuid" 2>/dev/null
        done
}

list() {
    if [[ "$(nmcli radio wifi 2>/dev/null)" != "enabled" ]]; then
        echo "[]"
        return
    fi
    # Terse output escapes ':' inside fields as '\:'; the SSID is last so it may hold anything.
    nmcli -t -f IN-USE,SIGNAL,SECURITY,BSSID,SSID device wifi list --rescan no 2>/dev/null \
        | jq -R -s -c --rawfile saved <(saved_ssids) '
            ($saved | split("\n") | map(select(. != ""))) as $known
            | split("\n")
            | map(select(. != "")
                | [splits("(?<!\\\\):")] as $f
                | {
                    active: ($f[0] == "*"),
                    signal: ($f[1] | tonumber? // 0),
                    secure: ($f[2] != "" and $f[2] != "--"),
                    bssid: ($f[3] | gsub("\\\\:"; ":")),
                    ssid: ($f[4:] | join(":") | gsub("\\\\(?<c>.)"; "\(.c)"))
                }
                | select(.ssid != "" and (.bssid | test("'"$BSSID_RE"'")))
                | .known = (.ssid as $s | $known | index($s) != null))
            | group_by(.ssid)
            | map(sort_by(.active, .signal) | last)
            | sort_by((.active | not), -.signal)
            | .[:20]'
}

push_list() {
    eww update wifi_networks="$(list)"
}

# Field of the strongest access point with this BSSID in the scan results.
network_field() {
    list | jq -r --arg b "$1" --arg f "$2" 'map(select(.bssid == $b)) | first | .[$f] // empty'
}

valid_bssid() {
    [[ "$1" =~ $BSSID_RE ]] || { echo "Invalid BSSID: $1" >&2; exit 1; }
}

notify() {
    notify-send -a "Wi-Fi" "$@"
}

prompt_monitor() {
    local monitor
    monitor="$(eww get cc_open 2>/dev/null)"
    echo "${monitor:-0}"
}

open_prompt() {
    local bssid="$1" ssid="$2" monitor x
    monitor="$(prompt_monitor)"
    x="$(~/.config/eww/scripts/control-center.sh offset "$monitor")"
    ~/.config/eww/scripts/control-center.sh close
    eww update wifi_prompt="$(jq -n -c --arg b "$bssid" --arg s "$ssid" '{bssid: $b, ssid: $s, state: "input"}')"
    eww open wifi-prompt --screen "$monitor" --anchor "top right" --pos "${x}x6"
}

case "$1" in
    list)
        list
        ;;
    rescan)
        eww update wifi_scanning=true
        push_list
        nmcli device wifi rescan 2>/dev/null
        # The scan finishes a moment after rescan returns.
        sleep 2
        push_list
        eww update wifi_scanning=false
        ;;
    toggle)
        if [[ "$(nmcli radio wifi)" == "enabled" ]]; then
            nmcli radio wifi off
        else
            nmcli radio wifi on
        fi
        eww update wifi_enabled="$(nmcli radio wifi)"
        push_list
        ;;
    connect)
        valid_bssid "$2"
        network="$(list | jq -c --arg b "$2" 'map(select(.bssid == $b)) | first // empty')"
        [[ -n "$network" ]] || { notify "Network not found" "Scan again and pick it from the list."; exit 1; }
        ssid="$(jq -r .ssid <<< "$network")"
        if [[ "$(jq -r .active <<< "$network")" == "true" ]]; then
            exit 0
        fi
        if [[ "$(jq -r '.known or (.secure | not)' <<< "$network")" == "true" ]]; then
            eww update wifi_connecting="$2"
            if nmcli --wait 30 device wifi connect "$2" >/dev/null 2>&1; then
                notify "Connected" "$ssid"
            elif [[ "$(jq -r .secure <<< "$network")" == "true" ]]; then
                # The saved password no longer works.
                eww update wifi_connecting=""
                open_prompt "$2" "$ssid"
                exit 0
            else
                notify "Could not connect" "$ssid"
            fi
            eww update wifi_connecting=""
            push_list
        else
            open_prompt "$2" "$ssid"
        fi
        ;;
    join)
        valid_bssid "$2"
        IFS= read -r password
        ssid="$(network_field "$2" ssid)"
        eww update wifi_prompt="$(jq -n -c --arg b "$2" --arg s "$ssid" '{bssid: $b, ssid: $s, state: "connecting"}')"
        if nmcli --wait 30 device wifi connect "$2" password "$password" >/dev/null 2>&1; then
            eww close wifi-prompt
            notify "Connected" "$ssid"
        else
            eww update wifi_prompt="$(jq -n -c --arg b "$2" --arg s "$ssid" '{bssid: $b, ssid: $s, state: "error"}')"
        fi
        ;;
    disconnect)
        device="$(wifi_device)"
        [[ -n "$device" ]] && nmcli device disconnect "$device" >/dev/null
        push_list
        ;;
    cancel)
        eww close wifi-prompt
        ;;
    *)
        echo "Usage: $0 {list|rescan|toggle|connect <bssid>|join <bssid>|disconnect|cancel}" >&2
        exit 1
        ;;
esac
