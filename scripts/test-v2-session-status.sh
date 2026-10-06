#!/usr/bin/env bash
# test-v2-session-status.sh - Verify status flags via json_each on content arrays
# Tests three CTEs that the main session query needs:
#   has_running_question — tool with name IN ('question','plan_exit') and state.status='running' in latest assistant message
#   has_child_question   — same but in non-archived child sessions' latest messages
#   has_error            — tool with state.status='error' in latest assistant message
# v1 used the `part` table; v2 embeds parts in session_message.data -> content array

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

echo "=== test-v2-session-status ==="
echo "Session: $SESSION_ID"
echo ""

# --- Test 1: has_running_question ---
# Find latest assistant message, then json_each on its content array
echo "--- has_running_question ---"
RQ=$(sqlite3 "$DB_PATH" "
  SELECT COUNT(*) FROM (
    SELECT json_extract(j.value, '\$.type') as ctype,
           json_extract(j.value, '\$.name') as cname,
           json_extract(j.value, '\$.state.status') as cstatus
    FROM session_message sm,
         json_each(sm.data, '\$.content') as j
    WHERE sm.session_id = '${SESSION_ID}'
      AND sm.type = 'assistant'
      AND sm.seq = (
        SELECT MAX(seq) FROM session_message
        WHERE session_id = '${SESSION_ID}' AND type = 'assistant'
      )
      AND json_extract(j.value, '\$.type') = 'tool'
      AND json_extract(j.value, '\$.name') IN ('question', 'plan_exit')
      AND json_extract(j.value, '\$.state.status') = 'running'
  );
")
echo "has_running_question: $RQ"

# --- Test 2: has_child_question ---
echo ""
echo "--- has_child_question ---"
CQ=$(sqlite3 "$DB_PATH" "
  SELECT COUNT(*) FROM (
    SELECT json_extract(j.value, '\$.type') as ctype,
           json_extract(j.value, '\$.name') as cname,
           json_extract(j.value, '\$.state.status') as cstatus
    FROM session_message sm
    JOIN session_v2 child ON child.id = sm.session_id
    CROSS JOIN json_each(sm.data, '\$.content') as j
    WHERE child.parent_id = '${SESSION_ID}'
      AND child.time_archived IS NULL
      AND sm.type = 'assistant'
      AND sm.seq = (
        SELECT MAX(seq) FROM session_message
        WHERE session_id = child.id AND type = 'assistant'
      )
      AND json_extract(j.value, '\$.type') = 'tool'
      AND json_extract(j.value, '\$.name') IN ('question', 'plan_exit')
      AND json_extract(j.value, '\$.state.status') = 'running'
  );
")
echo "has_child_question: $CQ"

# --- Test 3: has_error ---
echo ""
echo "--- has_error ---"
ERR=$(sqlite3 "$DB_PATH" "
  SELECT COUNT(*) FROM (
    SELECT json_extract(j.value, '\$.type') as ctype,
           json_extract(j.value, '\$.state.status') as cstatus
    FROM session_message sm,
         json_each(sm.data, '\$.content') as j
    WHERE sm.session_id = '${SESSION_ID}'
      AND sm.type = 'assistant'
      AND sm.seq = (
        SELECT MAX(seq) FROM session_message
        WHERE session_id = '${SESSION_ID}' AND type = 'assistant'
      )
      AND json_extract(j.value, '\$.type') = 'tool'
      AND json_extract(j.value, '\$.state.status') = 'error'
  );
")
echo "has_error: $ERR"

# --- Show the content array of the latest assistant message for debugging ---
echo ""
echo "--- Latest assistant message content items ---"
sqlite3 -header -column "$DB_PATH" "
  SELECT json_extract(j.value, '\$.type') as type,
         json_extract(j.value, '\$.name') as name,
         json_extract(j.value, '\$.state.status') as status
  FROM session_message sm,
       json_each(sm.data, '\$.content') as j
  WHERE sm.session_id = '${SESSION_ID}'
    AND sm.type = 'assistant'
    AND sm.seq = (
      SELECT MAX(seq) FROM session_message
      WHERE session_id = '${SESSION_ID}' AND type = 'assistant'
    );
"

echo ""
echo "PASS"
