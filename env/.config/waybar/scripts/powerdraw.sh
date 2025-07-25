#!/bin/bash

if [ -f /sys/class/power_supply/BAT*/current_now ]; then
  powerDraw="󰠰 $(($(cat /sys/class/power_supply/BAT*/current_now)/1000000))w"
fi


cat << EOF
{ "text":"$powerDraw", "tooltip":"power Draw $powerDraw"}  
EOF
