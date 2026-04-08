#!/usr/bin/env bash
# opencode-sessions-fzf.sh - Browse, filter, sort, and resume opencode sessions via fzf
#
# Usage:
#   ./opencode-sessions-fzf.sh              # Interactive mode with fzf
#   ./opencode-sessions-fzf.sh --list       # List sessions without fzf
#   ./opencode-sessions-fzf.sh --copy       # Copy selected session ID to clipboard
#   ./opencode-sessions-fzf.sh --multi      # Multi-select mode
#   ./opencode-sessions-fzf.sh --filter working  # Only show working sessions
#   ./opencode-sessions-fzf.sh --sort status     # Start sorted by status
#
# Dependencies: sqlite3, fzf, opencode

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DB_PATH="${HOME}/.local/share/opencode/opencode.db"
PREVIEW_SCRIPT="${SCRIPT_DIR}/preview.sh"

# ─── Color codes ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
RESET='\033[0m'

# ─── Argument parsing ─────────────────────────────────────────────────────────
MODE="interactive"
FILTER_STATUS=""
SORT_BY="time"
DAYS_FILTER=14
SHOW_ALL=false
DIR_FILTER=""

while [[ $# -gt 0 ]]; do
	case "$1" in
	--list)
		MODE="list"
		shift
		;;
	--copy)
		MODE="copy"
		shift
		;;
	--multi)
		MODE="multi"
		shift
		;;
	--filter)
		FILTER_STATUS="$2"
		shift 2
		;;
	--sort)
		SORT_BY="$2"
		shift 2
		;;
	--days)
		DAYS_FILTER="$2"
		shift 2
		;;
	--all)
		SHOW_ALL=true
		shift
		;;
	--dir)
		DIR_FILTER="$2"
		shift 2
		;;
	-h | --help)
		echo "Usage: $0 [OPTIONS]"
		echo ""
		echo "Options:"
		echo "  --list          List sessions without fzf"
		echo "  --copy          Copy selected session ID to clipboard"
		echo "  --multi         Multi-select mode (TAB to mark)"
		echo "  --filter STATUS Filter by: working, needs-input, error, idle"
		echo " --sort FIELD Initial sort: time (default), directory, status"
		echo " --dir DIR    Filter by specific directory (exact match)"
		echo " --days N Show sessions from last N days (default: 14)"
		echo "  --all           Show all sessions regardless of age"
		echo "  -h, --help      Show this help"
		exit 0
		;;
	*)
		echo "Unknown option: $1" >&2
		exit 1
		;;
	esac
done

# ─── Validation ───────────────────────────────────────────────────────────────
if [[ ! -f "$DB_PATH" ]]; then
	echo -e "${RED}Error: opencode database not found at ${DB_PATH}${RESET}" >&2
	echo "Run opencode at least once to create the database." >&2
	exit 1
fi

if ! command -v sqlite3 &>/dev/null; then
	echo -e "${RED}Error: sqlite3 is required but not installed${RESET}" >&2
	exit 1
fi

if ! command -v fzf &>/dev/null; then
	echo -e "${RED}Error: fzf is required but not installed${RESET}" >&2
	exit 1
fi

if [[ ! -f "$PREVIEW_SCRIPT" ]]; then
	echo -e "${RED}Error: preview.sh not found at ${PREVIEW_SCRIPT}${RESET}" >&2
	exit 1
fi

# ─── Single combined CTE query ────────────────────────────────────────────────
# Computes all status flags in one database hit
# Optimized with JOIN to MAX subquery instead of window functions
query_all_sessions() {
	# Calculate time threshold (Unix milliseconds)
	local time_threshold
	if [[ "$SHOW_ALL" == "true" ]]; then
		time_threshold=0
	else
		time_threshold=$((($(date +%s) - DAYS_FILTER * 86400) * 1000))
	fi

	sqlite3 -separator '|' "$DB_PATH" "
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
$(if [[ -n "$DIR_FILTER" ]]; then echo "AND s.directory = '${DIR_FILTER}'"; fi);
"
}

# ─── Query for directory grouping ─────────────────────────────────────────────
query_directories() {
	local time_threshold
	if [[ "$SHOW_ALL" == "true" ]]; then
		time_threshold=0
	else
		time_threshold=$((($(date +%s) - DAYS_FILTER * 86400) * 1000))
	fi

	sqlite3 -separator '|' "$DB_PATH" "
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

# ─── Helper functions ─────────────────────────────────────────────────────────

# Get total session count (without time filter) for count display
get_total_count() {
	sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM session WHERE time_archived IS NULL AND parent_id IS NULL;"
}

get_sort_label() {
	case "$1" in
	time) echo "time" ;;
	directory) echo "directory" ;;
	status) echo "status (running, idle, dead)" ;;
	*) echo "time" ;;
	esac
}

derive_repo_name() {
	local dir="$1"
	if [[ "$dir" == *"/.worktrees/"* ]]; then
		basename "${dir%%/.worktrees/*}"
	else
		basename "$dir"
	fi
}

relative_time() {
	local ts="$1"
	local now
	now=$(date +%s)
	local diff=$((now - ts / 1000))
	if ((diff < 60)); then
		echo "${diff}s ago"
	elif ((diff < 3600)); then
		echo "$((diff / 60))m ago"
	elif ((diff < 86400)); then
		echo "$((diff / 3600))h ago"
	elif ((diff < 604800)); then
		echo "$((diff / 86400))d ago"
	else
		date -d "@$((ts / 1000))" '+%Y-%m-%d' 2>/dev/null || echo "$ts"
	fi
}

shorten_model() {
	local model="$1"
	[[ -z "$model" ]] && return
	[[ "$model" == *"/"* ]] && model="${model##*/}"
	model="${model#claude-}"
	model="${model#antigravity-}"
	model="${model//codex-/}"
	model="${model%-preview}"
	echo "$model"
}

compute_status() {
	local has_rq="$1" has_cq="$2" has_err="$3" role="$4" completed="$5"
	if ((has_rq > 0 || has_cq > 0)); then
		echo "needs-input"
	elif ((has_err > 0)); then
		echo "error"
	elif [[ "$role" == "assistant" && "$completed" == "null" ]]; then
		echo "working"
	elif [[ "$role" == "user" ]]; then
		echo "working"
	else
		echo "idle"
	fi
}

status_icon() {
	case "$1" in
	needs-input) echo -e "${YELLOW}🟡${RESET}" ;;
	error) echo -e "${RED}🔴${RESET}" ;;
	working) echo -e "${GREEN}🟢${RESET}" ;;
	idle) echo -e "${DIM}⚪${RESET}" ;;
	*) echo -e "${DIM}⚪${RESET}" ;;
	esac
}

status_priority() {
	case "$1" in
	working) echo 0 ;; # running
	idle) echo 1 ;;    # idle
	*) echo 2 ;;       # dead (error, needs-input, etc.)
	esac
}

# ─── Build formatted session list ─────────────────────────────────────────────
# Output: session_id\tstatus\ttime_ago\trepo\ttitle\tmodel\tdirectory\tchild_count\ttime_updated
build_session_data() {
	query_all_sessions | while IFS='|' read -r id title directory time_updated time_created worktree project_name last_role last_completed has_rq has_cq has_err child_count model; do
		[[ -z "$id" ]] && continue

		local status
		status=$(compute_status "$has_rq" "$has_cq" "$has_err" "$last_role" "$last_completed")

		# Apply filter
		if [[ -n "$FILTER_STATUS" && "$status" != "$FILTER_STATUS" ]]; then
			continue
		fi

		local repo
		repo=$(derive_repo_name "$directory")

		local time_ago
		time_ago=$(relative_time "$time_updated")

		local short_model
		short_model=$(shorten_model "$model")

		# Truncate title to 60 chars
		local display_title="${title:0:60}"
		[[ ${#title} -gt 60 ]] && display_title="${display_title}…"

		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$id" "$status" "$time_ago" "$repo" "$display_title" "$short_model" "$directory" "$child_count" "$time_updated"
	done
}

# ─── Build directory data for directory view ─────────────────────────────────
# Output: directory\tstatus\ttime_ago\trepo\t(count sessions)\ttime_updated
build_directory_data() {
	query_directories | while IFS='|' read -r directory count time_updated role completed; do
		[[ -z "$directory" ]] && continue

		local status
		status=$(compute_status 0 0 0 "$role" "$completed")

		local time_ago
		time_ago=$(relative_time "$time_updated")

		local repo
		repo=$(derive_repo_name "$directory")

		printf '%s\t%s\t%s\t%s\t(%d sessions)\t%s\n' \
			"$directory" "$status" "$time_ago" "$repo" "$count" "$time_updated"
	done
}

# ─── Sort functions ───────────────────────────────────────────────────────────

sort_by_time() {
	# Sort by time_updated (field 9) descending — newest first
	sort -t$'\t' -k9,9rn
}

sort_by_directory() {
	sort -t$'\t' -k4,4 -k9,9rn
}

sort_by_status() {
	while IFS=$'\t' read -r id status time_ago repo title model directory child_count time_updated; do
		local prio
		case "$status" in
		working) prio=0 ;; # running
		idle) prio=1 ;;    # idle
		*) prio=2 ;;       # dead (error, needs-input, etc.)
		esac
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$prio" "$time_ago" "$repo" "$title" "$model" "$directory" "$child_count" "$time_updated"
	done | sort -t$'\t' -k2,2n -k9,9rn | while IFS=$'\t' read -r id prio time_ago repo title model directory child_count time_updated; do
		local actual_status
		case "$prio" in
		0) actual_status="working" ;;
		1) actual_status="idle" ;;
		*) actual_status="dead" ;;
		esac
		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$actual_status" "$time_ago" "$repo" "$title" "$model" "$directory" "$child_count" "$time_updated"
	done
}

sort_data() {
	case "$1" in
	time) sort_by_time ;;
	directory) sort_by_directory ;;
	status) sort_by_status ;;
	*) sort_by_time ;;
	esac
}

# ─── List mode ────────────────────────────────────────────────────────────────

run_list() {
	# Get counts for display
	local filtered_count=0
	local total_count=0

	# Count filtered sessions
	filtered_count=$(build_session_data | wc -l)

	# Get total count if filtering
	if [[ "$SHOW_ALL" != "true" && "$DAYS_FILTER" -gt 0 ]]; then
		total_count=$(get_total_count)
		if [[ "$filtered_count" != "$total_count" ]]; then
			echo -e "${DIM}Showing ${filtered_count} of ${total_count} sessions (last ${DAYS_FILTER} days)${RESET}"
		fi
	fi

	echo -e "${WHITE}$(printf '%-8s' 'Status') $(printf '%-10s' 'Updated') $(printf '%-20s' 'Repo') Session Title [Model]${RESET}"
	echo -e "${DIM}$(printf '%.0s─' {1..100})${RESET}"

	build_session_data | sort_data "$SORT_BY" | while IFS=$'\t' read -r id status time_ago repo title model directory child_count; do
		local icon
		icon=$(status_icon "$status")
		if [[ -n "$model" ]]; then
			printf '%-8s %-10s %-20s %s [%s]\n' "$icon" "$time_ago" "$repo" "$title" "$model"
		else
			printf '%-8s %-10s %-20s %s\n' "$icon" "$time_ago" "$repo" "$title"
		fi
	done
}

# ─── Interactive fzf mode ─────────────────────────────────────────────────────

run_interactive() {
	echo -e "${CYAN}Loading sessions...${RESET}" >&2

	# Cache all session data
	local cache_file
	cache_file=$(mktemp)
	trap 'rm -f "$cache_file"' EXIT

	build_session_data >"$cache_file"

	if [[ ! -s "$cache_file" ]]; then
		echo -e "${YELLOW}No sessions found.${RESET}"
		exit 0
	fi

	# Get counts for display
	local filtered_count
	local total_count=0
	filtered_count=$(wc -l <"$cache_file")

	if [[ "$SHOW_ALL" != "true" && "$DAYS_FILTER" -gt 0 ]]; then
		total_count=$(get_total_count)
		if [[ "$filtered_count" != "$total_count" ]]; then
			echo -e "${DIM}Showing ${filtered_count} of ${total_count} sessions (last ${DAYS_FILTER} days)${RESET}" >&2
		fi
	fi

	# Format for display
	format_for_display() {
		while IFS=$'\t' read -r id status time_ago repo title model directory child_count time_updated; do
			local icon
			icon=$(status_icon "$status")
			if [[ -n "$model" ]]; then
				printf '%s\t%-8s %-10s %-20s %s [%s]\n' "$id" "$icon" "$time_ago" "$repo" "$title" "$model"
			else
				printf '%s\t%-8s %-10s %-20s %s\n' "$id" "$icon" "$time_ago" "$repo" "$title"
			fi
		done
	}

	# Sort the cached data (default: newest first)
	local sorted_file
	sorted_file=$(mktemp)
	trap 'rm -f "$cache_file" "$sorted_file"' EXIT
	sort_data "$SORT_BY" <"$cache_file" >"$sorted_file"

	local fzf_flags=()
	if [[ "$MODE" == "multi" ]]; then
		fzf_flags+=(--multi)
	fi

	# State file for sort cycling
	local sort_state_file
	sort_state_file=$(mktemp)
	# Map initial sort to index: time=0, directory=1, status=2
	case "$SORT_BY" in
	time) echo "0" >"$sort_state_file" ;;
	directory) echo "1" >"$sort_state_file" ;;
	status) echo "2" >"$sort_state_file" ;;
	*) echo "0" >"$sort_state_file" ;;
	esac

	# Cycle script: reads state, increments, sorts, outputs formatted data
	local cycle_script
	cycle_script=$(mktemp)
	trap 'rm -f "$cache_file" "$sorted_file" "$cycle_script" "$sort_state_file"' EXIT

	cat >"$cycle_script" <<CYCLE_EOF
#!/usr/bin/env bash
CACHE_FILE="$cache_file"
STATE_FILE="$sort_state_file"

sort_order=("time" "directory" "status")

idx=\$(cat "\$STATE_FILE")
idx=\$(( (idx + 1) % 3 ))
echo "\$idx" > "\$STATE_FILE"

sort_field="\${sort_order[\$idx]}"

format_for_display() {
    while IFS=\$'\\t' read -r id status time_ago repo title model directory child_count; do
        local icon
        case "\$status" in
            needs-input) icon=\$'\\033[0;33m🟡\\033[0m' ;;
            error)       icon=\$'\\033[0;31m🔴\\033[0m' ;;
            working)     icon=\$'\\033[0;32m🟢\\033[0m' ;;
            idle)        icon=\$'\\033[2m⚪\\033[0m' ;;
            *)           icon=\$'\\033[2m⚪\\033[0m' ;;
        esac
        if [[ -n "\$model" ]]; then
            printf '%s\\t%-8s %-10s %-20s %s [%s]\\n' "\$id" "\$icon" "\$time_ago" "\$repo" "\$title" "\$model"
        else
            printf '%s\\t%-8s %-10s %-20s %s\\n' "\$id" "\$icon" "\$time_ago" "\$repo" "\$title"
        fi
    done
}

sort_data() {
    case "\$1" in
        time) cat ;;
        directory) sort -t\$'\\t' -k4,4 -k3,3 ;;
        status)
            while IFS=\$'\\t' read -r id status time_ago repo title model directory child_count; do
                local prio
                case "\$status" in
                    working) prio=0 ;; # running
                    idle) prio=1 ;;    # idle
                    *) prio=2 ;;       # dead (error, needs-input, etc.)
                esac
                printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "\$id" "\$prio" "\$time_ago" "\$repo" "\$title" "\$model" "\$directory" "\$child_count"
            done | sort -t\$'\\t' -k2,2n -k3,3 | while IFS=\$'\\t' read -r id prio time_ago repo title model directory child_count; do
                local actual_status
                case "\$prio" in
                    0) actual_status="working" ;;
                    1) actual_status="idle" ;;
                    *) actual_status="dead" ;;
                esac
                printf '%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\t%s\\n' "\$id" "\$actual_status" "\$time_ago" "\$repo" "\$title" "\$model" "\$directory" "\$child_count"
            done
            ;;
    esac
}

sort_data "\$sort_field" < "\$CACHE_FILE" | format_for_display
CYCLE_EOF
	chmod +x "$cycle_script"

	# Run fzf with footer (not header) and alt-s sort cycling
	local selected
	selected=$(format_for_display <"$sorted_file" | fzf \
		--height 80% \
		--ansi \
		--layout=reverse \
		--border \
		--with-nth 2.. \
		--preview "bash '${PREVIEW_SCRIPT}' {}" \
		--preview-window "right:60%,border-left" \
		--delimiter '\t' \
		--prompt="Select session: " \
		--footer "Alt-S: cycle sort (→ $(get_sort_label "$SORT_BY")) | ↑/↓: navigate | Enter: resume | ?: toggle preview" \
		--bind "?:toggle-preview" \
		--bind "alt-s:reload(bash '${cycle_script}')" \
		"${fzf_flags[@]}" \
		2>/dev/null) || true

	if [[ -z "$selected" ]]; then
		echo -e "${DIM}No session selected.${RESET}"
		exit 0
	fi

	# Extract session ID(s)
	local session_ids=()
	while IFS= read -r line; do
		local sid
		sid=$(echo "$line" | cut -f1)
		session_ids+=("$sid")
	done <<<"$selected"

	if [[ "$MODE" == "copy" ]]; then
		local copy_text
		copy_text=$(printf '%s\n' "${session_ids[@]}")
		if command -v xclip &>/dev/null; then
			echo "$copy_text" | xclip -selection clipboard
		elif command -v pbcopy &>/dev/null; then
			echo "$copy_text" | pbcopy
		elif command -v wl-copy &>/dev/null; then
			echo "$copy_text" | wl-copy
		else
			echo -e "${YELLOW}Session IDs:${RESET}"
			echo "$copy_text"
			echo -e "${DIM}(No clipboard tool found, copy manually)${RESET}"
		fi
		echo -e "${GREEN}Copied ${#session_ids[@]} session ID(s) to clipboard${RESET}"
		exit 0
	fi

	# Resume the first selected session
	local session_id="${session_ids[0]}"
	local directory
	directory=$(sqlite3 "$DB_PATH" "SELECT directory FROM session WHERE id = '${session_id}';")

	if [[ -z "$directory" ]]; then
		echo -e "${RED}Error: Could not find directory for session ${session_id}${RESET}"
		exit 1
	fi

	if [[ ! -d "$directory" ]]; then
		echo -e "${RED}Error: Directory does not exist: ${directory}${RESET}"
		exit 1
	fi

	echo -e "${GREEN}Resuming session: ${session_id}${RESET}"
	echo -e "${DIM}Directory: ${directory}${RESET}"

	cd "$directory"
	exec opencode -s "$session_id"
}

# ─── Main entry point ─────────────────────────────────────────────────────────

case "$MODE" in
list)
	run_list
	;;
interactive | copy | multi)
	run_interactive
	;;
esac
