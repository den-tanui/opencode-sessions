#!/usr/bin/env bash
# TPM main file for opencode-sessions plugin
#
# This plugin displays opencode sessions in a tmux popup window
# and creates/switches to tmux sessions when resuming sessions.

# Get plugin directory dynamically
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source tmux helper functions
source "${CURRENT_DIR}/lib/tmux_helpers.sh"

# ─── Key bindings ─────────────────────────────────────────────────────────────
# Uses tmux display-popup for the outer popup. The script runs inside the
# popup, so chained fzf calls (project → session drill-down) stay within the
# same popup without flicker. All options are resolved at load time via
# get_tmux_option with built-in fallbacks (no set_tmux_default needed).

sessions_key=$(get_tmux_option @opencode-sessions-key "o")
projects_key=$(get_tmux_option @opencode-sessions-projects-key "O")

bind_popup_key "$sessions_key"
bind_popup_key "$projects_key" "--projects"
