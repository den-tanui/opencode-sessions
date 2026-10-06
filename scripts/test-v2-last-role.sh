#!/usr/bin/env bash
# test-v2-last-role.sh - Verify latest message role and completion extraction
# Tests:
#   last_role     = session_message.type of latest message (by seq)
#   last_completed = json_extract(data, '$.time.completed') on latest message
# v1 did: json_extract(data, '$.role') and json_extract(data, '$.time.completed') FROM message
# v2: type is a direct column on session_message; time.completed still JSON

set -euo pipefail

DB_PATH="${1:-$HOME/.local/share/opencode/opencode.db}"
SESSION_ID="${2:-}"

if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID=$(sqlite3 "$DB_PATH" "SELECT id FROM session_v2 WHERE time_archived IS NULL AND parent_id IS NULL LIMIT 1;")
  if [[ -z "$SESSION_ID" ]]; then
    echo "FAIL: no sessions found"
    exit 1
  fi
fi

echo "=== test-v2-last-role ==="
echo "Session: $SESSION_ID"
echo ""

# Test 1: Latest message type and completed using MAX(seq)
echo "--- Latest message (by MAX seq) ---"
sqlite3 -header -column "$DB_PATH" "
  SELECT sm.type as last_role,
         json_extract(sm.data, '\$.time.completed') as last_completed,
         sm.seq, sm.time_created
  FROM session_message sm
  WHERE sm.session_id = '${SESSION_ID}'
    AND sm.seq = (SELECT MAX(seq) FROM session_message WHERE session_id = '${SESSION_ID}')
  LIMIT 1;
"

echo ""

# Test 2: Show last 5 messages for context
echo "--- Last 5 messages ---"
sqlite3 -header -column "$DB_PATH" "
  SELECT sm.type, sm.seq,
         json_extract(sm.data, '\$.time.completed') as completed,
         substr(COALESCE(json_extract(sm.data, '\$.text'), ''), 1, 60) as text_preview
  FROM session_message sm
  WHERE sm.session_id = '${SESSION_ID}'
  ORDER BY sm.seq DESC
  LIMIT 5;
"

echo ""

# Test 3: Pipe-delimited (matches what format.sh expects)
echo "--- Pipe-delimited (last_role|last_completed) ---"
sqlite3 -separator '|' "$DB_PATH" "
  SELECT sm.type,
         COALESCE(CAST(json_extract(sm.data, '\$.time.completed') AS TEXT), 'null')
  FROM session_message sm
  WHERE sm.session_id = '${SESSION_ID}'
    AND sm.seq = (SELECT MAX(seq) FROM session_message WHERE session_id = '${SESSION_ID}')
  LIMIT 1;
"

echo ""
echo "PASS"
