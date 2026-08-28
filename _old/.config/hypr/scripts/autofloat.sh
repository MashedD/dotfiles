#!/usr/bin/env bash
# autofloat: float new windows unless tiling exceptions
# Workaround for broken legacy window rules in Hyprland 0.55

TILING_CLASSES="^(kitty|firefox)$"

INSTANCE=$(ls -1 /tmp/hypr/ 2>/dev/null | head -1)
[[ -z "$INSTANCE" ]] && exit 1

socat -U - UNIX-CONNECT:"/tmp/hypr/$INSTANCE/.socket2.sock" 2>/dev/null | while read -r line; do
  [[ "$line" != openwindow>>* ]] && continue
  data="${line#openwindow>>}"
  addr="${data%%,*}"
  remainder="${data#*,}"
  remainder="${remainder#*,}"
  class="${remainder%%,*}"
  [[ "$class" =~ $TILING_CLASSES ]] && continue
  hyprctl dispatch setfloating "address:$addr" 2>/dev/null
  sleep 0.1
  hyprctl dispatch centerwindow "address:$addr" 2>/dev/null
done
