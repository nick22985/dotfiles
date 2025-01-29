#!/bin/bash
# PREV_SESSION=$(tmux display-message -p '#S')
# tmux set-environment -g PREV_SESSION "$PREV_SESSION"
# tmux switch-client -l
# tmux confirm-before -p "kill-session $PREV_SESSION? (y/n)" "run-shell \"tmux kill-session -t $PREV_SESSION\""
#

# Store the current session name
PREV_SESSION=$(tmux display-message -p '#S')

# Set the environment variable
tmux set-environment -g PREV_SESSION "$PREV_SESSION"

# Prompt for confirmation to switch to the last session and handle the result
tmux confirm-before -p "switch and kill session $PREV_SESSION? (y/n)" \
  "run-shell 'tmux switch-client -l; tmux kill-session -t $PREV_SESSION'" \
  2>/dev/null || true
