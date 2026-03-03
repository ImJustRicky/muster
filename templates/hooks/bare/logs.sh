#!/usr/bin/env bash
set -euo pipefail
# Stream logs for {{SERVICE_NAME}} via journalctl

journalctl -u "{{SERVICE_NAME}}" -f --no-pager -n 100
