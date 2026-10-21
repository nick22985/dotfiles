#!/bin/bash
# Screen recording state for the bar's recording pill. Recordings are wf-recorder runs started by
# ~/.local/bin/capture.
#   listen   {"active", "elapsed"} as JSON whenever either changes
#   stop     stop the recording

listen() {
    local pid seconds line last=""
    while true; do
        pid="$(pgrep -xo wf-recorder 2>/dev/null)"
        if [[ -n "$pid" ]]; then
            seconds="$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')"
            seconds="${seconds:-0}"
            if (( seconds >= 3600 )); then
                line="$(printf '{"active":true,"elapsed":"%d:%02d:%02d"}' $((seconds / 3600)) $((seconds % 3600 / 60)) $((seconds % 60)))"
            else
                line="$(printf '{"active":true,"elapsed":"%d:%02d"}' $((seconds / 60)) $((seconds % 60)))"
            fi
        else
            line='{"active":false,"elapsed":""}'
        fi
        [[ "$line" != "$last" ]] && printf '%s\n' "$line"
        last="$line"
        sleep 1
    done
}

case "$1" in
    listen) listen ;;
    stop) ~/.local/bin/capture --stop-recording 2>/dev/null || pkill -INT -x wf-recorder ;;
    *)
        echo "Usage: $0 {listen|stop}" >&2
        exit 1
        ;;
esac
