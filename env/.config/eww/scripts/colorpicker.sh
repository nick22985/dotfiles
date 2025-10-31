#!/usr/bin/env bash

check() {
  command -v "$1" 1>/dev/null
}

notify() {
  check notify-send && {
    notify-send -a "Color Picker" "$@"
    return
  }
  echo "$@"
}

loc="$HOME/.cache/colorpicker"
[ -d "$loc" ] || mkdir -p "$loc"
[ -f "$loc/colors" ] || touch "$loc/colors"

limit=10

[[ $# -eq 1 && $1 = "-l" ]] && {
  cat "$loc/colors"
  exit
}

# For eww - output just the most recent color or empty if none
[[ $# -eq 1 && $1 = "-e" ]] && {
  if [ -s "$loc/colors" ]; then
    head -n 1 "$loc/colors"
  else
    echo ""
  fi
  exit
}

# For eww - output recent colors as JSON array
[[ $# -eq 1 && $1 = "-j" ]] && {
  if [ -s "$loc/colors" ]; then
    head -n 5 "$loc/colors" | jq -R . | jq -s .
  else
    echo "[]"
  fi
  exit
}



check hyprpicker || {
  notify "hyprpicker is not installed"
  exit
}

killall -q hyprpicker
color=$(hyprpicker)

check wl-copy && {
  echo "$color" | sed -z 's/\n//g' | wl-copy
}

prevColors=$(head -n $((limit - 1)) "$loc/colors")
echo "$color" >"$loc/colors"
echo "$prevColors" >>"$loc/colors"
sed -i '/^$/d' "$loc/colors"

# Update eww instead of waybar
eww update colorpicker_recent="$(head -n 1 "$loc/colors" 2>/dev/null || echo '')"

notify "Color picked: $color" "Copied to clipboard"