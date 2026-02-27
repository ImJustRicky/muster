#!/usr/bin/env bash
# muster/lib/core/colors.sh — Terminal colors and styling

BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# Mustard accent — the muster brand color
MUSTARD='\033[38;5;178m'
MUSTARD_BRIGHT='\033[38;5;220m'
MUSTARD_DIM='\033[38;5;136m'

GREEN='\033[38;5;114m'
RED='\033[38;5;203m'
YELLOW='\033[38;5;221m'
GRAY='\033[38;5;243m'
WHITE='\033[38;5;255m'
BLUE='\033[38;5;75m'
MAGENTA='\033[38;5;176m'

# Accent alias — used throughout the TUI
ACCENT="$MUSTARD"
ACCENT_BRIGHT="$MUSTARD_BRIGHT"
