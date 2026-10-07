#!/usr/bin/env bash
# Helper functions for opencode-sessions

# Get total session count
get_total_count() {
	local db_path="${1:-${HOME}/.local/share/opencode/opencode.db}"
	sqlite3 "$db_path" "SELECT COUNT(*) FROM session_v2 WHERE time_archived IS NULL AND parent_id IS NULL;"
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
