#!/usr/bin/env bash
# test-v2-directories.sh - Verify directory-level grouping query
# Tests: query_directories — groups by directory, counts sessions, finds latest role/completed
# Output: directory|session_count|latest_time|latest_role|latest_completed

set -euo pipefail

DB_PATH="${1:-$HOME/.local/share/opencode/opencode.db}"
DAYS_FILTER="${2:-14}"
SHOW_ALL="${3:-0}"

if [[ "$SHOW_ALL" == "true" || "$SHOW_ALL" == "1" ]]; then
  TIME_THRESHOLD=0
else
  TIME_THRESHOLD=$((($(date +%s) - DAYS_FILTER * 86400) * 1000))
fi

echo "=== test-v2-directories ==="
echo "DB: $DB_PATH"
echo "Days filter: $DAYS_FILTER  (threshold: $TIME_THRESHOLD)"
echo ""

# --- Test: Full directory query with v2 schema ---
echo "--- Pipe-delimited output (directory|session_count|latest_time|latest_role|latest_completed) ---"
sqlite3 -separator '|' "$DB_PATH" "
  WITH latest_session AS (
    SELECT s1.directory, s1.id as session_id, s1.time_updated
    FROM session_v2 s1
    INNER JOIN (
      SELECT directory, MAX(time_updated) as max_time
      FROM session_v2
      WHERE time_archived IS NULL AND parent_id IS NULL
        AND time_updated >= ${TIME_THRESHOLD}
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
    AND s.time_updated >= ${TIME_THRESHOLD}
  GROUP BY s.directory
  ORDER BY latest_time DESC;
"

echo ""
echo "--- Readable output ---"
sqlite3 -header -column "$DB_PATH" "
  WITH latest_session AS (
    SELECT s1.directory, s1.id as session_id, s1.time_updated
    FROM session_v2 s1
    INNER JOIN (
      SELECT directory, MAX(time_updated) as max_time
      FROM session_v2
      WHERE time_archived IS NULL AND parent_id IS NULL
        AND time_updated >= ${TIME_THRESHOLD}
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
    AND s.time_updated >= ${TIME_THRESHOLD}
  GROUP BY s.directory
  ORDER BY latest_time DESC;
"

echo ""
echo "PASS"
