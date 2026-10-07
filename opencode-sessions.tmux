#!/usr/bin/env bash
# TPM main file for opencode-sessions plugin
#
# This plugin displays opencode sessions in a tmux popup window
# and creates/switches to tmux sessions when resuming sessions.

# Get plugin directory dynamically
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source tmux helper functions
source "${CURRENT_DIR}/lib/tmux_helpers.sh"

# ─── Set defaults (only if user hasn't already configured them) ───────────────
set_tmux_default @opencode-sessions-days "30"
set_tmux_default @opencode-sessions-sort "time"
set_tmux_default @opencode-sessions-prefix "false"
set_tmux_default @opencode-sessions-popup-height "80%"
set_tmux_default @opencode-sessions-popup-width "80%"
set_tmux_default @opencode-sessions-key "o"
set_tmux_default @opencode-sessions-projects-key "O"
set_tmux_default @opencode-sessions-popup-border "false"
set_tmux_default @opencode-sessions-fzf-opts "--height 80% --layout=reverse"
set_tmux_default @opencode-sessions-ansi "true"

# ─── Key bindings ─────────────────────────────────────────────────────────────
# Uses tmux display-popup for the outer popup. The script runs inside the
# popup, so chained fzf calls (project → session drill-down) stay within the
# same popup without flicker. All options are resolved at load time.

sessions_key=$(get_tmux_option @opencode-sessions-key "o")
projects_key=$(get_tmux_option @opencode-sessions-projects-key "O")

bind_popup_key "$sessions_key"
bind_popup_key "$projects_key" "--projects"
