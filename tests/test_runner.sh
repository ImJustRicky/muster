#!/usr/bin/env bash
# tests/test_runner.sh — Discover and run all test files
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
failures=0
ran=0

for f in "$SCRIPT_DIR"/test_*.sh "$SCRIPT_DIR"/test-*.sh; do
  [[ -f "$f" ]] || continue
  name=$(basename "$f")
  # Skip helpers and this runner
  [[ "$name" == "test_helpers.sh" ]] && continue
  [[ "$name" == "test_runner.sh" ]] && continue

  echo ""
  echo "=== ${name} ==="
  ran=$(( ran + 1 ))
  if ! bash "$f"; then
    failures=$(( failures + 1 ))
  fi
done

echo ""
echo "────────────────────────────────"
if (( failures == 0 )); then
  printf '\033[38;5;114mAll %d test files passed\033[0m\n' "$ran"
else
  printf '\033[38;5;203m%d/%d test files had failures\033[0m\n' "$failures" "$ran"
fi
echo ""

exit $failures
