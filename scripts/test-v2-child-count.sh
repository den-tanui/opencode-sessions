#!/usr/bin/env bash
# test-v2-child-count.sh - Verify child session count from session_v2
# Tests: SELECT COUNT(*) FROM session_v2 WHERE parent_id = ? AND time_archived IS NULL

set -euo pipefail

DB_PATH="${1:-$HOME/.local/share/opencode/opencode.db}"
SESSION_ID="${2:-}"

# Pick first active session with children if none provided
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID=$(sqlite3 "$DB_PATH" "
    SELECT parent_id FROM session_v2
    WHERE parent_id IS NOT NULL AND time_archived IS NULL
    LIMIT 1;
  ")
  if [[ -z "$SESSION_ID" ]]; then
    SESSION_ID=$(sqlite3 "$DB_PATH" "SELECT id FROM session_v2 WHERE time_archived IS NULL AND parent_id IS NULL LIMIT 1;")
  fi
fi

echo "=== test-v2-child-count ==="
echo "Session: $SESSION_ID"
echo ""

CHILD_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session_v2 WHERE parent_id = '${SESSION_ID}' AND time_archived IS NULL;")

echo "Child count: $CHILD_COUNT"
echo ""

# Show child sessions for verification
echo "Child sessions:"
sqlite3 -header -column "$DB_PATH" "
  SELECT id, title, directory, time_created
  FROM session_v2
  WHERE parent_id = '${SESSION_ID}' AND time_archived IS NULL
  ORDER BY time_created DESC;
"

echo ""
echo "PASS"
