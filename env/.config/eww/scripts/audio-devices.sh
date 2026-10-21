#!/bin/bash
# Audio page of the control center.
#   list               {"sinks": [...], "sources": [...], "apps": [...]}; devices are {"id", "name", "default"},
#                      apps (playback streams) are {"id", "name", "media", "icon", "muted"}
#   volumes            {"<app id>": volume} for the apps, kept apart from list so a volume change
#                      doesn't rebuild the app rows (and drop a slider mid-drag)
#   set-sink <id>      make an output the default
#   set-source <id>    make an input the default
#   mute-app <id>      toggle an app's mute

# shellcheck source=lib/icons.sh
source "$(dirname "$0")/lib/icons.sh"

STEAM_DIRS=("$HOME/.local/share/Steam" "$HOME/.steam/steam")

devices() {
    local kind="$1" default="$2"
    pactl -f json list "$kind" 2>/dev/null | jq -c --arg default "$default" '
        map(select((.name | endswith(".monitor") | not) and ((.monitor_of_sink // "n/a") == "n/a"))
            | {id: .index, name: (.description // .name), default: (.name == $default)})'
}

# The Steam app id a process was started under, from its environment.
steam_app_id() {
    local var
    [[ -r "/proc/$1/environ" ]] || return 1
    while IFS= read -r -d '' var; do
        if [[ "$var" =~ ^SteamAppId=([0-9]+)$ && "${BASH_REMATCH[1]}" != 0 ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi
    done 2>/dev/null < "/proc/$1/environ"
    return 1
}

# A Steam game's name from its app manifest in any of the Steam libraries.
steam_name() {
    local dir library manifest
    for dir in "${STEAM_DIRS[@]}"; do
        while IFS= read -r library; do
            manifest="$library/steamapps/appmanifest_$1.acf"
            [[ -f "$manifest" ]] && { sed -n 's/^[[:space:]]*"name"[[:space:]]*"\(.*\)"$/\1/p' "$manifest" | head -n1; return; }
        done < <(printf '%s\n' "$dir"; sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"$/\1/p' "$dir/steamapps/libraryfolders.vdf" 2>/dev/null)
    done
    return 1
}

# The Hyprland window of a process or its nearest ancestor with one, as "class\x1ftitle".
window_of() {
    local pid="$1" windows="$2" window stat i
    for ((i = 0; i < 12 && pid > 1; i++)); do
        window="$(awk -F'\x1f' -v pid="$pid" '$1 == pid {print $2 "\x1f" $3; exit}' <<< "$windows")"
        [[ -n "$window" ]] && { printf '%s\n' "$window"; return 0; }
        stat="$(cat "/proc/$pid/stat" 2>/dev/null)" || return 1
        read -r _ pid _ <<< "${stat##*) }"
    done
    return 1
}

# Each app's icon is the first of its icon name, Flatpak id, binary or lowercased name that the
# icon theme has. Streams carry few details of their own, so the client's fill the gaps.
# Steam games (Proton ones report Wine and an internal name) go by their Steam name and icon.
# Apps with no name, or only a runtime's (Java, Wine, Python) or engine's (WebRTC, Chromium), go by
# the desktop entry of their Flatpak id or window class, else their window's title; the class joins
# the icon candidates. Steam goes by the app's own pid first; the window by the pid PipeWire took from
# the socket first, since a Flatpak app's own pid is from inside its sandbox.
apps() {
    local icons own_pid sec_pid generic app_id app steam_id name window class title windows
    windows="$(hyprctl clients -j 2>/dev/null | jq -r '.[] | [.pid, .class, .title] | map(tostring | gsub("[\u001f\n]"; " ")) | join("\u001f")')"
    jq -r -n --argjson clients "$(pactl -f json list clients 2>/dev/null || echo '[]')" \
        --argjson streams "$(pactl -f json list sink-inputs 2>/dev/null || echo '[]')" '
        ($clients | map({key: (.index | tostring), value: .properties}) | from_entries) as $client
        | $streams[] | (($client[.client | tostring] // {}) + .properties) as $p
        | ($p["application.process.binary"] // "") as $binary
        | {id: (.index | tostring),
           name: ($p["application.name"] // (if $binary != "" then $binary else null end) // $p["media.name"] // "Unknown"),
           media: ($p["media.name"] // ""),
           muted: .mute} as $app
        | [$p["application.icon_name"], $p["pipewire.access.portal.app_id"], $binary,
           ($p["application.name"] // "" | ascii_downcase | gsub(" "; "-"))]
        | map(select(. != null and . != "")) | join("\u001f")
          + "\u001e" + ($p["application.process.id"] // "") + "\u001e" + ($p["pipewire.sec.pid"] // "")
          + "\u001e" + (if $p["application.name"] == null
                          or ($binary | test("^(java|wine.*|python[0-9.]*)$"))
                          or ($p["application.name"] | test("^(WEBRTC VoiceEngine|Chromium|ALSA plug-in.*)$"; "i"))
                        then "1" else "" end)
          + "\u001e" + ($p["pipewire.access.portal.app_id"] // "")
          + "\u001e" + ($app | tojson)' \
    | while IFS=$'\x1e' read -r icons own_pid sec_pid generic app_id app; do
        name=""
        [[ "$own_pid" =~ ^[0-9]+$ ]] || own_pid=""
        [[ "$sec_pid" =~ ^[0-9]+$ ]] || sec_pid=""
        if steam_id="$(steam_app_id "$own_pid" || steam_app_id "$sec_pid")"; then
            icons="steam_icon_$steam_id"$'\x1f'"$icons"
            name="$(steam_name "$steam_id")"
        elif [[ -n "$generic" ]]; then
            class="" title=""
            if window="$(window_of "$sec_pid" "$windows" || window_of "$own_pid" "$windows")"; then
                IFS=$'\x1f' read -r class title <<< "$window"
                class="${class,,}"
                icons="$class"$'\x1f'"${class%%[^a-z0-9._-]*}"$'\x1f'"$icons"
            fi
            name="$(desktop_value "$app_id" Name || desktop_value "$class" Name)"
            name="${name:-$title}"
        fi
        jq -c --arg icon "$(first_icon "$icons")" --arg name "$name" '.icon = $icon | if $name != "" then .name = $name end' <<< "$app"
    done | jq -s -c 'sort_by(.name | ascii_downcase)'
}

volumes() {
    pactl -f json list sink-inputs 2>/dev/null | jq -c '
        map({key: (.index | tostring), value: ([.volume[].value_percent | rtrimstr("%") | tonumber] | max)})
        | from_entries'
}

list() {
    local sinks sources apps
    sinks="$(devices sinks "$(pactl get-default-sink 2>/dev/null)")"
    sources="$(devices sources "$(pactl get-default-source 2>/dev/null)")"
    apps="$(apps)"
    jq -n -c --argjson sinks "${sinks:-[]}" --argjson sources "${sources:-[]}" --argjson apps "${apps:-[]}" \
        '{sinks: $sinks, sources: $sources, apps: $apps}'
}

valid_id() {
    [[ "$1" =~ ^[0-9]+$ ]] || { echo "Invalid device id: $1" >&2; exit 1; }
}

case "$1" in
    list)
        list
        ;;
    volumes)
        volumes
        ;;
    set-sink|set-source)
        valid_id "$2"
        pactl "set-default-${1#set-}" "$2"
        eww update audio_devices="$(list)"
        ;;
    mute-app)
        valid_id "$2"
        pactl set-sink-input-mute "$2" toggle
        eww update audio_devices="$(list)"
        ;;
    *)
        echo "Usage: $0 {list|volumes|set-sink <id>|set-source <id>|mute-app <id>}" >&2
        exit 1
        ;;
esac
