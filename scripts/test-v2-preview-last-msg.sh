#!/usr/bin/env bash
# test-v2-preview-last-msg.sh - Verify last message text extraction for preview pane
# Tests: get the last meaningful text message from a session
# v1: json_extract(p.data, '$.text') FROM part p JOIN message m ...
# v2: user/synthetic messages have flat $.text; assistant messages have $.content[N].text

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

echo "=== test-v2-preview-last-msg ==="
echo "Session: $SESSION_ID"
echo ""

# --- Test 1: Get latest message, branch on type ---
echo "--- Last message text (branching on type) ---"
LAST_MSG=$(sqlite3 "$DB_PATH" "
  SELECT
    CASE
      WHEN sm.type IN ('user', 'system', 'synthetic') THEN
        json_extract(sm.data, '\$.text')
      WHEN sm.type = 'assistant' THEN
        (SELECT json_extract(j.value, '\$.text')
         FROM json_each(sm.data, '\$.content') as j
         WHERE json_extract(j.value, '\$.type') = 'text'
           AND json_extract(j.value, '\$.text') IS NOT NULL
           AND json_extract(j.value, '\$.text') != ''
           AND json_extract(j.value, '\$.text') NOT LIKE '<%'
         ORDER BY json_extract(j.value, '\$.time.created') DESC
         LIMIT 1)
      ELSE NULL
    END as last_text
  FROM session_message sm
  WHERE sm.session_id = '${SESSION_ID}'
    AND sm.seq = (SELECT MAX(seq) FROM session_message WHERE session_id = '${SESSION_ID}')
  LIMIT 1;
")

if [[ -n "$LAST_MSG" ]]; then
  echo "Last message text (truncated to 300):"
  echo "${LAST_MSG:0:300}"
else
  echo "(no text found in latest message)"
fi

echo ""

# --- Test 2: Show last 5 messages with text for context ---
echo "--- Last 5 messages ---"
sqlite3 -header -column "$DB_PATH" "
  SELECT sm.type, sm.seq,
         CASE
           WHEN sm.type IN ('user', 'system', 'synthetic') THEN
             substr(json_extract(sm.data, '\$.text'), 1, 80)
           WHEN sm.type = 'assistant' THEN
             substr(
               (SELECT json_extract(j.value, '\$.text')
                FROM json_each(sm.data, '\$.content') as j
                WHERE json_extract(j.value, '\$.type') = 'text'
                LIMIT 1), 1, 80)
           ELSE '(non-text)'
         END as text_preview
  FROM session_message sm
  WHERE sm.session_id = '${SESSION_ID}'
  ORDER BY sm.seq DESC
  LIMIT 5;
"

echo ""

# --- Test 3: Find last text message across ALL messages (not just latest) ---
echo "--- Last text message across all messages (fallback) ---"
sqlite3 -header -column "$DB_PATH" "
  SELECT sm.type, sm.seq,
         CASE
           WHEN sm.type IN ('user', 'system', 'synthetic') THEN
             substr(json_extract(sm.data, '\$.text'), 1, 120)
           WHEN sm.type = 'assistant' THEN
             substr(
               (SELECT json_extract(j.value, '\$.text')
                FROM json_each(sm.data, '\$.content') as j
                WHERE json_extract(j.value, '\$.type') = 'text'
                  AND json_extract(j.value, '\$.text') NOT LIKE '<%'
                LIMIT 1), 1, 120)
           ELSE NULL
         END as text_preview
  FROM session_message sm
  WHERE sm.session_id = '${SESSION_ID}'
    AND (
      (sm.type IN ('user', 'system', 'synthetic') AND json_extract(sm.data, '\$.text') IS NOT NULL
         AND json_extract(sm.data, '\$.text') != '' AND json_extract(sm.data, '\$.text') NOT LIKE '<%')
      OR
      (sm.type = 'assistant' AND EXISTS (
        SELECT 1 FROM json_each(sm.data, '\$.content') as j
        WHERE json_extract(j.value, '\$.type') = 'text'
          AND json_extract(j.value, '\$.text') IS NOT NULL
          AND json_extract(j.value, '\$.text') != ''
          AND json_extract(j.value, '\$.text') NOT LIKE '<%'
      ))
    )
  ORDER BY sm.seq DESC
  LIMIT 3;
"

echo ""
echo "PASS"
