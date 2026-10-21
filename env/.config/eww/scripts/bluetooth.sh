#!/bin/bash
# Bluetooth page of the control center.
#   list           {"powered", "devices": [...]} as JSON, paired devices first
#   toggle         turn the adapter on or off
#   click <mac>    disconnect a connected device, connect a paired one, or pair a new one
#   scan           look for new devices for a few seconds
#   forget <mac>   remove a paired device
#
# Device names are broadcast by the device, so commands only ever carry its address.

MAC_RE='^([0-9A-F]{2}:){5}[0-9A-F]{2}$'
SCAN_SECONDS=12

powered() {
    bluetoothctl show 2>/dev/null | grep -q 'Powered: yes'
}

# One JSON object per device: name from `devices`, state from `info`.
device_json() {
    local mac="$1" name="$2"
    bluetoothctl info "$mac" 2>/dev/null | jq -R -s -c --arg mac "$mac" --arg name "$name" '
        def field($k): (capture("\n\t" + $k + ": (?<v>[^\n]*)") // {v: ""}).v;
        {
            mac: $mac,
            name: $name,
            paired: (field("Paired") == "yes"),
            connected: (field("Connected") == "yes"),
            icon: field("Icon"),
            battery: (field("Battery Percentage") | capture("\\((?<p>[0-9]+)\\)") // {p: ""} | .p)
        }'
}

# "<mac> <name>" lines; unnamed discoveries show their address with dashes as the name.
devices() {
    bluetoothctl devices "$@" 2>/dev/null | awk '$1 == "Device" { mac = $2; $1 = $2 = ""; sub(/^ +/, ""); print mac, $0 }'
}

list() {
    if ! powered; then
        echo '{"powered":false,"devices":[]}'
        return
    fi
    local mac name paired nearby=0
    paired="$(devices Paired)"
    {
        while read -r mac name; do
            [[ "$mac" =~ $MAC_RE ]] && device_json "$mac" "$name"
        done <<< "$paired"
        devices | while read -r mac name; do
            [[ "$mac" =~ $MAC_RE && "$name" != "${mac//:/-}" ]] || continue
            grep -q "^$mac " <<< "$paired" && continue
            ((nearby++ < 8)) || break
            device_json "$mac" "$name"
        done
    } | jq -s -c '{powered: true, devices: (unique_by(.mac) | sort_by((.paired | not), (.connected | not), .name))}'
}

push_list() {
    eww update bt_devices="$(list)"
}

valid_mac() {
    [[ "$1" =~ $MAC_RE ]] || { echo "Invalid address: $1" >&2; exit 1; }
}

notify() {
    notify-send -a "Bluetooth" "$@"
}

case "$1" in
    list)
        list
        ;;
    toggle)
        if powered; then
            bluetoothctl power off >/dev/null
        else
            rfkill unblock bluetooth 2>/dev/null
            bluetoothctl power on >/dev/null
        fi
        push_list
        ;;
    click)
        valid_mac "$2"
        device="$(device_json "$2" "")"
        eww update bt_busy="$2"
        if [[ "$(jq -r .connected <<< "$device")" == "true" ]]; then
            bluetoothctl disconnect "$2" >/dev/null
        elif [[ "$(jq -r .paired <<< "$device")" == "true" ]]; then
            bluetoothctl connect "$2" >/dev/null || notify "Could not connect" "Is the device on and in range?"
        elif bluetoothctl --timeout 20 pair "$2" >/dev/null; then
            bluetoothctl trust "$2" >/dev/null
            bluetoothctl connect "$2" >/dev/null || notify "Paired, but could not connect"
        else
            notify "Pairing failed" "Put the device in pairing mode and try again."
        fi
        eww update bt_busy=""
        push_list
        ;;
    scan)
        powered || exit 0
        eww update bt_scanning=true
        bluetoothctl --timeout "$SCAN_SECONDS" scan on >/dev/null
        push_list
        eww update bt_scanning=false
        ;;
    forget)
        valid_mac "$2"
        bluetoothctl remove "$2" >/dev/null
        push_list
        ;;
    *)
        echo "Usage: $0 {list|toggle|click <mac>|scan|forget <mac>}" >&2
        exit 1
        ;;
esac
