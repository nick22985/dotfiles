#!/bin/bash
source "$HOME/.local/bin/tmux-session-stack"

CURRENT=$(tmux display-message -p '#S')

~/.local/bin/tmux-session-push "$CURRENT"

TARGET=$(prev_live_session "$CURRENT")

if [[ -z "$TARGET" ]]; then
    while IFS= read -r s; do
        [[ -z "$s" || "$s" == "$CURRENT" ]] && continue
        TARGET="$s"
        break
    done < <(tmux list-sessions -F '#S' 2>/dev/null)
fi

if [[ -z "$TARGET" ]]; then
    tmux display-message "No other session to switch to"
    exit 0
fi

tmux confirm-before -p "switch to '$TARGET' and kill '$CURRENT'? (y/n)" \
  "run-shell '
    tmux switch-client -t $TARGET
    tmux kill-session -t $CURRENT
    source $HOME/.local/bin/tmux-session-stack
    session_pop $CURRENT
  '" \
  2>/dev/null || true
