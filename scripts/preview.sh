#!/usr/bin/env bash
# preview.sh - Preview helper for opencode-sessions-fzf.sh
# Usage: bash preview.sh "<tab-delimited fzf line>"
#
# Expected input format:
# session_id\tstatus\ttime_ago\trepo\ttitle\tmodel\tdirectory\tchild_count

set -euo pipefail

DB_PATH="${HOME}/.local/share/opencode/opencode.db"

# Color codes (self-contained, no dependency on parent shell)
# Respects USE_ANSI env var passed from parent script
if [[ "${USE_ANSI:-false}" == "true" ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  CYAN='\033[0;36m'
  MAGENTA='\033[0;35m'
  WHITE='\033[1;37m'
  DIM='\033[2m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  CYAN=''
  MAGENTA=''
  WHITE=''
  DIM=''
  BOLD=''
  RESET=''
fi

# Parse input - fzf passes the full line, we extract session_id from first field
INPUT="${1:-}"
SESSION_ID="${INPUT%%	*}" # First tab-delimited field

if [[ -z "$SESSION_ID" ]]; then
	echo -e "${RED}No session selected${RESET}"
	exit 0
fi

# Get session details from DB
SESSION_DATA=$(sqlite3 -separator '|' "$DB_PATH" "
    SELECT s.id, s.title, s.directory, s.time_updated, s.time_created,
           s.permission, p.worktree, p.name
    FROM session_v2 s
    JOIN project p ON s.project_id = p.id
    WHERE s.id = '${SESSION_ID}';
" 2>/dev/null) || true

if [[ -z "$SESSION_DATA" ]]; then
	echo -e "${RED}Session not found: ${SESSION_ID}${RESET}"
	exit 0
fi

IFS='|' read -r id title directory time_updated time_created permission worktree project_name <<<"$SESSION_DATA"

# Get status (recompute for accuracy in preview)
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

# Status icon
case "$STATUS" in
needs-input) STATUS_ICON="${YELLOW}🟡${RESET} ${YELLOW}needs-input${RESET}" ;;
error) STATUS_ICON="${RED}🔴${RESET} ${RED}error${RESET}" ;;
working) STATUS_ICON="${GREEN}🟢${RESET} ${GREEN}working${RESET}" ;;
idle) STATUS_ICON="${DIM}⚪${RESET} ${DIM}idle${RESET}" ;;
*) STATUS_ICON="${DIM}⚪${RESET} ${DIM}unknown${RESET}" ;;
esac

# Model — extract $.id from JSON object in session_v2.model column
MODEL=$(sqlite3 "$DB_PATH" "
    SELECT json_extract(model, '\$.id') FROM session_v2 WHERE id = '${SESSION_ID}';
" 2>/dev/null) || true

# Shorten model
if [[ -n "$MODEL" ]]; then
	[[ "$MODEL" == *"/"* ]] && MODEL="${MODEL##*/}"
	MODEL="${MODEL#claude-}"
	MODEL="${MODEL#antigravity-}"
	MODEL="${MODEL//codex-/}"
	MODEL="${MODEL%-preview}"
fi
[[ -z "$MODEL" ]] && MODEL="${DIM}(none)${RESET}"

# Relative time
now=$(date +%s)
diff=$((now - time_updated / 1000))
if ((diff < 60)); then
	TIME_AGO="${diff}s ago"
elif ((diff < 3600)); then
	TIME_AGO="$((diff / 60))m ago"
elif ((diff < 86400)); then
	TIME_AGO="$((diff / 3600))h ago"
elif ((diff < 604800)); then
	TIME_AGO="$((diff / 86400))d ago"
else
	TIME_AGO=$(date -d "@$((time_updated / 1000))" '+%Y-%m-%d' 2>/dev/null || echo "$time_updated")
fi

# Child session count
CHILD_COUNT=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM session_v2
    WHERE parent_id = '${SESSION_ID}' AND time_archived IS NULL;
")

# Last message preview — branch on message type for v2 schema
# User/system/synthetic: flat $.text; assistant: $.content[N].text
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
" 2>/dev/null) || true
[[ -z "$LAST_MSG" ]] && LAST_MSG="${DIM}(no messages)${RESET}"
# Truncate to 300 chars
if [[ ${#LAST_MSG} -gt 300 ]]; then
	LAST_MSG="${LAST_MSG:0:300}${DIM}...${RESET}"
fi

# Modified files — v2: session_message content array tool items
MODIFIED_FILES=$(sqlite3 "$DB_PATH" "
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
" 2>/dev/null) || true

# Child sessions list
CHILD_SESSIONS=$(sqlite3 -separator '|' "$DB_PATH" "
    SELECT s.id, s.title, s.directory
    FROM session_v2 s
    WHERE s.parent_id = '${SESSION_ID}' AND s.time_archived IS NULL
    ORDER BY s.time_created DESC
    LIMIT 5;
" 2>/dev/null) || true

# ─── Output ───────────────────────────────────────────────────────────────────

echo -e "${BOLD}${WHITE}Session:${RESET} ${title}"
echo -e "${WHITE}ID:${RESET}       ${DIM}${id}${RESET}"
echo -e "${WHITE}Status:${RESET}   ${STATUS_ICON}"
echo -e "${WHITE}Model:${RESET}    ${MODEL}"
echo -e "${WHITE}Dir:${RESET}      ${DIM}${directory}${RESET}"
echo -e "${WHITE}Updated:${RESET}  ${TIME_AGO}"
echo -e "${WHITE}Children:${RESET} ${CHILD_COUNT}"
echo ""
echo -e "${BOLD}${WHITE}Last Message:${RESET}"
echo -e "${DIM}${LAST_MSG}${RESET}"
echo ""

# Modified files
if [[ -n "$MODIFIED_FILES" ]]; then
	file_count=$(echo "$MODIFIED_FILES" | wc -l)
	echo -e "${BOLD}${WHITE}Modified Files (${file_count}):${RESET}"
	echo "$MODIFIED_FILES" | head -10 | while read -r f; do
		echo -e "  ${CYAN}${f}${RESET}"
	done
	if ((file_count > 10)); then
		echo -e "  ${DIM}... and $((file_count - 10)) more${RESET}"
	fi
else
	echo -e "${BOLD}${WHITE}Modified Files:${RESET} ${DIM}(none)${RESET}"
fi
echo ""

# Child sessions
if [[ -n "$CHILD_SESSIONS" ]]; then
	echo -e "${BOLD}${WHITE}Child Sessions:${RESET}"
	echo "$CHILD_SESSIONS" | while IFS='|' read -r cid ctitle cdir; do
		local_repo="${cdir##*/}"
		echo -e "  ${MAGENTA}${ctitle}${RESET} ${DIM}(${local_repo})${RESET}"
	done
	if ((CHILD_COUNT > 5)); then
		echo -e "  ${DIM}... and $((CHILD_COUNT - 5)) more${RESET}"
	fi
else
	echo -e "${BOLD}${WHITE}Child Sessions:${RESET} ${DIM}(none)${RESET}"
fi
echo ""
