#!/usr/bin/env bash
# Emits JSON audio state on every PulseAudio change. Replaces three eww defpolls
# (volume @100ms, volume_muted @200ms, mic_muted @500ms) that were spawning
# ~15 pactl processes per second.

emit() {
  local vol mute mic_mute
  vol=$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | grep -oP '\d+(?=%)' | head -1)
  pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | grep -q 'yes' && mute=true || mute=false
  pactl get-source-mute @DEFAULT_SOURCE@ 2>/dev/null | grep -q 'yes' && mic_mute=true || mic_mute=false
  printf '{"volume":%s,"muted":"%s","mic_muted":"%s"}\n' "${vol:-50}" "$mute" "$mic_mute"
}

emit
pactl subscribe 2>/dev/null | while read -r line; do
  case "$line" in
    *"on sink"*|*"on source"*|*"on server"*) emit ;;
  esac
done
