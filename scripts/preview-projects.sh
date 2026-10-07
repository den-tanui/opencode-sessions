#!/usr/bin/env bash
# preview-projects.sh - Preview helper for project view
# Usage: bash preview-projects.sh "<tab-delimited fzf line>"
#
# Expected input format:
# project_id\tstatus\ttime_ago\tname\tsession_count\tmodel\tworktree\tlatest_time

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

# Parse input - fzf passes the full line, we extract project_id from first field
INPUT="${1:-}"
PROJECT_ID="${INPUT%%	*}" # First tab-delimited field

if [[ -z "$PROJECT_ID" ]]; then
	echo -e "${RED}No project selected${RESET}"
	exit 0
fi

# Get project details from DB
PROJECT_DATA=$(sqlite3 -separator '|' "$DB_PATH" "
    SELECT p.id, p.name, p.worktree, p.vcs, p.time_created, p.time_updated
    FROM project p
    WHERE p.id = '${PROJECT_ID}';
" 2>/dev/null) || true

if [[ -z "$PROJECT_DATA" ]]; then
	echo -e "${RED}Project not found: ${PROJECT_ID}${RESET}"
	exit 0
fi

IFS='|' read -r id name worktree vcs time_created time_updated <<<"$PROJECT_DATA"

# Get session count
SESSION_COUNT=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM session_v2
    WHERE project_id = '${PROJECT_ID}'
      AND time_archived IS NULL AND parent_id IS NULL;
")

# Get latest session status
STATUS=$(sqlite3 "$DB_PATH" "
SELECT CASE
    WHEN (
        SELECT COUNT(*) FROM (
          SELECT json_extract(j.value, '\$.type') as ctype,
                 json_extract(j.value, '\$.name') as cname,
                 json_extract(j.value, '\$.state.status') as cstatus
          FROM session_message sm,
               json_each(sm.data, '\$.content') as j
          WHERE sm.session_id = (
            SELECT id FROM session_v2
            WHERE project_id = '${PROJECT_ID}'
              AND time_archived IS NULL AND parent_id IS NULL
            ORDER BY time_updated DESC LIMIT 1
          )
            AND sm.type = 'assistant'
            AND sm.seq = (
              SELECT MAX(seq) FROM session_message
              WHERE session_id = (
                SELECT id FROM session_v2
                WHERE project_id = '${PROJECT_ID}'
                  AND time_archived IS NULL AND parent_id IS NULL
                ORDER BY time_updated DESC LIMIT 1
              ) AND type = 'assistant'
            )
            AND json_extract(j.value, '\$.type') = 'tool'
            AND json_extract(j.value, '\$.name') IN ('question', 'plan_exit')
            AND json_extract(j.value, '\$.state.status') = 'running'
        )
    ) > 0 THEN 'needs-input'

    WHEN (
        SELECT COUNT(*) FROM (
          SELECT json_extract(j.value, '\$.type') as ctype,
                 json_extract(j.value, '\$.state.status') as cstatus
          FROM session_message sm,
               json_each(sm.data, '\$.content') as j
          WHERE sm.session_id = (
            SELECT id FROM session_v2
            WHERE project_id = '${PROJECT_ID}'
              AND time_archived IS NULL AND parent_id IS NULL
            ORDER BY time_updated DESC LIMIT 1
          )
            AND sm.type = 'assistant'
            AND sm.seq = (
              SELECT MAX(seq) FROM session_message
              WHERE session_id = (
                SELECT id FROM session_v2
                WHERE project_id = '${PROJECT_ID}'
                  AND time_archived IS NULL AND parent_id IS NULL
                ORDER BY time_updated DESC LIMIT 1
              ) AND type = 'assistant'
            )
            AND json_extract(j.value, '\$.type') = 'tool'
            AND json_extract(j.value, '\$.state.status') = 'error'
        )
    ) > 0 THEN 'error'

    WHEN (
        SELECT sm.type FROM session_message sm
        WHERE sm.session_id = (
          SELECT id FROM session_v2
          WHERE project_id = '${PROJECT_ID}'
            AND time_archived IS NULL AND parent_id IS NULL
          ORDER BY time_updated DESC LIMIT 1
        )
          AND sm.seq = (
            SELECT MAX(seq) FROM session_message
            WHERE session_id = (
              SELECT id FROM session_v2
              WHERE project_id = '${PROJECT_ID}'
                AND time_archived IS NULL AND parent_id IS NULL
              ORDER BY time_updated DESC LIMIT 1
            )
          )
        LIMIT 1
    ) = 'assistant' AND (
        SELECT json_extract(sm.data, '\$.time.completed')
        FROM session_message sm
        WHERE sm.session_id = (
          SELECT id FROM session_v2
          WHERE project_id = '${PROJECT_ID}'
            AND time_archived IS NULL AND parent_id IS NULL
          ORDER BY time_updated DESC LIMIT 1
        )
          AND sm.seq = (
            SELECT MAX(seq) FROM session_message
            WHERE session_id = (
              SELECT id FROM session_v2
              WHERE project_id = '${PROJECT_ID}'
                AND time_archived IS NULL AND parent_id IS NULL
              ORDER BY time_updated DESC LIMIT 1
            )
          )
        LIMIT 1
    ) IS NULL THEN 'working'

    WHEN (
        SELECT sm.type FROM session_message sm
        WHERE sm.session_id = (
          SELECT id FROM session_v2
          WHERE project_id = '${PROJECT_ID}'
            AND time_archived IS NULL AND parent_id IS NULL
          ORDER BY time_updated DESC LIMIT 1
        )
          AND sm.seq = (
            SELECT MAX(seq) FROM session_message
            WHERE session_id = (
              SELECT id FROM session_v2
              WHERE project_id = '${PROJECT_ID}'
                AND time_archived IS NULL AND parent_id IS NULL
              ORDER BY time_updated DESC LIMIT 1
            )
          )
        LIMIT 1
    ) = 'user' THEN 'working'

    ELSE 'idle'
END as status;
")

# Status icon
case "$STATUS" in
needs-input) STATUS_ICON="${YELLOW}🟡${RESET} ${YELLOW}needs-input${RESET}" ;;
error)       STATUS_ICON="${RED}🔴${RESET} ${RED}error${RESET}" ;;
working)     STATUS_ICON="${GREEN}🟢${RESET} ${GREEN}working${RESET}" ;;
idle)        STATUS_ICON="${DIM}⚪${RESET} ${DIM}idle${RESET}" ;;
*)           STATUS_ICON="${DIM}⚪${RESET} ${DIM}unknown${RESET}" ;;
esac

# Latest model
MODEL=$(sqlite3 "$DB_PATH" "
    SELECT json_extract(s.model, '\$.id')
    FROM session_v2 s
    WHERE s.project_id = '${PROJECT_ID}'
      AND s.time_archived IS NULL AND s.parent_id IS NULL
      AND json_extract(s.model, '\$.id') IS NOT NULL
    ORDER BY s.time_updated DESC LIMIT 1;
" 2>/dev/null) || true

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

# Recent sessions for this project
RECENT_SESSIONS=$(sqlite3 -separator '|' "$DB_PATH" "
    SELECT s.id, s.title, s.time_updated,
           json_extract(s.model, '\$.id') as model
    FROM session_v2 s
    WHERE s.project_id = '${PROJECT_ID}'
      AND s.time_archived IS NULL AND s.parent_id IS NULL
    ORDER BY s.time_updated DESC
    LIMIT 8;
" 2>/dev/null) || true

# ─── Output ───────────────────────────────────────────────────────────────────

echo -e "${BOLD}${WHITE}Project:${RESET} ${name:-$(basename "$worktree")}"
echo -e "${WHITE}ID:${RESET}       ${DIM}${id}${RESET}"
echo -e "${WHITE}Status:${RESET}   ${STATUS_ICON}"
echo -e "${WHITE}Model:${RESET}    ${MODEL}"
echo -e "${WHITE}Worktree:${RESET} ${DIM}${worktree}${RESET}"
[[ -n "$vcs" ]] && echo -e "${WHITE}VCS:${RESET}      ${vcs}"
echo -e "${WHITE}Sessions:${RESET} ${SESSION_COUNT}"
echo -e "${WHITE}Updated:${RESET}  ${TIME_AGO}"
echo ""

# Recent sessions
if [[ -n "$RECENT_SESSIONS" ]]; then
	echo -e "${BOLD}${WHITE}Recent Sessions:${RESET}"
	echo "$RECENT_SESSIONS" | while IFS='|' read -r sid stitle stime smodel; do
		# Relative time for this session
		sdiff=$((now - stime / 1000))
		if ((sdiff < 60)); then
			stime_ago="${sdiff}s ago"
		elif ((sdiff < 3600)); then
			stime_ago="$((sdiff / 60))m ago"
		elif ((sdiff < 86400)); then
			stime_ago="$((sdiff / 3600))h ago"
		elif ((sdiff < 604800)); then
			stime_ago="$((sdiff / 86400))d ago"
		else
			stime_ago=$(date -d "@$((stime / 1000))" '+%Y-%m-%d' 2>/dev/null || echo "$stime")
		fi

		local_title="${stitle:0:50}"
		[[ ${#stitle} -gt 50 ]] && local_title="${local_title}…"

		# Shorten model
		if [[ -n "$smodel" ]]; then
			[[ "$smodel" == *"/"* ]] && smodel="${smodel##*/}"
			smodel="${smodel#claude-}"
			smodel="${smodel#antigravity-}"
			smodel="${smodel//codex-/}"
			smodel="${smodel%-preview}"
		fi

		if [[ -n "$smodel" ]]; then
			echo -e "  ${MAGENTA}${local_title}${RESET} ${DIM}${stime_ago}${RESET} ${DIM}[${smodel}]${RESET}"
		else
			echo -e "  ${MAGENTA}${local_title}${RESET} ${DIM}${stime_ago}${RESET}"
		fi
	done
else
	echo -e "${BOLD}${WHITE}Recent Sessions:${RESET} ${DIM}(none)${RESET}"
fi
echo ""
