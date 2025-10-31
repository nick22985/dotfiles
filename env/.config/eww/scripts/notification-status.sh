#!/bin/bash

# Monitor swaync status and filter out cc-open class
swaync-client -swb 2>/dev/null | while read -r line; do
    if [[ -n "$line" ]]; then
        # Use jq to process the status and extract the first non-cc-open class
        echo "$line" | jq -c '{
            class: (
                if (.class | type) == "array" then
                    (.class | map(select(. != "cc-open")) | .[0] // "none")
                else
                    .class
                end
            ),
            text: .text,
            tooltip: .tooltip
        }'
    else
        echo '{"class": "none"}'
    fi
done
