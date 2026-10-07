#!/usr/bin/env bash
# Formatting and sorting functions for opencode-sessions

# Build formatted session list from raw query results
# Output: session_id\tstatus\ttime_ago\trepo\ttitle\tmodel\tdirectory\tchild_count\ttime_updated
build_session_data() {
	local query_func="$1"
	local filter_status="$2"
	shift 2

	# Call the query function passed as argument, forwarding remaining args
	"$query_func" "$@" | while IFS='|' read -r id title directory time_updated time_created worktree project_name last_role last_completed has_rq has_cq has_err child_count model; do
		[[ -z "$id" ]] && continue

		local status
		status=$(compute_status "$has_rq" "$has_cq" "$has_err" "$last_role" "$last_completed")

		# Apply filter
		if [[ -n "$filter_status" && "$status" != "$filter_status" ]]; then
			continue
		fi

		local repo
		repo=$(derive_repo_name "$worktree")

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

# Build formatted project list from raw query results
# Output: project_id\tstatus\ttime_ago\tname\tsession_count\tmodel\tworktree\tlatest_time
build_project_data() {
	local query_func="$1"
	local filter_status="$2"
	shift 2

	"$query_func" "$@" | while IFS='|' read -r id name worktree session_count latest_time latest_role latest_completed model; do
		[[ -z "$id" ]] && continue

		local status
		status=$(compute_status 0 0 0 "$latest_role" "$latest_completed")

		# Apply filter
		if [[ -n "$filter_status" && "$status" != "$filter_status" ]]; then
			continue
		fi

		local repo
		repo=$(derive_repo_name "$worktree")

		local time_ago
		time_ago=$(relative_time "$latest_time")

		local short_model
		short_model=$(shorten_model "$model")

		local display_name="${name:-$repo}"
		local full_name="${name:-$repo}"
		display_name="${display_name:0:40}"
		[[ ${#full_name} -gt 40 ]] && display_name="${display_name}…"

		printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
			"$id" "$status" "$time_ago" "$display_name" "$session_count" "$short_model" "$worktree" "$latest_time"
	done
}

# Format project data for display in fzf
# Input: tab-delimited project data
# Output: id\tformatted_line
format_projects_for_display() {
	while IFS=$'\t' read -r id status time_ago name session_count model worktree latest_time; do
		local icon
		icon=$(status_icon "$status")
		if [[ -n "$model" ]]; then
			printf '%s\t%-8s %-10s %-20s (%s sessions) [%s]\n' "$id" "$icon" "$time_ago" "$name" "$session_count" "$model"
		else
			printf '%s\t%-8s %-10s %-20s (%s sessions)\n' "$id" "$icon" "$time_ago" "$name" "$session_count"
		fi
	done
}

# Format projects for list mode (no leading id tab)
format_projects_for_list() {
	while IFS=$'\t' read -r id status time_ago name session_count model worktree latest_time; do
		local icon
		icon=$(status_icon "$status")
		if [[ -n "$model" ]]; then
			printf '%-8s %-10s %-20s (%s sessions) [%s]\n' "$icon" "$time_ago" "$name" "$session_count" "$model"
		else
			printf '%-8s %-10s %-20s (%s sessions)\n' "$icon" "$time_ago" "$name" "$session_count"
		fi
	done
}

# Build directory data for directory view
# Output: directory\tstatus\ttime_ago\trepo\t(count sessions)\ttime_updated
build_directory_data() {
	local query_func="$1"

	"$query_func" | while IFS='|' read -r directory count time_updated role completed; do
		[[ -z "$directory" ]] && continue

		local status
		status=$(compute_status 0 0 0 "$role" "$completed")

		local time_ago
		time_ago=$(relative_time "$time_updated")

		local repo
		repo=$(derive_repo_name "$worktree")

		printf '%s\t%s\t%s\t%s\t(%d sessions)\t%s\n' \
			"$directory" "$status" "$time_ago" "$repo" "$count" "$time_updated"
	done
}

# Sort by time_updated descending (newest first)
sort_by_time() {
	sort -t$'\t' -k9,9rn
}

# Sort by project (repo) grouped by most recent activity, then by time descending within each
sort_by_directory() {
	awk -F'\t' '
		{ if ($9 > max[$4]) max[$4] = $9; lines[NR] = $0; repos[NR] = $4 }
		END { for (i = 1; i <= NR; i++) print max[repos[i]] "\t" lines[i] }
	' | sort -t$'\t' -k1,1rn -k10,10rn | cut -f2-
}

# Main sort dispatcher
sort_data() {
	case "$1" in
	time) sort_by_time ;;
	directory) sort_by_directory ;;
	*) sort_by_time ;;
	esac
}

# Format session data for display in fzf
# Input: tab-delimited session data
# Output: id\tformatted_line
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

# Format for list mode (no leading id tab)
format_for_list() {
	while IFS=$'\t' read -r id status time_ago repo title model directory child_count time_updated; do
		local icon
		icon=$(status_icon "$status")
		if [[ -n "$model" ]]; then
			printf '%-8s %-10s %-20s %s [%s]\n' "$icon" "$time_ago" "$repo" "$title" "$model"
		else
			printf '%-8s %-10s %-20s %s\n' "$icon" "$time_ago" "$repo" "$title"
		fi
	done
}
