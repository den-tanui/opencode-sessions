#!/usr/bin/env bash
# Formatting and sorting functions for opencode-sessions

# Build formatted session list from raw query results
# Output: session_id\tstatus\ttime_ago\trepo\ttitle\tmodel\tdirectory\tchild_count\ttime_updated
build_session_data() {
	local query_func="$1"
	local filter_status="$2"

	# Call the query function passed as argument
	"$query_func" | while IFS='|' read -r id title directory time_updated time_created worktree project_name last_role last_completed has_rq has_cq has_err child_count model; do
		[[ -z "$id" ]] && continue

		local status
		status=$(compute_status "$has_rq" "$has_cq" "$has_err" "$last_role" "$last_completed")

		# Apply filter
		if [[ -n "$filter_status" && "$status" != "$filter_status" ]]; then
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
		repo=$(derive_repo_name "$directory")

		printf '%s\t%s\t%s\t%s\t(%d sessions)\t%s\n' \
			"$directory" "$status" "$time_ago" "$repo" "$count" "$time_updated"
	done
}

# Sort by time_updated descending (newest first)
sort_by_time() {
	sort -t$'\t' -k9,9rn
}

# Sort by directory, then by time descending
sort_by_directory() {
	sort -t$'\t' -k4,4 -k9,9rn
}

# Sort by status priority, then by time descending
sort_by_status() {
	while IFS=$'\t' read -r id status time_ago repo title model directory child_count time_updated; do
		local prio
		case "$status" in
		working) prio=0 ;;
		idle) prio=1 ;;
		*) prio=2 ;;
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

# Main sort dispatcher
sort_data() {
	case "$1" in
	time) sort_by_time ;;
	directory) sort_by_directory ;;
	status) sort_by_status ;;
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
