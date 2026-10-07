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

	if [[ -n "$extra" ]]; then
		args+=" $extra"
	fi

	echo "$args"
}

# Build the tmux display-popup command for the session picker.
# Args: extra_args (optional, e.g. "--projects")
# Echoes the full tmux command string (bind-key ... run-shell ...)
build_popup_binding() {
	local extra="${1:-}"
	local script="$CURRENT_DIR/bin/opencode_sessions.sh"
	local border_opt="#{?@opencode-sessions-popup-border,-B,}"
	local width="#{@opencode-sessions-popup-width}"
	local height="#{@opencode-sessions-popup-height}"
	local args

	args=$(build_session_args "$extra")

	echo "run-shell -b \"tmux display-popup ${border_opt} -w '${width}' -h '${height}' -xC -yC -E \\\"${script}${args}\\\"\""
}
