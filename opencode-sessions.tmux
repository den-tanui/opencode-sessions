#!/usr/bin/env bash
# TPM main file for opencode-sessions plugin
#
# This plugin displays opencode sessions in a tmux popup window
# and creates/switches to tmux sessions when resuming sessions.

# Get plugin directory dynamically
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set default options
set -g @opencode-sessions-days "30"
set -g @opencode-sessions-sort "time"
set -g @opencode-sessions-prefix "false"
set -g @opencode-sessions-popup-height "80%"
set -g @opencode-sessions-popup-width "80%"
set -g @opencode-sessions-key "o"
set -g @opencode-sessions-projects-key "O"
set -g @opencode-sessions-popup-border "false"

# FZF options - passed as single string
set -g @opencode-sessions-fzf-opts "--height 80% --layout=reverse"

# Enable ANSI colored output (true/false)
set -g @opencode-sessions-ansi "true"

# Key binding - uses tmux display-popup for the outer popup.
# The script runs inside the popup, so chained fzf calls (project →
# session drill-down) stay within the same popup without flicker.
# Tmux options are passed as CLI args to the script.
bind-key -n "#{@opencode-sessions-key}" run-shell -b "tmux display-popup #{?@opencode-sessions-popup-border,-B,} -w '#{@opencode-sessions-popup-width}' -h '#{@opencode-sessions-popup-height}' -xC -yC -E \"${CURRENT_DIR}/bin/opencode_sessions.sh --days #{@opencode-sessions-days} --sort #{@opencode-sessions-sort} --fzf-opts '#{@opencode-sessions-fzf-opts}' #{?#{@opencode-sessions-ansi},--ansi,} #{?#{@opencode-sessions-prefix},--prefix '#{@opencode-sessions-prefix}',}\""

# Projects key binding - same popup, but launches in projects mode.
bind-key -n "#{@opencode-sessions-projects-key}" run-shell -b "tmux display-popup #{?@opencode-sessions-popup-border,-B,} -w '#{@opencode-sessions-popup-width}' -h '#{@opencode-sessions-popup-height}' -xC -yC -E \"${CURRENT_DIR}/bin/opencode_sessions.sh --projects --days #{@opencode-sessions-days} --sort #{@opencode-sessions-sort} --fzf-opts '#{@opencode-sessions-fzf-opts}' #{?#{@opencode-sessions-ansi},--ansi,} #{?#{@opencode-sessions-prefix},--prefix '#{@opencode-sessions-prefix}',}\""
