#!/usr/bin/env bash
# test-v2-preview-child-sessions.sh - Verify child sessions list for preview pane
# Tests: SELECT id, title, directory FROM session_v2 WHERE parent_id = ? AND time_archived IS NULL

set -euo pipefail

DB_PATH="${1:-$HOME/.local/share/opencode/opencode.db}"
SESSION_ID="${2:-}"

if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID=$(sqlite3 "$DB_PATH" "SELECT parent_id FROM session_v2 WHERE parent_id IS NOT NULL AND time_archived IS NULL LIMIT 1;")
  if [[ -z "$SESSION_ID" ]]; then
    SESSION_ID=$(sqlite3 "$DB_PATH" "SELECT id FROM session_v2 WHERE time_archived IS NULL AND parent_id IS NULL LIMIT 1;")
  fi
fi

echo "=== test-v2-preview-child-sessions ==="
echo "Session: $SESSION_ID"
echo ""

echo "--- Pipe-delimited output ---"
sqlite3 -separator '|' "$DB_PATH" "
  SELECT s.id, s.title, s.directory
  FROM session_v2 s
  WHERE s.parent_id = '${SESSION_ID}' AND s.time_archived IS NULL
  ORDER BY s.time_created DESC
  LIMIT 5;
"

echo ""
echo "--- Readable output ---"
sqlite3 -header -column "$DB_PATH" "
  SELECT s.id, s.title, s.directory, s.time_created
  FROM session_v2 s
  WHERE s.parent_id = '${SESSION_ID}' AND s.time_archived IS NULL
  ORDER BY s.time_created DESC
  LIMIT 5;
"

echo ""
echo "PASS"
