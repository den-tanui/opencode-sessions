#!/usr/bin/env bash
# Tmux helper functions for opencode-sessions plugin
# Provides option get/set-with-default helpers so user config is preserved.

# Get a tmux option value, falling back to a default if unset.
# Args: option_name default_value
get_tmux_option() {
	local option="$1"
	local default="$2"
	local value
	value=$(tmux show-option -gqv "$option" 2>/dev/null)
	if [[ -z "$value" ]]; then
		echo "$default"
	else
		echo "$value"
	fi
}

# Set a tmux option only if it is not already set by the user.
# Args: option_name default_value
set_tmux_default() {
	local option="$1"
	local default="$2"
	local current
	current=$(tmux show-option -gqv "$option" 2>/dev/null)
	if [[ -z "$current" ]]; then
		tmux set -g "$option" "$default"
	fi
}

# Build the CLI args string for opencode_sessions.sh from tmux options.
# Echoes the argument string (without the script path).
# Args: extra_args (optional, e.g. "--projects")
build_session_args() {
	local extra="${1:-}"
	local args=""

	args+=" --days $(get_tmux_option @opencode-sessions-days 30)"
	args+=" --sort $(get_tmux_option @opencode-sessions-sort time)"
	args+=" --fzf-opts '$(get_tmux_option @opencode-sessions-fzf-opts '--height 80% --layout=reverse')'"

	local prefix
	prefix=$(get_tmux_option @opencode-sessions-prefix false)
	if [[ "$prefix" != "false" && -n "$prefix" ]]; then
		args+=" --prefix '$prefix'"
	fi

	local ansi
	ansi=$(get_tmux_option @opencode-sessions-ansi true)
	if [[ "$ansi" == "true" ]]; then
		args+=" --ansi"
	fi

	local filter
	filter=$(get_tmux_option @opencode-sessions-filter "")
	if [[ -n "$filter" ]]; then
		args+=" --filter '$filter'"
	fi

	local show_all
	show_all=$(get_tmux_option @opencode-sessions-all false)
	if [[ "$show_all" == "true" ]]; then
		args+=" --all"
	fi

	local dir
	dir=$(get_tmux_option @opencode-sessions-dir "")
	if [[ -n "$dir" ]]; then
		args+=" --dir '$dir'"
	fi

	local new_window
	new_window=$(get_tmux_option @opencode-sessions-new-window false)
	if [[ "$new_window" == "true" ]]; then
		args+=" --new-window"
	fi

	if [[ -n "$extra" ]]; then
		args+=" $extra"
	fi

	echo "$args"
}

# Bind a tmux key to open the session picker popup.
# Resolves all options at load time (not via #{...} format strings)
# so values are concrete when the binding is registered.
# Args: key  extra_args (optional, e.g. "--projects")
bind_popup_key() {
	local key="$1"
	local extra="${2:-}"
	local script="$CURRENT_DIR/bin/opencode_sessions.sh"
	local args

	args=$(build_session_args "$extra")

	# Resolve popup dimensions and border at load time
	local width height border_flag
	width=$(get_tmux_option @opencode-sessions-popup-width "80%")
	height=$(get_tmux_option @opencode-sessions-popup-height "80%")
	border_flag=""
	if [[ "$(get_tmux_option @opencode-sessions-popup-border false)" == "true" ]]; then
		border_flag="-B"
	fi

	# Build the display-popup command that runs inside the popup
	local popup_cmd="${script}${args}"

	# Register the key binding via tmux bind-key
	tmux bind-key -n "$key" run-shell -b \
		"tmux display-popup ${border_flag} -w '${width}' -h '${height}' -xC -yC -E \"${popup_cmd}\""
}
