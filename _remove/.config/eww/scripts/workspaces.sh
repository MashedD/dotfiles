#!/usr/bin/env bash
active=$(hyprctl activeworkspace -j | jq '.id')
hyprctl workspaces -j | jq -c --argjson active "$active" '[.[] | {id: .id, active: (.id == $active)}] | sort_by(.id)'
