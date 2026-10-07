#!/usr/bin/env bash
# sort_cycle.sh — cycles sort order for fzf display file
# Usage: sort_cycle.sh STATE_FILE DISPLAY_FILE
# Sorts the display file on different columns and outputs result

set -euo pipefail

STATE_FILE="$1"
DISPLAY_FILE="$2"

idx=$(cat "$STATE_FILE")
idx=$(( (idx + 1) % 2 ))
echo "$idx" > "$STATE_FILE"

if [[ "$idx" == "0" ]]; then
    sort -t$'\t' -k3,3rn "$DISPLAY_FILE"
else
    sort -t$'\t' -k4,4 -k3,3rn "$DISPLAY_FILE"
fi
