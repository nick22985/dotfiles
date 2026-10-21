#!/bin/bash
# Clipboard page of the control center, backed by cliphist.
#   list          the newest entries as [{"id", "text"}]
#   copy <id>     put an entry back on the clipboard
#   delete <id>   remove an entry from the history
#   wipe          clear the history

LIMIT=30

valid_id() {
    [[ "$1" =~ ^[0-9]+$ ]] || { echo "Invalid entry id: $1" >&2; exit 1; }
}

list() {
    cliphist list 2>/dev/null | head -n "$LIMIT" | jq -R -s -c '
        split("\n")
        | map(select(test("^[0-9]+\t"))
            | capture("^(?<id>[0-9]+)\t(?<text>.*)$")
            | .text |= (gsub("\\s+"; " ") | ltrimstr(" ")))'
}

push_list() {
    eww update clip_entries="$(list)"
}

case "$1" in
    list)
        list
        ;;
    copy)
        valid_id "$2"
        printf '%s\t\n' "$2" | cliphist decode | wl-copy
        ;;
    delete)
        valid_id "$2"
        cliphist list | grep -m1 "^$2"$'\t' | cliphist delete
        push_list
        ;;
    wipe)
        cliphist wipe
        push_list
        ;;
    *)
        echo "Usage: $0 {list|copy <id>|delete <id>|wipe}" >&2
        exit 1
        ;;
esac
