#!/usr/bin/env bash
# Database queries for opencode-sessions
# v2 schema: session_v2, session_message (no part table; content in JSON)

# Query all sessions - returns pipe-delimited fields
# Args: db_path days_filter show_all dir_filter
# Output: id|title|directory|time_updated|time_created|worktree|project_name|
#         last_role|last_completed|has_running_question|has_child_question|
#         has_error|child_count|model
query_all_sessions() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	local days_filter="${2:-14}"
	local show_all="${3:-false}"
	local dir_filter="${4:-}"

	local time_threshold
	if [[ "$show_all" == "true" ]]; then
		time_threshold=0
	else
		time_threshold=$((($(date +%s) - days_filter * 86400) * 1000))
	fi

	sqlite3 -separator '|' "$db_path" "
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
       COALESCE(json_extract(s.model, '\$.id'), '') as model
FROM session_v2 s
JOIN project p ON s.project_id = p.id
LEFT JOIN latest_msg lm ON lm.session_id = s.id
LEFT JOIN has_running_question hrq ON hrq.session_id = s.id
LEFT JOIN has_child_question hcq ON hcq.parent_id = s.id
LEFT JOIN has_error he ON he.session_id = s.id
LEFT JOIN child_count cc ON cc.parent_id = s.id
WHERE s.time_archived IS NULL AND s.parent_id IS NULL
AND s.time_updated >= $time_threshold
$(if [[ -n "$dir_filter" ]]; then echo "AND s.directory = '${dir_filter}'"; fi);
"
}

# Query directories - returns pipe-delimited fields
# Output: directory|session_count|latest_time|latest_role|latest_completed
query_directories() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	local days_filter="${2:-14}"
	local show_all="${3:-false}"

	local time_threshold
	if [[ "$show_all" == "true" ]]; then
		time_threshold=0
	else
		time_threshold=$((($(date +%s) - days_filter * 86400) * 1000))
	fi

	sqlite3 -separator '|' "$db_path" "
  WITH latest_session AS (
    SELECT s1.directory, s1.id as session_id, s1.time_updated
    FROM session_v2 s1
    INNER JOIN (
      SELECT directory, MAX(time_updated) as max_time
      FROM session_v2
      WHERE time_archived IS NULL AND parent_id IS NULL
        AND time_updated >= $time_threshold
      GROUP BY directory
    ) s2 ON s1.directory = s2.directory AND s1.time_updated = s2.max_time
  ),
  latest_msg AS (
    SELECT sm.session_id, sm.type as role,
           json_extract(sm.data, '\$.time.completed') as completed
    FROM session_message sm
    INNER JOIN (
      SELECT session_id, MAX(seq) as max_seq
      FROM session_message
      GROUP BY session_id
    ) lm ON sm.session_id = lm.session_id AND sm.seq = lm.max_seq
  )
  SELECT s.directory,
         COUNT(*) as session_count,
         MAX(s.time_updated) as latest_time,
         COALESCE(lm.role, '') as latest_role,
         COALESCE(CAST(lm.completed AS TEXT), 'null') as latest_completed
  FROM session_v2 s
  LEFT JOIN latest_session ls ON ls.directory = s.directory
  LEFT JOIN latest_msg lm ON lm.session_id = ls.session_id
  WHERE s.time_archived IS NULL
    AND s.parent_id IS NULL
    AND s.time_updated >= $time_threshold
  GROUP BY s.directory
  ORDER BY latest_time DESC;
    "
}
