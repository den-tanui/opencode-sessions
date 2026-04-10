#!/usr/bin/env bash
# TPM main file for opencode-sessions plugin
#
# This plugin displays opencode sessions in a tmux popup window
# and creates/switches to tmux sessions when resuming sessions.

# Get plugin directory dynamically
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set default options
set -g @opencode-sessions-days "7"
set -g @opencode-sessions-sort "time"
set -g @opencode-sessions-prefix "false"
set -g @opencode-sessions-popup-height "80%"
set -g @opencode-sessions-popup-width "80%"
set -g @opencode-sessions-key "o"

# Key binding - reads key and popup options from tmux options at runtime
# Uses -n for no-prefix binding
bind-key -n "#{@opencode-sessions-key}" run-shell -b "tmux display-popup -w '#{@opencode-sessions-popup-width}' -h '#{@opencode-sessions-popup-height}' -xC -yC -E 'bash -c ${CURRENT_DIR}/bin/opencode_sessions.sh'"