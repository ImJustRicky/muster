#!/usr/bin/env bash
# Stream logs for {{SERVICE_NAME}} via Docker

docker logs -f "{{SERVICE_NAME}}" --tail=100
