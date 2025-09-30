#!/bin/bash

input="$*"

if [[ "$input" == !* ]]; then
    query="${input:1}"
    query="${query// /+}"
    xdg-open "https://www.google.com/search?q=$query"
    exit 0
fi

# Extract the first word (command)
cmd=$(echo "$input" | awk '{print $1}')

# If the first word is a valid executable, run the whole command line
if command -v "$cmd" >/dev/null 2>&1; then
    eval "$input"
    exit 0
fi

# Otherwise fallback to web search
query="${input// /+}"
xdg-open "https://www.google.com/search?q=$query"
