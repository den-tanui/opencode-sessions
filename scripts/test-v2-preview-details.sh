#!/usr/bin/env bash
# test-v2-preview-details.sh - Verify session details query for preview pane
# Tests: SELECT id, title, directory, time_updated, time_created, permission, worktree, project_name
#        FROM session_v2 JOIN project

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

echo "=== test-v2-preview-details ==="
echo "Session: $SESSION_ID"
echo ""

# Test pipe-delimited (matches what preview.sh reads)
echo "--- Pipe-delimited output ---"
sqlite3 -separator '|' "$DB_PATH" "
  SELECT s.id, s.title, s.directory, s.time_updated, s.time_created,
         s.permission, p.worktree, p.name
  FROM session_v2 s
  JOIN project p ON s.project_id = p.id
  WHERE s.id = '${SESSION_ID}';
"

echo ""
echo "--- Readable output ---"
sqlite3 -header -column "$DB_PATH" "
  SELECT s.id, s.title, s.directory, s.time_updated, s.time_created,
         s.permission, p.worktree, p.name
  FROM session_v2 s
  JOIN project p ON s.project_id = p.id
  WHERE s.id = '${SESSION_ID}';
"

echo ""
echo "PASS"
