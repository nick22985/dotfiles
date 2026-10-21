#!/bin/bash
# Opens/closes the calendar dropped from the clock and moves it between months.
#   toggle <index>      open on monitor <index>, or close if already open there
#   close               close it
#   close-later         close after a short delay unless the pointer came back
#   month -1|+1|today   show the previous/next/current month
#   goto <YYYY-MM-DD>   show that day's month with the day selected
#   refresh             fill in events, then download stale calendars and show the result

DATA=~/.config/eww/scripts/calendar-data.py

close() {
    eww close calendar-popup 2>/dev/null
    eww update cal_open=""
}

# Shows the month's events read from the calendars, if the popup still shows that month.
fill() {
    local month="$1" data
    data="$("$DATA" month "$month" 2>/dev/null)" || return
    [[ "$(eww get cal_month 2>/dev/null)" == "$month" ]] && eww update cal_data="$data"
}

# Shows a month with a day selected: from the cache at once, then filled in if it was stale.
render() {
    local month="$1" day="$2" data
    data="$("$DATA" month "$month" --quick 2>/dev/null)" || return
    eww update cal_month="$month" cal_sel="$day" cal_data="$data"
    [[ "$data" == *'"loading":true'* ]] && fill "$month"
}

# Today if it is in the month, otherwise the 1st.
default_day() {
    if [[ "$1" == "$(date +%Y-%m)" ]]; then
        date +%F
    else
        printf '%s-01' "$1"
    fi
}

case "$1" in
    toggle)
        index="${2:-0}"
        if [[ "$(eww get cal_open 2>/dev/null)" == "$index" ]]; then
            close
            exit 0
        fi
        close
        ~/.config/eww/scripts/control-center.sh close
        month="$(date +%Y-%m)"
        eww update cal_month="$month" cal_sel="$(date +%F)" \
            cal_data="$("$DATA" month "$month" --quick 2>/dev/null || echo '{}')"
        eww open calendar-popup --screen "$index"
        eww update cal_open="$index" cal_hover=false
        setsid -f "$0" refresh >/dev/null 2>&1
        ;;
    close)
        close
        ;;
    close-later)
        sleep 0.8
        [[ "$(eww get cal_hover 2>/dev/null)" == "true" ]] || close
        ;;
    month)
        if [[ "$2" == "today" ]]; then
            month="$(date +%Y-%m)"
        else
            current="$(eww get cal_month 2>/dev/null)"
            month="$(date -d "${current:-$(date +%Y-%m)}-01 ${2:-+1} month" +%Y-%m 2>/dev/null)" || exit 1
        fi
        render "$month" "$(default_day "$month")"
        ;;
    goto)
        [[ "$2" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || exit 1
        render "${2:0:7}" "$2"
        ;;
    refresh)
        month="$(eww get cal_month 2>/dev/null)"
        [[ -n "$month" ]] || exit 0
        [[ "$(eww get cal_data 2>/dev/null)" == *'"loading":true'* ]] && fill "$month"
        "$DATA" sync >/dev/null 2>&1
        # Cheap when nothing changed; also picks up download errors. The popup may be on
        # another month by now.
        fill "$(eww get cal_month 2>/dev/null)"
        ;;
    *)
        echo "Usage: $0 {toggle <index>|close|close-later|month -1|+1|today|goto <YYYY-MM-DD>|refresh}" >&2
        exit 1
        ;;
esac
