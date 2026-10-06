#!/usr/bin/env bash
# test-v2-session-directory.sh - Verify session directory lookup from session_v2
# Tests: SELECT directory FROM session_v2 WHERE id = ?
# Used by: bin/opencode_sessions.sh line 391

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

echo "=== test-v2-session-directory ==="
echo "Session: $SESSION_ID"
echo ""

DIRECTORY=$(sqlite3 "$DB_PATH" "SELECT directory FROM session_v2 WHERE id = '${SESSION_ID}';")

if [[ -z "$DIRECTORY" ]]; then
  echo "FAIL: directory not found for session $SESSION_ID"
  exit 1
fi

echo "Directory: $DIRECTORY"

if [[ -d "$DIRECTORY" ]]; then
  echo "Directory exists: yes"
else
  echo "WARNING: directory does not exist on filesystem"
fi

echo ""
echo "PASS"
