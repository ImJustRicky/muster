#!/usr/bin/env bats
load test_helper

setup() {
  TEST_TEMP="$(mktemp -d)"
  source "$MUSTER_ROOT/lib/core/scanner.sh"
}

@test "_scan_detect_dev_cmds: detects Node.js from package.json" {
  mkdir -p "$TEST_TEMP/project"
  echo '{"scripts":{"dev":"next dev"}}' > "$TEST_TEMP/project/package.json"
  _scan_detect_dev_cmds "$TEST_TEMP/project"
  [ ${#_SCAN_DEV_CMDS[@]} -gt 0 ]
  echo "${_SCAN_DEV_CMDS[0]}" | grep -q "npm run dev"
}

@test "_scan_detect_dev_cmds: detects Go from go.mod" {
  mkdir -p "$TEST_TEMP/project/cmd/server"
  echo 'module example.com/app' > "$TEST_TEMP/project/go.mod"
  echo 'package main' > "$TEST_TEMP/project/cmd/server/main.go"
  _scan_detect_dev_cmds "$TEST_TEMP/project"
  [ ${#_SCAN_DEV_CMDS[@]} -gt 0 ]
  echo "${_SCAN_DEV_CMDS[0]}" | grep -q "go run"
}

@test "_scan_detect_dev_cmds: detects Python with requirements.txt" {
  mkdir -p "$TEST_TEMP/project"
  echo 'django' > "$TEST_TEMP/project/requirements.txt"
  echo '' > "$TEST_TEMP/project/manage.py"
  _scan_detect_dev_cmds "$TEST_TEMP/project"
  [ ${#_SCAN_DEV_CMDS[@]} -gt 0 ]
  echo "${_SCAN_DEV_CMDS[0]}" | grep -q "manage.py"
}

@test "scan_project: detects compose stack" {
  mkdir -p "$TEST_TEMP/project"
  echo 'version: "3"' > "$TEST_TEMP/project/docker-compose.yml"
  scan_project "$TEST_TEMP/project"
  [ "$_SCAN_STACK" = "compose" ]
}

@test "_scan_is_excluded: auto-excludes archived directory" {
  _SCAN_EXCLUDES=""
  _scan_is_excluded "$TEST_TEMP" "archived/foo"
}

@test "_scan_is_excluded: auto-excludes deprecated directory" {
  _SCAN_EXCLUDES=""
  _scan_is_excluded "$TEST_TEMP" "deprecated/bar"
}

@test "_scan_is_excluded: respects _SCAN_EXCLUDES" {
  _SCAN_EXCLUDES="node_modules .git"
  _scan_is_excluded "$TEST_TEMP" "node_modules/foo"
}

@test "_scan_is_excluded: does not exclude normal directories" {
  _SCAN_EXCLUDES=""
  ! _scan_is_excluded "$TEST_TEMP" "src/main.go"
}
