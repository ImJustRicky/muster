#!/usr/bin/env bash
set -eo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v bats &>/dev/null; then
  echo "bats-core not found. Install: brew install bats-core"
  exit 1
fi

bats "$SCRIPT_DIR"/*.bats "$@"
