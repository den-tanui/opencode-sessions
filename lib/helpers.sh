#!/usr/bin/env bash
# Helper functions for opencode-sessions

# Get total session count
get_total_count() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	sqlite3 "$db_path" "SELECT COUNT(*) FROM session_v2 WHERE time_archived IS NULL AND parent_id IS NULL;"
}

# Run a scalar SQL query safely with error handling
# Args: db_path sql
# Escapes single quotes in the SQL string before execution
db_scalar() {
	local db_path="$1"
	local sql="$2"
	# Escape single quotes
	sql="${sql//\'/\'\'}"
	local result
	result=$(sqlite3 "$db_path" "$sql" 2>&1) || {
		echo -e "${RED:-}DB error: ${result}${RESET:-}" >&2
		return 1
	}
	echo "$result"
}

# Derive repo name from directory
derive_repo_name() {
	local dir="$1"
	if [[ "$dir" == *"/.worktrees/"* ]]; then
		basename "${dir%%/.worktrees/*}"
	else
		basename "$dir"
	fi
}
