#!/usr/bin/env bash
# Color codes for opencode-sessions
# When USE_ANSI is not set or false, all color variables are empty strings
# so output is plain text without escape codes

if [[ "${USE_ANSI:-false}" == "true" ]]; then
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	YELLOW='\033[0;33m'
	CYAN='\033[0;36m'
	WHITE='\033[1;37m'
	DIM='\033[2m'
	RESET='\033[0m'
else
	RED=''
	GREEN=''
	YELLOW=''
	CYAN=''
	WHITE=''
	DIM=''
	RESET=''
fi
