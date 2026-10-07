#!/usr/bin/env bash
# opencode_sessions.sh - TPM plugin entry point for browsing opencode sessions
#
# Usage:
#   ./bin/opencode_sessions.sh              # Interactive mode with fzf in tmux popup
#   ./bin/opencode_sessions.sh --list       # List sessions without fzf
#   ./bin/opencode_sessions.sh --copy       # Copy selected session ID to clipboard
#   ./bin/opencode_sessions.sh --multi      # Multi-select mode
#   ./bin/opencode_sessions.sh --filter working  # Only show working sessions
#   ./bin/opencode_sessions.sh --new-window    # Open in new window without switching
#
# Dependencies: sqlite3, fzf, opencode

set -euo pipefail

# ─── Script directory resolution ──────────────────────────────────────────────
# Handle both direct execution and TPM sourcing
if [[ -n "${TMUX_PLUGIN:-}" ]]; then
  # Running as TPM plugin - use plugin directory
  SCRIPT_DIR="${TMUX_PLUGIN}"
else
  # Running directly - resolve relative to script location
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
fi

# ─── Source library modules ───────────────────────────────────────────────────
# colors.sh is sourced after arg parsing, once USE_ANSI is finalized
source "${SCRIPT_DIR}/lib/helpers.sh"
source "${SCRIPT_DIR}/lib/db.sh"
source "${SCRIPT_DIR}/lib/format.sh"

# ─── Configuration ──────────────────────────────────────────────────────────────
DB_PATH="${HOME}/.local/share/opencode/opencode.db"
PREVIEW_SCRIPT="${SCRIPT_DIR}/scripts/preview.sh"

# Check if running inside tmux
is_in_tmux() {
  [[ -n "${TMUX:-}" ]]
}

# Get current tmux session name
get_current_tmux_session() {
  if is_in_tmux; then
    tmux display-message -p '#S' 2>/dev/null
  fi
}

DAYS_FILTER=7
SORT_BY="time"
FZF_OPTS="--height 100% --layout=reverse --border"

# ─── Argument parsing ─────────────────────────────────────────────────────────
MODE="interactive"
FILTER_STATUS=""
SHOW_ALL=false
DIR_FILTER=""
NEW_WINDOW_MODE=false
PROJECTS_MODE=false
PROJECT_FILTER=""
TMUX_POPUP=false
TMUX_OPTS_ARG=""
PREFIX=""
ANSI_FLAG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
  --list)
    MODE="list"
    shift
    ;;
  --copy)
    MODE="copy"
    shift
    ;;
  --multi)
    MODE="multi"
    shift
    ;;
  --filter)
    FILTER_STATUS="$2"
    shift 2
    ;;
  --sort)
    SORT_BY="$2"
    shift 2
    ;;
  --days)
    DAYS_FILTER="$2"
    shift 2
    ;;
  --all)
    SHOW_ALL=true
    shift
    ;;
  --dir)
    DIR_FILTER="$2"
    shift 2
    ;;
  --new-window)
    NEW_WINDOW_MODE=true
    shift
    ;;
  --projects)
    PROJECTS_MODE=true
    shift
    ;;
  --tmux)
    TMUX_POPUP=true
    # Optional dimension argument: --tmux=center,80%,50% or --tmux center,80%,50%
    if [[ $# -gt 1 ]] && [[ "$2" != --* ]]; then
      TMUX_OPTS_ARG="$2"
      shift 2
    else
      shift
    fi
    ;;
  --tmux=*)
    TMUX_POPUP=true
    TMUX_OPTS_ARG="${1#--tmux=}"
    shift
    ;;
  --ansi)
    ANSI_FLAG=true
    shift
    ;;
  --fzf-opts)
    FZF_OPTS="$2"
    shift 2
    ;;
  --fzf-opts=*)
    FZF_OPTS="${1#--fzf-opts=}"
    shift
    ;;
  --prefix)
    PREFIX="$2"
    shift 2
    ;;
  --prefix=*)
    PREFIX="${1#--prefix=}"
    shift
    ;;
  -h | --help)
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --list          List sessions without fzf"
    echo "  --copy          Copy selected session ID to clipboard"
    echo "  --multi         Multi-select mode (TAB to mark)"
    echo "  --filter STATUS Filter by: working, needs-input, error, idle"
    echo "  --sort FIELD    Initial sort: time (default), directory"
    echo "  --dir DIR       Filter by specific directory (exact match)"
    echo "  --days N        Show sessions from last N days (default: 14)"
    echo "  --all           Show all sessions regardless of age"
    echo "  --projects      Browse projects instead of sessions"
    echo "  --tmux [OPTS]   Open fzf in a floating tmux popup (requires tmux 3.3+)"
    echo "                  OPTS: e.g. center,80%,50% or right,40% (default: center,80%)"
    echo "  --ansi          Enable ANSI colored output (status indicators, headers, preview)"
    echo "  --fzf-opts OPTS Custom fzf options (overrides default)"
    echo "  --prefix STR    Tmux session name prefix"
    echo "  --new-window    Open session in new window without switching tmux"
    echo "  -h, --help      Show this help"
    exit 0
    ;;
  *)
    echo "Unknown option: $1" >&2
    exit 1
    ;;
  esac
done

# ─── Re-evaluate ANSI after arg parsing ──────────────────────────────────────
# --ansi flag or --ansi in --fzf-opts enables colored output
if [[ "$ANSI_FLAG" == "true" ]] || echo "$FZF_OPTS" | grep -qw -- '--ansi'; then
  USE_ANSI=true
  # Ensure --ansi is in FZF_OPTS for fzf itself
  echo "$FZF_OPTS" | grep -qw -- '--ansi' || FZF_OPTS="--ansi $FZF_OPTS"
else
  USE_ANSI=false
fi
source "${SCRIPT_DIR}/lib/colors.sh"

# ─── Validation ───────────────────────────────────────────────────────────────
if [[ ! -f "$DB_PATH" ]]; then
  echo -e "${RED}Error: opencode database not found at ${DB_PATH}${RESET}" >&2
  echo "Run opencode at least once to create the database." >&2
  exit 1
fi

if ! command -v sqlite3 &>/dev/null; then
  echo -e "${RED}Error: sqlite3 is required but not installed${RESET}" >&2
  exit 1
fi

if ! command -v fzf &>/dev/null; then
  echo -e "${RED}Error: fzf is required but not installed${RESET}" >&2
  exit 1
fi

if [[ ! -f "$PREVIEW_SCRIPT" ]]; then
  echo -e "${RED}Error: preview.sh not found at ${PREVIEW_SCRIPT}${RESET}" >&2
  exit 1
fi

# ─── Tmux popup setup ─────────────────────────────────────────────────────────
# When --tmux is passed, strip --height from FZF_OPTS (incompatible with --tmux)
# and add the --tmux flag to all fzf invocations.
# Dimension options can come from: --tmux=OPTS arg, or @opencode-sessions-tmux-opts tmux option.
FZF_TMUX_OPTS=""
if [[ "$TMUX_POPUP" == "true" ]]; then
  if ! is_in_tmux; then
    echo -e "${YELLOW}Warning: --tmux requires running inside tmux, ignoring${RESET}" >&2
    TMUX_POPUP=false
  else
    # Strip --height (and its value) from FZF_OPTS — incompatible with --tmux popup
    FZF_OPTS=$(echo "$FZF_OPTS" | sed -E 's/--height[= ]+[0-9]+%?//g')
    # Build --tmux option string: CLI arg takes priority, then hardcoded default
    FZF_TMUX_OPTS="--tmux=${TMUX_OPTS_ARG:-center,80%}"
  fi
fi

# ─── List mode ────────────────────────────────────────────────────────────────

run_list() {
  # Cache session data once — avoid querying DB twice
  local cache_file
  cache_file=$(mktemp)
  trap 'rm -f "${cache_file:-}"' RETURN

  build_session_data query_all_sessions "$FILTER_STATUS" "$DB_PATH" "$DAYS_FILTER" "$SHOW_ALL" "$DIR_FILTER" >"$cache_file"

  local filtered_count
  filtered_count=$(wc -l <"$cache_file")

  # Show count header if filtering
  if [[ "$SHOW_ALL" != "true" && "$DAYS_FILTER" -gt 0 ]]; then
    local total_count
    total_count=$(get_total_count "$DB_PATH")
    if [[ "$filtered_count" != "$total_count" ]]; then
      echo -e "${DIM}Showing ${filtered_count} of ${total_count} sessions (last ${DAYS_FILTER} days)${RESET}"
    fi
  fi

  echo -e "${WHITE}$(printf '%-8s' 'Status') $(printf '%-10s' 'Updated') $(printf '%-20s' 'Repo') Session Title [Model]${RESET}"
  echo -e "${DIM}$(printf '%.0s─' {1..100})${RESET}"

  sort_data "$SORT_BY" <"$cache_file" | format_for_list | while IFS=$'\t' read -r line; do
    echo -e "$line"
  done
}

# ─── Interactive fzf mode ─────────────────────────────────────────────────────

run_interactive() {
  echo -e "${CYAN}Loading sessions...${RESET}" >&2

  # Cache all session data
  local cache_file
  cache_file=$(mktemp)
  trap 'rm -f "${cache_file:-}"' EXIT

  build_session_data query_all_sessions "$FILTER_STATUS" "$DB_PATH" "$DAYS_FILTER" "$SHOW_ALL" "$DIR_FILTER" >"$cache_file"

  if [[ ! -s "$cache_file" ]]; then
    echo -e "${YELLOW}No sessions found.${RESET}"
    exit 0
  fi

  # Get counts for display
  local filtered_count
  local total_count=0
  filtered_count=$(wc -l <"$cache_file")

  if [[ "$SHOW_ALL" != "true" && "$DAYS_FILTER" -gt 0 ]]; then
    total_count=$(get_total_count "$DB_PATH")
    if [[ "$filtered_count" != "$total_count" ]]; then
      echo -e "${DIM}Showing ${filtered_count} of ${total_count} sessions (last ${DAYS_FILTER} days)${RESET}" >&2
    fi
  fi

  # Pre-format once into a sortable display file
  # Format: id\tdisplay_line\ttime_updated\trepo
  # fzf shows col 2; ctrl-s just sorts on col 3 (time) or col 4 (repo)+col 3
  local display_file
  display_file=$(mktemp)
  trap 'rm -f "${cache_file:-}" "${display_file:-}"' EXIT
  format_for_display <"$cache_file" >"$display_file"

  local fzf_flags=()
  if [[ "$MODE" == "multi" ]]; then
    fzf_flags+=(--multi)
  fi

  # State file for sort cycling
  local sort_state_file
  sort_state_file=$(mktemp)
  case "$SORT_BY" in
  time) echo "0" >"$sort_state_file" ;;
  directory) echo "1" >"$sort_state_file" ;;
  *) echo "0" >"$sort_state_file" ;;
  esac

  # Cycle script — just sorts the display file on different columns
  local cycle_script
  cycle_script=$(mktemp)
  trap 'rm -f "${cache_file:-}" "${display_file:-}" "${cycle_script:-}" "${sort_state_file:-}" "${footer_script:-}"' EXIT

  # Footer script - reads sort state and outputs footer text
  local footer_script
  footer_script=$(mktemp)
  trap 'rm -f "${cache_file:-}" "${display_file:-}" "${cycle_script:-}" "${sort_state_file:-}" "${footer_script:-}"' EXIT

  cat >"$footer_script" <<FOOTER_EOF
#!/usr/bin/env bash
STATE_FILE="$sort_state_file"
sort_order=("time" "directory")
idx=\$(cat "\$STATE_FILE")
sort_field="\${sort_order[\$idx]}"
echo "CTRL-S: cycle sort (current: \$sort_field) | ↑/↓: navigate | Enter: resume | Ctrl-o: new window | ?: toggle preview"
FOOTER_EOF
  chmod +x "$footer_script"

  cat >"$cycle_script" <<CYCLE_EOF
#!/usr/bin/env bash
STATE_FILE="$sort_state_file"
DISPLAY_FILE="$display_file"

idx=\$(cat "\$STATE_FILE")
idx=\$(( (idx + 1) % 2 ))
echo "\$idx" > "\$STATE_FILE"

if [[ "\$idx" == "0" ]]; then
    sort -t\$'\\t' -k3,3rn "\$DISPLAY_FILE"
else
    sort -t\$'\\t' -k4,4 -k3,3rn "\$DISPLAY_FILE"
fi
CYCLE_EOF
  chmod +x "$cycle_script"

  # Initial sort (array preserves literal tab from $'\t')
  local initial_sort_cmd=(sort -t$'\t')
  case "$SORT_BY" in
  directory) initial_sort_cmd+=(-k4,4 -k3,3rn) ;;
  *) initial_sort_cmd+=(-k3,3rn) ;;
  esac

  # Run fzf with footer and ctrl-s sort cycling
  local selected
  selected=$("${initial_sort_cmd[@]}" <"$display_file" | fzf \
    $FZF_OPTS \
    $FZF_TMUX_OPTS \
    --expect=ctrl-o \
    --with-nth 2 \
    --border-label " OpenCode Sessions " \
    --preview "USE_ANSI=${USE_ANSI} bash '${PREVIEW_SCRIPT}' {}" \
    --preview-window "right:60%,border-left" \
    --delimiter '\t' \
    --prompt="Select session: " \
    --footer "CTRL-S: cycle sort (current: $SORT_BY) | ↑/↓: navigate | Enter: resume | Ctrl-o: new window | ?: toggle preview" \
    --bind "?:toggle-preview" \
    --bind "ctrl-s:reload(bash '${cycle_script}')+transform-footer(bash '${footer_script}')" \
    "${fzf_flags[@]}" \
    2>/dev/null) || true

  if [[ -z "$selected" ]]; then
    echo -e "${DIM}No session selected.${RESET}"
    exit 0
  fi

  # Extract the key pressed (first line) and selection (remaining lines)
  local key_pressed=""
  local selection=""
  if [[ -n "$selected" ]]; then
    key_pressed=$(echo "$selected" | head -1)
    selection=$(echo "$selected" | tail -n +2)
  fi

  # Determine if this is new-window mode (Ctrl-o pressed or --new-window flag)
  local is_new_window="$NEW_WINDOW_MODE"
  if [[ "$key_pressed" == "ctrl-o" ]]; then
    is_new_window="true"
  fi

  # Restore selected for further processing
  selected="$selection"

  # Handle empty selection after key extraction
  if [[ -z "$selected" ]]; then
    echo -e "${DIM}No session selected.${RESET}"
    exit 0
  fi

  # Extract session ID(s)
  local session_ids=()
  while IFS= read -r line; do
    local sid
    sid=$(echo "$line" | cut -f1)
    session_ids+=("$sid")
  done <<<"$selected"

  if [[ "$MODE" == "copy" ]]; then
    local copy_text
    copy_text=$(printf '%s\n' "${session_ids[@]}")
    if command -v xclip &>/dev/null; then
      echo "$copy_text" | xclip -selection clipboard
    elif command -v pbcopy &>/dev/null; then
      echo "$copy_text" | pbcopy
    elif command -v wl-copy &>/dev/null; then
      echo "$copy_text" | wl-copy
    else
      echo -e "${YELLOW}Session IDs:${RESET}"
      echo "$copy_text"
      echo -e "${DIM}(No clipboard tool found, copy manually)${RESET}"
    fi
    echo -e "${GREEN}Copied ${#session_ids[@]} session ID(s) to clipboard${RESET}"
    exit 0
  fi

  # Resume the first selected session with tmux session handling
  # If new-window mode with multiple sessions, handle each
  if [[ "$is_new_window" == "true" ]] && [[ ${#session_ids[@]} -gt 1 ]]; then
    for sid in "${session_ids[@]}"; do
      handle_session "$sid" "true"
    done
  else
    # Single session or non-new-window mode
    handle_session "${session_ids[0]}" "$is_new_window"
  fi
}

# ─── Projects list mode ──────────────────────────────────────────────────────

run_projects_list() {
  local filtered_count=0

  filtered_count=$(build_project_data query_projects "$FILTER_STATUS" "$DB_PATH" "$DAYS_FILTER" "$SHOW_ALL" | wc -l)

  echo -e "${WHITE}$(printf '%-8s' 'Status') $(printf '%-10s' 'Updated') $(printf '%-20s' 'Project') (Sessions) [Model]${RESET}"
  echo -e "${DIM}$(printf '%.0s─' {1..100})${RESET}"

  build_project_data query_projects "$FILTER_STATUS" "$DB_PATH" "$DAYS_FILTER" "$SHOW_ALL" | sort -t$'\t' -k8,8rn | format_projects_for_list | while IFS=$'\t' read -r line; do
    echo -e "$line"
  done
}

# ─── Projects interactive fzf mode ───────────────────────────────────────────

run_projects_interactive() {
  echo -e "${CYAN}Loading projects...${RESET}" >&2

  local cache_file
  cache_file=$(mktemp)
  trap 'rm -f "${cache_file:-}"' EXIT

  build_project_data query_projects "$FILTER_STATUS" "$DB_PATH" "$DAYS_FILTER" "$SHOW_ALL" >"$cache_file"

  if [[ ! -s "$cache_file" ]]; then
    echo -e "${YELLOW}No projects found.${RESET}"
    exit 0
  fi

  local sorted_file
  sorted_file=$(mktemp)
  trap 'rm -f "${cache_file:-}" "${sorted_file:-}"' EXIT
  sort -t$'\t' -k8,8rn <"$cache_file" >"$sorted_file"

  local fzf_flags=()
  if [[ "$MODE" == "multi" ]]; then
    fzf_flags+=(--multi)
  fi

  local project_preview_script="${SCRIPT_DIR}/scripts/preview-projects.sh"

  local selected
  selected=$(format_projects_for_display <"$sorted_file" | fzf \
    $FZF_OPTS \
    $FZF_TMUX_OPTS \
    --expect=ctrl-o \
    --with-nth 2.. \
    --border-label " OpenCode Projects " \
    --preview "USE_ANSI=${USE_ANSI} bash '${project_preview_script}' {}" \
    --preview-window "right:60%,border-left" \
    --delimiter '\t' \
    --prompt="Select project: " \
    --footer "↑/↓: navigate | Enter: latest session | Ctrl-o: new window | ?: toggle preview" \
    --bind "?:toggle-preview" \
    "${fzf_flags[@]}" \
    2>/dev/null) || true

  if [[ -z "$selected" ]]; then
    echo -e "${DIM}No project selected.${RESET}"
    exit 0
  fi

  # Extract the key pressed (first line) and selection (remaining lines)
  local key_pressed=""
  local selection=""
  if [[ -n "$selected" ]]; then
    key_pressed=$(echo "$selected" | head -1)
    selection=$(echo "$selected" | tail -n +2)
  fi

  local is_new_window="$NEW_WINDOW_MODE"
  if [[ "$key_pressed" == "ctrl-o" ]]; then
    is_new_window="true"
  fi

  selected="$selection"

  if [[ -z "$selected" ]]; then
    echo -e "${DIM}No project selected.${RESET}"
    exit 0
  fi

  # Extract project ID(s)
  local project_ids=()
  while IFS= read -r line; do
    local pid
    pid=$(echo "$line" | cut -f1)
    project_ids+=("$pid")
  done <<<"$selected"

  if [[ "$MODE" == "copy" ]]; then
    local copy_text
    copy_text=$(printf '%s\n' "${project_ids[@]}")
    if command -v xclip &>/dev/null; then
      echo "$copy_text" | xclip -selection clipboard
    elif command -v pbcopy &>/dev/null; then
      echo "$copy_text" | pbcopy
    elif command -v wl-copy &>/dev/null; then
      echo "$copy_text" | wl-copy
    else
      echo -e "${YELLOW}Project IDs:${RESET}"
      echo "$copy_text"
      echo -e "${DIM}(No clipboard tool found, copy manually)${RESET}"
    fi
    echo -e "${GREEN}Copied ${#project_ids[@]} project ID(s) to clipboard${RESET}"
    exit 0
  fi

  # Resume the latest session for the selected project
  if [[ "$is_new_window" == "true" ]] && [[ ${#project_ids[@]} -gt 1 ]]; then
    for pid in "${project_ids[@]}"; do
      handle_project "$pid" "true"
    done
  else
    handle_project "${project_ids[0]}" "$is_new_window"
  fi
}

# ─── Handle project selection (resume latest session) ────────────────────────

handle_project() {
  local project_id="$1"
  local is_new_window="${2:-false}"

  # Get project name for display
  local project_name
  project_name=$(sqlite3 "$DB_PATH" "SELECT name FROM project WHERE id = '${project_id}';")
  [[ -z "$project_name" ]] && project_name="$project_id"

  # Check if there are any active sessions for this project
  local session_count
  session_count=$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM session_v2
    WHERE project_id = '${project_id}'
      AND time_archived IS NULL AND parent_id IS NULL;
  ")

  if [[ "$session_count" -eq 0 ]]; then
    echo -e "${YELLOW}No active sessions for project: ${project_name}${RESET}"
    # Get the project worktree to start a new session
    local worktree
    worktree=$(sqlite3 "$DB_PATH" "SELECT worktree FROM project WHERE id = '${project_id}';")
    if [[ -n "$worktree" ]] && [[ -d "$worktree" ]]; then
      echo -e "${DIM}Starting opencode in ${worktree}${RESET}"
      if is_in_tmux; then
        local session_name
        session_name=$(derive_repo_name "$worktree")
        if tmux has-session -t "$session_name" 2>/dev/null; then
          tmux new-window -t "$session_name" -c "$worktree" -n "opencode" "exec opencode"
        else
          tmux new-session -d -s "$session_name" -c "$worktree" "exec opencode"
          tmux switch-client -t "$session_name"
        fi
      else
        cd "$worktree" && exec opencode
      fi
    else
      echo -e "${RED}Project worktree not found or does not exist${RESET}"
      exit 1
    fi
    exit 0
  fi

  # If only one session, resume it directly
  if [[ "$session_count" -eq 1 ]]; then
    local session_id
    session_id=$(sqlite3 "$DB_PATH" "
      SELECT id FROM session_v2
      WHERE project_id = '${project_id}'
        AND time_archived IS NULL AND parent_id IS NULL
      ORDER BY time_updated DESC LIMIT 1;
    ")
    handle_session "$session_id" "$is_new_window"
    return
  fi

  # Multiple sessions: launch session picker filtered by project
  echo -e "${CYAN}Loading sessions for: ${project_name}${RESET}" >&2

  local cache_file
  cache_file=$(mktemp)
  trap 'rm -f "${cache_file:-}"' EXIT

  build_session_data query_all_sessions "$FILTER_STATUS" "$DB_PATH" 0 "true" "" "$project_id" >"$cache_file"

  if [[ ! -s "$cache_file" ]]; then
    echo -e "${YELLOW}No sessions found for project: ${project_name}${RESET}"
    exit 0
  fi

  local sorted_file
  sorted_file=$(mktemp)
  trap 'rm -f "${cache_file:-}" "${sorted_file:-}"' EXIT
  sort_data "$SORT_BY" <"$cache_file" >"$sorted_file"

  local selected
  selected=$(format_for_display <"$sorted_file" | fzf \
    $FZF_OPTS \
    $FZF_TMUX_OPTS \
    --expect=ctrl-o \
    --with-nth 2.. \
    --border-label " ${project_name} Sessions " \
    --preview "USE_ANSI=${USE_ANSI} bash '${PREVIEW_SCRIPT}' {}" \
    --preview-window "right:60%,border-left" \
    --delimiter '\t' \
    --prompt="Select session: " \
    --footer "↑/↓: navigate | Enter: resume | Ctrl-o: new window | ?: toggle preview" \
    --bind "?:toggle-preview" \
    2>/dev/null) || true

  if [[ -z "$selected" ]]; then
    echo -e "${DIM}No session selected.${RESET}"
    exit 0
  fi

  # Extract key and selection
  local key_pressed=""
  local selection=""
  key_pressed=$(echo "$selected" | head -1)
  selection=$(echo "$selected" | tail -n +2)

  local nw="$is_new_window"
  [[ "$key_pressed" == "ctrl-o" ]] && nw="true"

  if [[ -z "$selection" ]]; then
    echo -e "${DIM}No session selected.${RESET}"
    exit 0
  fi

  local session_id
  session_id=$(echo "$selection" | cut -f1)
  handle_session "$session_id" "$nw"
}

# ─── Handle tmux session creation/switching ─────────────────────────────────

handle_session() {
  local session_id="$1"
  local is_new_window="${2:-false}"

  # Get session directory from database
  local directory
  directory=$(sqlite3 "$DB_PATH" "SELECT directory FROM session_v2 WHERE id = '${session_id}';")

  if [[ -z "$directory" ]]; then
    echo -e "${RED}Error: Could not find directory for session ${session_id}${RESET}"
    exit 1
  fi

  if [[ ! -d "$directory" ]]; then
    echo -e "${RED}Error: Directory does not exist: ${directory}${RESET}"
    exit 1
  fi

  # Derive tmux session name from directory
  local session_name
  session_name=$(derive_repo_name "$directory")

  # Apply optional tmux session name prefix
  if [[ -n "$PREFIX" && "$PREFIX" != "false" ]]; then
    session_name="${PREFIX}${session_name}"
  fi

  echo -e "${GREEN}Resuming session: ${session_id}${RESET}"
  echo -e "${DIM}Directory: ${directory}${RESET}"
  echo -e "${DIM}Tmux session: ${session_name}${RESET}"

  # If new-window mode and not in tmux, fall back to cd + exec
  if [[ "$is_new_window" == "true" ]] && ! is_in_tmux; then
    echo -e "${DIM}Not in tmux - running opencode directly in directory${RESET}"
    cd "$directory" && exec opencode -s "$session_id"
  fi

  # Handle based on new-window mode and tmux availability
  if [[ "$is_new_window" == "true" ]] && is_in_tmux; then
    # Create new window in current tmux session (don't switch)
    local current_session
    current_session=$(get_current_tmux_session)
    echo -e "${DIM}Creating new window in current tmux session: ${current_session}${RESET}"
    tmux new-window -t "$current_session" -c "$directory" -n "opencode" "exec opencode -s ${session_id}"
    # Do NOT switch - stay in current window
  elif tmux has-session -t "$session_name" 2>/dev/null; then
    # Session exists - create new window
    echo -e "${DIM}Creating new window in existing tmux session${RESET}"
    tmux new-window -t "$session_name" -c "$directory" -n "opencode" "exec opencode -s ${session_id}"
    tmux switch-client -t "$session_name"
  else
    # Create new tmux session
    echo -e "${DIM}Creating new tmux session${RESET}"
    tmux new-session -d -s "$session_name" -c "$directory" "exec opencode -s ${session_id}"
    tmux switch-client -t "$session_name"
  fi
}

# ─── Main entry point ─────────────────────────────────────────────────────────

case "$MODE" in
list)
  if [[ "$PROJECTS_MODE" == "true" ]]; then
    run_projects_list
  else
    run_list
  fi
  ;;
interactive | copy | multi)
  if [[ "$PROJECTS_MODE" == "true" ]]; then
    run_projects_interactive
  else
    run_interactive
  fi
  ;;
esac
