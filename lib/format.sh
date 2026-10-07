#!/usr/bin/env bash
# Formatting and sorting functions for opencode-sessions
# All per-line transformations use awk — zero subshell forks

# Build formatted session list from raw query results
# Output: session_id\tstatus\ttime_ago\trepo\ttitle\tmodel\tdirectory\tchild_count\ttime_updated
build_session_data() {
	local query_func="$1"
	local filter_status="$2"
	shift 2

	local now
	now=$(date +%s)

	"$query_func" "$@" | awk -F'|' -v OFS='\t' -v now="$now" -v filter="$filter_status" '
		function compute_status(has_rq, has_cq, has_err, role, completed) {
			if (has_rq + 0 > 0 || has_cq + 0 > 0) return "needs-input"
			if (has_err + 0 > 0) return "error"
			if (role == "assistant" && completed == "null") return "working"
			if (role == "user") return "working"
			return "idle"
		}
		function derive_repo_name(dir) {
			if (index(dir, "/.worktrees/") > 0)
				sub("/.worktrees/.*", "", dir)
			n = split(dir, parts, "/")
			return parts[n]
		}
		function relative_time(ts,    diff) {
			ts = int(ts / 1000)
			diff = now - ts
			if (diff < 60) return diff "s ago"
			if (diff < 3600) return int(diff / 60) "m ago"
			if (diff < 86400) return int(diff / 3600) "h ago"
			if (diff < 604800) return int(diff / 86400) "d ago"
			return strftime("%Y-%m-%d", ts)
		}
		function shorten_model(m) {
			if (m == "") return ""
			sub(".*/", "", m)
			sub(/^claude-/, "", m)
			sub(/^antigravity-/, "", m)
			gsub(/codex-/, "", m)
			sub(/-preview$/, "", m)
			return m
		}
		function truncate(s, maxlen) {
			if (length(s) > maxlen)
				return substr(s, 1, maxlen) "…"
			return s
		}
		NF == 0 { next }
		{
			status = compute_status($10, $11, $12, $8, $9)
			if (filter != "" && status != filter) next
			repo = derive_repo_name($6)
			time_ago = relative_time($4)
			short_model = shorten_model($14)
			display_title = truncate($2, 60)
			print $1, status, time_ago, repo, display_title, short_model, $3, $13, $4
		}
	'
}

# Build formatted project list from raw query results
# Output: project_id\tstatus\ttime_ago\tname\tsession_count\tmodel\tworktree\tlatest_time
build_project_data() {
	local query_func="$1"
	local filter_status="$2"
	shift 2

	local now
	now=$(date +%s)

	"$query_func" "$@" | awk -F'|' -v OFS='\t' -v now="$now" -v filter="$filter_status" '
		function compute_status(role, completed) {
			if (role == "assistant" && completed == "null") return "working"
			if (role == "user") return "working"
			return "idle"
		}
		function derive_repo_name(dir) {
			if (index(dir, "/.worktrees/") > 0)
				sub("/.worktrees/.*", "", dir)
			n = split(dir, parts, "/")
			return parts[n]
			return parts[n]
		}
		function relative_time(ts,    diff) {
			ts = int(ts / 1000)
			diff = now - ts
			if (diff < 60) return diff "s ago"
			if (diff < 3600) return int(diff / 60) "m ago"
			if (diff < 86400) return int(diff / 3600) "h ago"
			if (diff < 604800) return int(diff / 86400) "d ago"
			return strftime("%Y-%m-%d", ts)
		}
		function shorten_model(m) {
			if (m == "") return ""
			sub(".*/", "", m)
			sub(/^claude-/, "", m)
			sub(/^antigravity-/, "", m)
			gsub(/codex-/, "", m)
			sub(/-preview$/, "", m)
			return m
		}
		function truncate(s, maxlen) {
			if (length(s) > maxlen)
				return substr(s, 1, maxlen) "…"
			return s
		}
		NF == 0 { next }
		{
			status = compute_status($6, $7)
			if (filter != "" && status != filter) next
			repo = derive_repo_name($3)
			time_ago = relative_time($5)
			short_model = shorten_model($8)
			display_name = ($2 != "") ? $2 : repo
			display_name = truncate(display_name, 40)
			print $1, status, time_ago, display_name, $4, short_model, $3, $5
		}
	'
}

# Build directory data for directory view
# Output: directory\tstatus\ttime_ago\trepo\t(count sessions)\ttime_updated
build_directory_data() {
	local query_func="$1"
	shift

	local now
	now=$(date +%s)

	"$query_func" "$@" | awk -F'|' -v OFS='\t' -v now="$now" '
		function compute_status(role, completed) {
			if (role == "assistant" && completed == "null") return "working"
			if (role == "user") return "working"
			return "idle"
		}
		function derive_repo_name(dir) {
			if (index(dir, "/.worktrees/") > 0)
				sub("/.worktrees/.*", "", dir)
			n = split(dir, parts, "/")
			return parts[n]
		}
		function relative_time(ts,    diff) {
			ts = int(ts / 1000)
			diff = now - ts
			if (diff < 60) return diff "s ago"
			if (diff < 3600) return int(diff / 60) "m ago"
			if (diff < 86400) return int(diff / 3600) "h ago"
			if (diff < 604800) return int(diff / 86400) "d ago"
			return strftime("%Y-%m-%d", ts)
		}
		NF == 0 { next }
		{
			status = compute_status($4, $5)
			time_ago = relative_time($3)
			repo = derive_repo_name($1)
			print $1, status, time_ago, repo, "(" $2 " sessions)", $3
		}
	'
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
# Input: tab-delimited session data (9 fields)
# Output: id\tdisplay_line\ttime_updated\trepo
# Trailing sort keys allow ctrl-s to sort the file without reformatting
format_for_display() {
	awk -F'\t' -v OFS='\t' -v use_ansi="${USE_ANSI:-false}" '
		function status_icon(status) {
			if (use_ansi == "true") {
				if (status == "needs-input") return "\033[0;33m🟡\033[0m"
				else if (status == "error") return "\033[0;31m🔴\033[0m"
				else if (status == "working") return "\033[0;32m🟢\033[0m"
				else return "\033[2m⚪\033[0m"
			} else {
				if (status == "needs-input") return "?"
				else if (status == "error") return "!"
				else if (status == "working") return "*"
				else return "."
			}
		}
		NF == 0 { next }
		{
			icon = status_icon($2)
			if ($6 != "")
				printf "%s\t%-8s %-10s %-20s %s [%s]\t%s\t%s\n", $1, icon, $3, $4, $5, $6, $9, $4
			else
				printf "%s\t%-8s %-10s %-20s %s\t%s\t%s\n", $1, icon, $3, $4, $5, $9, $4
		}
	'
}

# Format for list mode (no leading id tab, no trailing sort keys)
format_for_list() {
	awk -F'\t' -v use_ansi="${USE_ANSI:-false}" '
		function status_icon(status) {
			if (use_ansi == "true") {
				if (status == "needs-input") return "\033[0;33m🟡\033[0m"
				else if (status == "error") return "\033[0;31m🔴\033[0m"
				else if (status == "working") return "\033[0;32m🟢\033[0m"
				else return "\033[2m⚪\033[0m"
			} else {
				if (status == "needs-input") return "?"
				else if (status == "error") return "!"
				else if (status == "working") return "*"
				else return "."
			}
		}
		NF == 0 { next }
		{
			icon = status_icon($2)
			if ($6 != "")
				printf "%-8s %-10s %-20s %s [%s]\n", icon, $3, $4, $5, $6
			else
				printf "%-8s %-10s %-20s %s\n", icon, $3, $4, $5
		}
	'
}

# Format project data for display in fzf
# Input: tab-delimited project data (8 fields)
# Output: id\tformatted_line
format_projects_for_display() {
	awk -F'\t' -v use_ansi="${USE_ANSI:-false}" '
		function status_icon(status) {
			if (use_ansi == "true") {
				if (status == "needs-input") return "\033[0;33m🟡\033[0m"
				else if (status == "error") return "\033[0;31m🔴\033[0m"
				else if (status == "working") return "\033[0;32m🟢\033[0m"
				else return "\033[2m⚪\033[0m"
			} else {
				if (status == "needs-input") return "?"
				else if (status == "error") return "!"
				else if (status == "working") return "*"
				else return "."
			}
		}
		NF == 0 { next }
		{
			icon = status_icon($2)
			if ($6 != "")
				printf "%s\t%-8s %-10s %-20s (%s sessions) [%s]\n", $1, icon, $3, $4, $5, $6
			else
				printf "%s\t%-8s %-10s %-20s (%s sessions)\n", $1, icon, $3, $4, $5
		}
	'
}

# Format projects for list mode (no leading id tab)
format_projects_for_list() {
	awk -F'\t' -v use_ansi="${USE_ANSI:-false}" '
		function status_icon(status) {
			if (use_ansi == "true") {
				if (status == "needs-input") return "\033[0;33m🟡\033[0m"
				else if (status == "error") return "\033[0;31m🔴\033[0m"
				else if (status == "working") return "\033[0;32m🟢\033[0m"
				else return "\033[2m⚪\033[0m"
			} else {
				if (status == "needs-input") return "?"
				else if (status == "error") return "!"
				else if (status == "working") return "*"
				else return "."
			}
		}
		NF == 0 { next }
		{
			icon = status_icon($2)
			if ($6 != "")
				printf "%-8s %-10s %-20s (%s sessions) [%s]\n", icon, $3, $4, $5, $6
			else
				printf "%-8s %-10s %-20s (%s sessions)\n", icon, $3, $4, $5
		}
	'
}
