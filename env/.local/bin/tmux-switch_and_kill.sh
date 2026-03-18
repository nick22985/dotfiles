#!/bin/bash
# Session history stack stored in tmux global env as colon-delimited string
# e.g. SESSION_STACK="main:work:dev"  (rightmost = most recent)
#
# Behaviour:
#   - Push current session onto the stack (no duplicates)
#   - Switch to the previous session (top of stack before current)
#   - Kill the session we just left
#   - Pop it off the stack

CURRENT=$(tmux display-message -p '#S')

# Read existing stack (may be empty / unset / corrupted)
RAW=$(tmux show-environment -g SESSION_STACK 2>/dev/null | sed 's/^SESSION_STACK=//')
# Treat removed-flag (-SESSION_STACK) or anything without a colon/word as empty
[[ "$RAW" == -* ]] && RAW=""

# ── Rebuild stack: dedup and strip empty/invalid entries ────────────────────
NEW_STACK=""
IFS=':' read -ra ENTRIES <<< "$RAW"
for entry in "${ENTRIES[@]}"; do
  # Skip empty, numeric-only (corrupted), or duplicate of current
  [[ -z "$entry" || "$entry" =~ ^[0-9]+$ || "$entry" == "$CURRENT" ]] && continue
  NEW_STACK="${NEW_STACK:+$NEW_STACK:}$entry"
done

# Push CURRENT onto the top (right end)
NEW_STACK="${NEW_STACK:+$NEW_STACK:}$CURRENT"

# Persist updated stack
tmux set-environment -g SESSION_STACK "$NEW_STACK"

# ── Find the most recent live target (walk stack right-to-left) ──────────────
IFS=':' read -ra FINAL <<< "$NEW_STACK"
STACK_LEN=${#FINAL[@]}
TARGET=""

for (( i = STACK_LEN - 2; i >= 0; i-- )); do
  candidate="${FINAL[$i]}"
  [[ -z "$candidate" ]] && continue
  if tmux has-session -t "$candidate" 2>/dev/null; then
    TARGET="$candidate"
    break
  fi
done

if [[ -z "$TARGET" ]]; then
  tmux display-message "No previous session in stack to switch to"
  exit 0
fi

# ── Confirm, switch, and kill ────────────────────────────────────────────────
# After killing CURRENT we also pop it from the stack
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
