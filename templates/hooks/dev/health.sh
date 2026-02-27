#!/usr/bin/env bash
# Health check for {{SERVICE_NAME}} — PID alive + optional HTTP ping

SERVICE="{{SERVICE_NAME}}"
PORT="{{PORT}}"
PID_FILE=".muster/pids/${SERVICE}.pid"

# Check PID is alive
if [[ ! -f "$PID_FILE" ]]; then
  exit 1
fi

pid=$(cat "$PID_FILE" 2>/dev/null)
if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
  exit 1
fi

# HTTP ping (best-effort, non-fatal)
if [[ -n "$PORT" && "$PORT" != "0" ]]; then
  if command -v curl &>/dev/null; then
    curl -sf -o /dev/null --max-time 3 "http://localhost:${PORT}/" 2>/dev/null || true
  fi
fi

exit 0
