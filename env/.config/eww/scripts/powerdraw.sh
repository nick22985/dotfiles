#!/bin/bash

# Battery power in watts: power_now (µW) where the battery reports it, otherwise current_now (µA) × voltage_now (µV).
battery=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -n1)
powerDraw=""
tooltip="No battery"

if [ -n "$battery" ]; then
  status=$(cat "$battery/status" 2>/dev/null)
  if [ -r "$battery/power_now" ]; then
    watts=$(awk '{ printf "%.1f", $1 / 1000000 }' "$battery/power_now")
  elif [ -r "$battery/current_now" ] && [ -r "$battery/voltage_now" ]; then
    watts=$(awk -v c="$(cat "$battery/current_now")" -v v="$(cat "$battery/voltage_now")" 'BEGIN { printf "%.1f", c * v / 1000000000000 }')
  fi

  case "$status" in
    Discharging)
      powerDraw="󰠰 ${watts}w"
      tooltip="Power draw ${watts}W"
      ;;
    Charging)
      powerDraw="󰂄 +${watts}w"
      tooltip="Charging at ${watts}W"
      ;;
    *)
      powerDraw="󰚥"
      tooltip="On AC power ($status)"
      ;;
  esac
fi

cat << EOF
{ "text":"$powerDraw", "tooltip":"$tooltip"}
EOF
