#!/usr/bin/env bash
# muster/lib/core/logger.sh — Logging functions
# Respects MUSTER_QUIET (suppress info) and MUSTER_VERBOSE (enable debug)

log()   { [[ "$MUSTER_QUIET" == "true" ]] && return; printf '%b  %b>%b %s\n' "" "$GREEN" "$RESET" "$1"; }
warn()  { printf '%b  %b!%b %s\n' "" "$YELLOW" "$RESET" "$1"; }
err()   { printf '%b  %bx%b %s\n' "" "$RED" "$RESET" "$1"; }
ok()    { [[ "$MUSTER_QUIET" == "true" ]] && return; printf '%b  %b*%b %s\n' "" "$GREEN" "$RESET" "$1"; }
info()  { [[ "$MUSTER_QUIET" == "true" ]] && return; printf '%b  %bi%b %s\n' "" "$ACCENT" "$RESET" "$1"; }
debug() { [[ "$MUSTER_VERBOSE" != "true" ]] && return; printf '%b  %b.%b %s\n' "" "$DIM" "$RESET" "$1"; }
