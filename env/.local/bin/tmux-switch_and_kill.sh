#!/bin/bash
CURRENT=$(tmux display-message -p '#S')

~/.local/bin/tmux-session-push "$CURRENT"

RAW=$(tmux show-environment -g SESSION_STACK 2>/dev/null | sed 's/^SESSION_STACK=//')
[[ "$RAW" == -* ]] && RAW=""

IFS=':' read -ra STACK <<< "$RAW"
TARGET=""

for (( i = ${#STACK[@]} - 1; i >= 0; i-- )); do
    candidate="${STACK[$i]}"
    [[ -z "$candidate" || "$candidate" == "$CURRENT" ]] && continue
    if tmux has-session -t "$candidate" 2>/dev/null; then
        TARGET="$candidate"
        break
    fi
done

if [[ -z "$TARGET" ]]; then
    tmux display-message "No previous session in stack to switch to"
    exit 0
fi

tmux confirm-before -p "switch to '$TARGET' and kill '$CURRENT'? (y/n)" \
  "run-shell '
    tmux switch-client -t $TARGET
    tmux kill-session -t $CURRENT
    STACK2=\$(tmux show-environment -g SESSION_STACK 2>/dev/null | sed \"s/^SESSION_STACK=//\")
    POPPED=\"\"
    IFS=: read -ra E <<< \"\$STACK2\"
    for e in \"\${E[@]}\"; do
      [ \"\$e\" = \"$CURRENT\" ] && continue
      POPPED=\"\${POPPED:+\$POPPED:}\$e\"
    done
    tmux set-environment -g SESSION_STACK \"\$POPPED\"
  '" \
  2>/dev/null || true
