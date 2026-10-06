#!/usr/bin/env bash
# test-v2-preview-status.sh - Verify full status computation for preview pane
# Tests the CASE block that returns: needs-input | error | working | idle
# v1 used part/message tables; v2 uses session_message + json_each on content array

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

echo "=== test-v2-preview-status ==="
echo "Session: $SESSION_ID"
echo ""

STATUS=$(sqlite3 "$DB_PATH" "
SELECT CASE
    -- needs-input: running question/plan_exit in latest assistant message
    WHEN (
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
        )
    ) > 0 THEN 'needs-input'

    -- needs-input: running question in child sessions
    WHEN (
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
            AND json_extract(j.value, '\$.type') = 'tool'
            AND json_extract(j.value, '\$.name') IN ('question', 'plan_exit')
            AND json_extract(j.value, '\$.state.status') = 'running'
            AND sm.seq = (
              SELECT MAX(seq) FROM session_message
              WHERE session_id = child.id AND type = 'assistant'
            )
        )
    ) > 0 THEN 'needs-input'

    -- error: tool with error status in latest assistant message
    WHEN (
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
        )
    ) > 0 THEN 'error'

    -- working: last message is assistant with no completion time
    WHEN (
        SELECT sm.type FROM session_message sm
        WHERE sm.session_id = '${SESSION_ID}'
          AND sm.seq = (SELECT MAX(seq) FROM session_message WHERE session_id = '${SESSION_ID}')
        LIMIT 1
    ) = 'assistant' AND (
        SELECT json_extract(sm.data, '\$.time.completed')
        FROM session_message sm
        WHERE sm.session_id = '${SESSION_ID}'
          AND sm.seq = (SELECT MAX(seq) FROM session_message WHERE session_id = '${SESSION_ID}')
        LIMIT 1
    ) IS NULL THEN 'working'

    -- working: last message is user
    WHEN (
        SELECT sm.type FROM session_message sm
        WHERE sm.session_id = '${SESSION_ID}'
          AND sm.seq = (SELECT MAX(seq) FROM session_message WHERE session_id = '${SESSION_ID}')
        LIMIT 1
    ) = 'user' THEN 'working'

    ELSE 'idle'
END as status;
")

echo "Computed status: $STATUS"
echo ""

# --- Debug: show latest message info ---
echo "--- Latest message ---"
sqlite3 -header -column "$DB_PATH" "
  SELECT sm.type, sm.seq,
         json_extract(sm.data, '\$.time.completed') as completed,
         substr(COALESCE(json_extract(sm.data, '\$.text'), ''), 1, 60) as text_preview
  FROM session_message sm
  WHERE sm.session_id = '${SESSION_ID}'
    AND sm.seq = (SELECT MAX(seq) FROM session_message WHERE session_id = '${SESSION_ID}')
  LIMIT 1;
"

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
