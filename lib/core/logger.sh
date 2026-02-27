#!/usr/bin/env bash
# muster/lib/core/logger.sh — Logging functions

log()  { echo -e "  ${GREEN}>${RESET} $1"; }
warn() { echo -e "  ${YELLOW}!${RESET} $1"; }
err()  { echo -e "  ${RED}x${RESET} $1"; }
ok()   { echo -e "  ${GREEN}*${RESET} $1"; }
info() { echo -e "  ${ACCENT}i${RESET} $1"; }
