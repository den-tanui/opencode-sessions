#!/usr/bin/env bash
# Database queries for opencode-sessions

# Query all sessions - returns pipe-delimited fields
# Args: db_path days_filter show_all dir_filter
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
    SELECT m.session_id, m.id,
           json_extract(m.data, '\$.role') as role,
           json_extract(m.data, '\$.time.completed') as completed
    FROM message m
    INNER JOIN (
        SELECT session_id, MAX(time_created) as max_time
        FROM message
        GROUP BY session_id
    ) tm ON m.session_id = tm.session_id AND m.time_created = tm.max_time
),
has_running_question AS (
    SELECT p.session_id, COUNT(*) as cnt
    FROM part p
    WHERE json_extract(p.data, '\$.type') = 'tool'
      AND json_extract(p.data, '\$.tool') IN ('question','plan_exit')
      AND json_extract(p.data, '\$.state.status') = 'running'
      AND p.message_id IN (SELECT id FROM latest_msg)
    GROUP BY p.session_id
),
has_child_question AS (
    SELECT child_s.parent_id, COUNT(*) as cnt
    FROM part p
    JOIN message m ON m.id = p.message_id
    JOIN session child_s ON child_s.id = m.session_id
    WHERE child_s.parent_id IS NOT NULL
      AND child_s.time_archived IS NULL
      AND json_extract(p.data, '\$.type') = 'tool'
      AND json_extract(p.data, '\$.tool') IN ('question','plan_exit')
      AND json_extract(p.data, '\$.state.status') = 'running'
    GROUP BY child_s.parent_id
),
has_error AS (
    SELECT p.session_id, COUNT(*) as cnt
    FROM part p
    WHERE json_extract(p.data, '\$.type') = 'tool'
      AND json_extract(p.data, '\$.state.status') = 'error'
      AND p.message_id IN (SELECT id FROM latest_msg)
    GROUP BY p.session_id
),
child_count AS (
    SELECT parent_id, COUNT(*) as cnt
    FROM session
    WHERE parent_id IS NOT NULL AND time_archived IS NULL
    GROUP BY parent_id
),
last_model AS (
    SELECT m.session_id, json_extract(m.data, '\$.modelID') as model
    FROM message m
    INNER JOIN (
        SELECT session_id, MAX(time_created) as max_time
        FROM message
        WHERE json_extract(data, '\$.role') = 'assistant'
          AND json_extract(data, '\$.modelID') IS NOT NULL
        GROUP BY session_id
    ) tm ON m.session_id = tm.session_id AND m.time_created = tm.max_time
    WHERE json_extract(m.data, '\$.role') = 'assistant'
      AND json_extract(m.data, '\$.modelID') IS NOT NULL
)
SELECT s.id, s.title, s.directory, s.time_updated, s.time_created,
       p.worktree, p.name,
       COALESCE(lm.role, '') as last_role,
       COALESCE(lm.completed, 'null') as last_completed,
       COALESCE(hrq.cnt, 0) as has_running_question,
       COALESCE(hcq.cnt, 0) as has_child_question,
       COALESCE(he.cnt, 0) as has_error,
       COALESCE(cc.cnt, 0) as child_count,
       COALESCE(lm2.model, '') as model
FROM session s
JOIN project p ON s.project_id = p.id
LEFT JOIN latest_msg lm ON lm.session_id = s.id
LEFT JOIN has_running_question hrq ON hrq.session_id = s.id
LEFT JOIN has_child_question hcq ON hcq.parent_id = s.id
LEFT JOIN has_error he ON he.session_id = s.id
LEFT JOIN child_count cc ON cc.parent_id = s.id
LEFT JOIN last_model lm2 ON lm2.session_id = s.id
WHERE s.time_archived IS NULL AND s.parent_id IS NULL
AND s.time_updated >= $time_threshold
$(if [[ -n "$dir_filter" ]]; then echo "AND s.directory = '${dir_filter}'"; fi);
"
}

# Query directories - returns pipe-delimited fields
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
    SELECT s.directory, 
           COUNT(*) as session_count,
           MAX(s.time_updated) as latest_time,
           (SELECT json_extract(m.data, '\$.role') 
            FROM message m 
            WHERE m.session_id = (
                SELECT id FROM session 
                WHERE directory = s.directory 
                ORDER BY time_updated DESC LIMIT 1
            )
            ORDER BY time_created DESC LIMIT 1) as latest_role,
           (SELECT json_extract(m.data, '\$.time.completed') 
            FROM message m 
            WHERE m.session_id = (
                SELECT id FROM session 
                WHERE directory = s.directory 
                ORDER BY time_updated DESC LIMIT 1
            )
            ORDER BY time_created DESC LIMIT 1) as latest_completed
    FROM session s
    WHERE s.time_archived IS NULL 
      AND s.parent_id IS NULL
      AND s.time_updated >= $time_threshold
    GROUP BY s.directory
    ORDER BY latest_time DESC;
    "
}
