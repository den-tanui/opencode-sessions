#!/usr/bin/env bash
# test-v2-sessions.sh - Verify full session listing query (query_all_sessions)
# Output: id|title|directory|time_updated|time_created|worktree|project_name|
#         last_role|last_completed|has_running_question|has_child_question|
#         has_error|child_count|model
#
# This is the big one — combines all the sub-queries into a single CTE chain.

set -euo pipefail

DB_PATH="${1:-$HOME/.local/share/opencode/opencode.db}"
DAYS_FILTER="${2:-14}"
SHOW_ALL="${3:-0}"
DIR_FILTER="${4:-}"

if [[ "$SHOW_ALL" == "true" || "$SHOW_ALL" == "1" ]]; then
  TIME_THRESHOLD=0
else
  TIME_THRESHOLD=$((($(date +%s) - DAYS_FILTER * 86400) * 1000))
fi

DIR_CLAUSE=""
if [[ -n "$DIR_FILTER" ]]; then
  DIR_CLAUSE="AND s.directory = '${DIR_FILTER}'"
fi

echo "=== test-v2-sessions ==="
echo "DB: $DB_PATH"
echo "Days filter: $DAYS_FILTER  (threshold: $TIME_THRESHOLD)"
echo "Dir filter: ${DIR_FILTER:-none}"
echo ""

# --- Full v2 query ---
SQL="
WITH latest_msg AS (
    SELECT sm.session_id, sm.type as role,
           json_extract(sm.data, '\$.time.completed') as completed
    FROM session_message sm
    INNER JOIN (
        SELECT session_id, MAX(seq) as max_seq
        FROM session_message
        GROUP BY session_id
    ) lm ON sm.session_id = lm.session_id AND sm.seq = lm.max_seq
),
has_running_question AS (
    SELECT sm.session_id, COUNT(*) as cnt
    FROM session_message sm,
         json_each(sm.data, '\$.content') as j
    WHERE sm.type = 'assistant'
      AND json_extract(j.value, '\$.type') = 'tool'
      AND json_extract(j.value, '\$.name') IN ('question', 'plan_exit')
      AND json_extract(j.value, '\$.state.status') = 'running'
      AND sm.session_id IN (
        SELECT session_id FROM latest_msg
        WHERE session_id IN (
          SELECT id FROM session_v2 WHERE time_archived IS NULL AND parent_id IS NULL
        )
      )
      AND sm.seq = (
        SELECT MAX(seq) FROM session_message
        WHERE session_id = sm.session_id AND type = 'assistant'
      )
    GROUP BY sm.session_id
),
has_child_question AS (
    SELECT child_s.parent_id, COUNT(*) as cnt
    FROM session_message sm
    JOIN session_v2 child_s ON child_s.id = sm.session_id
    CROSS JOIN json_each(sm.data, '\$.content') as j
    WHERE child_s.parent_id IS NOT NULL
      AND child_s.time_archived IS NULL
      AND sm.type = 'assistant'
      AND json_extract(j.value, '\$.type') = 'tool'
      AND json_extract(j.value, '\$.name') IN ('question', 'plan_exit')
      AND json_extract(j.value, '\$.state.status') = 'running'
      AND sm.seq = (
        SELECT MAX(seq) FROM session_message
        WHERE session_id = child_s.id AND type = 'assistant'
      )
    GROUP BY child_s.parent_id
),
has_error AS (
    SELECT sm.session_id, COUNT(*) as cnt
    FROM session_message sm,
         json_each(sm.data, '\$.content') as j
    WHERE sm.type = 'assistant'
      AND json_extract(j.value, '\$.type') = 'tool'
      AND json_extract(j.value, '\$.state.status') = 'error'
      AND sm.seq = (
        SELECT MAX(seq) FROM session_message
        WHERE session_id = sm.session_id AND type = 'assistant'
      )
    GROUP BY sm.session_id
),
child_count AS (
    SELECT parent_id, COUNT(*) as cnt
    FROM session_v2
    WHERE parent_id IS NOT NULL AND time_archived IS NULL
    GROUP BY parent_id
)
SELECT s.id, s.title, s.directory, s.time_updated, s.time_created,
       p.worktree, p.name,
       COALESCE(lm.role, '') as last_role,
       COALESCE(CAST(lm.completed AS TEXT), 'null') as last_completed,
       COALESCE(hrq.cnt, 0) as has_running_question,
       COALESCE(hcq.cnt, 0) as has_child_question,
       COALESCE(he.cnt, 0) as has_error,
       COALESCE(cc.cnt, 0) as child_count,
       COALESCE(s.model, '') as model
FROM session_v2 s
JOIN project p ON s.project_id = p.id
LEFT JOIN latest_msg lm ON lm.session_id = s.id
LEFT JOIN has_running_question hrq ON hrq.session_id = s.id
LEFT JOIN has_child_question hcq ON hcq.parent_id = s.id
LEFT JOIN has_error he ON he.session_id = s.id
LEFT JOIN child_count cc ON cc.parent_id = s.id
WHERE s.time_archived IS NULL AND s.parent_id IS NULL
AND s.time_updated >= ${TIME_THRESHOLD}
${DIR_CLAUSE}
"

echo "--- Pipe-delimited output ---"
sqlite3 -separator '|' "$DB_PATH" "$SQL"

echo ""
echo "--- Field count verification (should be 14) ---"
FIRST_ROW=$(sqlite3 -separator '|' "$DB_PATH" "$SQL LIMIT 1;")
if [[ -n "$FIRST_ROW" ]]; then
  FIELD_COUNT=$(echo "$FIRST_ROW" | awk -F'|' '{print NF}')
  echo "Fields per row: $FIELD_COUNT"
  if [[ "$FIELD_COUNT" -ne 14 ]]; then
    echo "FAIL: expected 14 fields, got $FIELD_COUNT"
    exit 1
  fi
fi

echo ""
echo "--- Readable output (first 5) ---"
sqlite3 -header -column "$DB_PATH" "$SQL LIMIT 5;"

echo ""
echo "PASS"
