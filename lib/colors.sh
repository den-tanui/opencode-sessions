#!/usr/bin/env bash
# Color codes and status icons for opencode-sessions
# When USE_ANSI is not set or false, all color variables are empty strings
# and status icons are plain ASCII instead of colored emoji.

if [[ "${USE_ANSI:-false}" == "true" ]]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[0;33m'
	CYAN='\033[0;36m'
	MAGENTA='\033[0;35m'
	WHITE='\033[1;37m'
	DIM='\033[2m'
	BOLD='\033[1m'
	RESET='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	CYAN=''
	MAGENTA=''
	WHITE=''
	DIM=''
	BOLD=''
	RESET=''
fi

# Status icon — returns colored emoji with ANSI, plain ASCII without
# Usage: status_icon "working" → 🟢 (ANSI) or * (plain)
status_icon() {
	if [[ "${USE_ANSI:-false}" == "true" ]]; then
		case "$1" in
		needs-input) echo -e "${YELLOW}🟡${RESET}" ;;
		error)       echo -e "${RED}🔴${RESET}" ;;
		working)     echo -e "${GREEN}🟢${RESET}" ;;
		idle)        echo -e "${DIM}⚪${RESET}" ;;
		*)           echo -e "${DIM}⚪${RESET}" ;;
		esac
	else
		case "$1" in
		needs-input) echo "?" ;;
		error)       echo "!" ;;
		working)     echo "*" ;;
		idle)        echo "." ;;
		*)           echo "." ;;
		esac
	fi
}

# Status icon with label — for preview panes
# Usage: status_icon_label "working" → "🟢 working" (ANSI) or "* working" (plain)
status_icon_label() {
	if [[ "${USE_ANSI:-false}" == "true" ]]; then
		case "$1" in
		needs-input) echo -e "${YELLOW}🟡${RESET} ${YELLOW}needs-input${RESET}" ;;
		error)       echo -e "${RED}🔴${RESET} ${RED}error${RESET}" ;;
		working)     echo -e "${GREEN}🟢${RESET} ${GREEN}working${RESET}" ;;
		idle)        echo -e "${DIM}⚪${RESET} ${DIM}idle${RESET}" ;;
		*)           echo -e "${DIM}⚪${RESET} ${DIM}unknown${RESET}" ;;
		esac
	else
		case "$1" in
		needs-input) echo "? needs-input" ;;
		error)       echo "! error" ;;
		working)     echo "* working" ;;
		idle)        echo ". idle" ;;
		*)           echo ". unknown" ;;
		esac
	fi
}
