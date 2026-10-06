#!/usr/bin/env bash
# test-v2-model.sh - Verify model extraction from session_v2.model column
# Tests: SELECT model FROM session_v2 WHERE id = ?
# v1 did: json_extract(data, '$.modelID') FROM message — no longer needed

set -euo pipefail

DB_PATH="${1:-$HOME/.local/share/opencode/opencode.db}"
SESSION_ID="${2:-}"

# Pick first active session if none provided
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID=$(sqlite3 "$DB_PATH" "SELECT id FROM session_v2 WHERE time_archived IS NULL AND parent_id IS NULL LIMIT 1;")
  if [[ -z "$SESSION_ID" ]]; then
    echo "FAIL: no sessions found"
    exit 1
  fi
fi

echo "=== test-v2-model ==="
echo "Session: $SESSION_ID"
echo ""

# Test 1: Direct column from session_v2
MODEL_DIRECT=$(sqlite3 "$DB_PATH" "SELECT model FROM session_v2 WHERE id = '${SESSION_ID}';")

echo "session_v2.model: '${MODEL_DIRECT}'"

# Test 2: Show all distinct models across sessions for comparison
echo ""
echo "All distinct models in active sessions:"
sqlite3 -header -column "$DB_PATH" "
  SELECT model, COUNT(*) as count
  FROM session_v2
  WHERE time_archived IS NULL AND parent_id IS NULL
  GROUP BY model
  ORDER BY count DESC;
"

echo ""
if [[ -n "$MODEL_DIRECT" ]]; then
  echo "PASS: model column populated"
else
  echo "WARN: model column is NULL for this session (may be valid if no assistant message was sent)"
fi
