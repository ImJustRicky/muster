#!/usr/bin/env bash
# Stream logs for {{SERVICE_NAME}} via journalctl

journalctl -u "{{SERVICE_NAME}}" -f --no-pager -n 100
