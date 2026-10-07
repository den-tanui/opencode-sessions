#!/usr/bin/env bash
# sort_footer.sh — outputs footer text showing current sort state
# Usage: sort_footer.sh STATE_FILE

set -euo pipefail

STATE_FILE="$1"
sort_order=("time" "directory")
idx=$(cat "$STATE_FILE")
sort_field="${sort_order[$idx]}"
echo "CTRL-S: cycle sort (current: $sort_field) | ↑/↓: navigate | Enter: resume | Ctrl-o: new window | ?: toggle preview"
