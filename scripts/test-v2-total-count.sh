#!/usr/bin/env bash
# test-v2-total-count.sh - Verify get_total_count query against v2 schema
# Tests: SELECT COUNT(*) FROM session_v2 WHERE time_archived IS NULL AND parent_id IS NULL

set -euo pipefail

DB_PATH="${1:-$HOME/.local/share/opencode/opencode.db}"

echo "=== test-v2-total-count ==="
echo "DB: $DB_PATH"
echo ""

COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session_v2 WHERE time_archived IS NULL AND parent_id IS NULL;")

if [[ -z "$COUNT" ]]; then
  echo "FAIL: empty result"
  exit 1
fi

echo "Total active top-level sessions: $COUNT"
echo ""
echo "PASS"
