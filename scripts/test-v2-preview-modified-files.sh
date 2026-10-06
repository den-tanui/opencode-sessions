#!/usr/bin/env bash
# test-v2-preview-modified-files.sh - Verify modified files extraction for preview pane
# Tests: find files modified by tool calls (edit, write, apply_patch) in session messages
# v1: queried part table for $.files and $.state.input.filePath
# v2: session_message.data -> content array -> tool items with state.input

set -euo pipefail

DB_PATH="${1:-$HOME/.local/share/opencode/opencode.db}"
SESSION_ID="${2:-}"

if [[ -z "$SESSION_ID" ]]; then
  # Find a session that has tool calls
  SESSION_ID=$(sqlite3 "$DB_PATH" "
    SELECT DISTINCT sm.session_id
    FROM session_message sm,
         json_each(sm.data, '\$.content') as j
    WHERE sm.type = 'assistant'
      AND json_extract(j.value, '\$.type') = 'tool'
      AND json_extract(j.value, '\$.name') IN ('edit', 'write', 'apply_patch')
      AND json_extract(j.value, '\$.state.status') = 'completed'
    LIMIT 1;
  ")
  if [[ -z "$SESSION_ID" ]]; then
    echo "FAIL: no sessions with file-editing tools found"
    exit 1
  fi
fi

echo "=== test-v2-preview-modified-files ==="
echo "Session: $SESSION_ID"
echo ""

# --- Test 1: Extract file paths from tool calls ---
# Try state.input.filePath first, then state.input.path, then state.input.file
echo "--- Modified files (from tool state.input) ---"
sqlite3 -header -column "$DB_PATH" "
  SELECT DISTINCT
    json_extract(j.value, '\$.name') as tool_name,
    COALESCE(
      json_extract(j.value, '\$.state.input.filePath'),
      json_extract(j.value, '\$.state.input.path'),
      json_extract(j.value, '\$.state.input.file'),
      json_extract(j.value, '\$.state.input.command')
    ) as file_or_input
  FROM session_message sm,
       json_each(sm.data, '\$.content') as j
  WHERE sm.session_id = '${SESSION_ID}'
    AND sm.type = 'assistant'
    AND json_extract(j.value, '\$.type') = 'tool'
    AND json_extract(j.value, '\$.name') IN ('edit', 'write', 'apply_patch', 'bash', 'read')
    AND json_extract(j.value, '\$.state.status') = 'completed'
  ORDER BY file_or_input;
"

echo ""

# --- Test 2: Show all tool calls for debugging ---
echo "--- All tool calls in session ---"
sqlite3 -header -column "$DB_PATH" "
  SELECT json_extract(j.value, '\$.name') as tool_name,
         json_extract(j.value, '\$.state.status') as status,
         json_extract(j.value, '\$.state.input.filePath') as file_path,
         json_extract(j.value, '\$.state.input.path') as path,
         json_extract(j.value, '\$.state.input.command') as command
  FROM session_message sm,
       json_each(sm.data, '\$.content') as j
  WHERE sm.session_id = '${SESSION_ID}'
    AND sm.type = 'assistant'
    AND json_extract(j.value, '\$.type') = 'tool'
  ORDER BY sm.seq;
"

echo ""

# --- Test 3: Pipe-delimited (distinct file paths only) ---
echo "--- Pipe-delimited file paths ---"
sqlite3 -separator '|' "$DB_PATH" "
  SELECT DISTINCT
    COALESCE(
      json_extract(j.value, '\$.state.input.filePath'),
      json_extract(j.value, '\$.state.input.path'),
      json_extract(j.value, '\$.state.input.file')
    ) as file_path
  FROM session_message sm,
       json_each(sm.data, '\$.content') as j
  WHERE sm.session_id = '${SESSION_ID}'
    AND sm.type = 'assistant'
    AND json_extract(j.value, '\$.type') = 'tool'
    AND json_extract(j.value, '\$.name') IN ('edit', 'write', 'apply_patch')
    AND json_extract(j.value, '\$.state.status') = 'completed'
    AND COALESCE(
      json_extract(j.value, '\$.state.input.filePath'),
      json_extract(j.value, '\$.state.input.path'),
      json_extract(j.value, '\$.state.input.file')
    ) IS NOT NULL;
"

echo ""
echo "PASS"
