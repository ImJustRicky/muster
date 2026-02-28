#!/usr/bin/env bats
load test_helper

@test "_load_env_file: loads KEY=VALUE pairs" {
  echo 'FOO=bar' > "$TEST_TEMP/.env"
  echo 'BAZ=qux' >> "$TEST_TEMP/.env"
  CONFIG_FILE="$TEST_TEMP/deploy.json"
  touch "$CONFIG_FILE"
  _load_env_file "$TEST_TEMP/.env"
  [ "$FOO" = "bar" ]
  [ "$BAZ" = "qux" ]
  _unload_env_file
}

@test "_load_env_file: skips comments and blank lines" {
  printf '# comment\n\nFOO=bar\n  # another comment\n' > "$TEST_TEMP/.env"
  CONFIG_FILE="$TEST_TEMP/deploy.json"
  touch "$CONFIG_FILE"
  _load_env_file "$TEST_TEMP/.env"
  [ "$FOO" = "bar" ]
  _unload_env_file
}

@test "_load_env_file: handles quoted values" {
  printf 'FOO="hello world"\nBAR='"'"'single quotes'"'"'\n' > "$TEST_TEMP/.env"
  CONFIG_FILE="$TEST_TEMP/deploy.json"
  touch "$CONFIG_FILE"
  _load_env_file "$TEST_TEMP/.env"
  [ "$FOO" = "hello world" ]
  [ "$BAR" = "single quotes" ]
  _unload_env_file
}

@test "_load_env_file: does not override existing vars" {
  export EXISTING_VAR="original"
  echo 'EXISTING_VAR=overwritten' > "$TEST_TEMP/.env"
  CONFIG_FILE="$TEST_TEMP/deploy.json"
  touch "$CONFIG_FILE"
  _load_env_file "$TEST_TEMP/.env"
  [ "$EXISTING_VAR" = "original" ]
  unset EXISTING_VAR
  _unload_env_file
}

@test "_unload_env_file: cleans up loaded vars" {
  echo 'CLEANUP_TEST=yes' > "$TEST_TEMP/.env"
  CONFIG_FILE="$TEST_TEMP/deploy.json"
  touch "$CONFIG_FILE"
  _load_env_file "$TEST_TEMP/.env"
  [ "$CLEANUP_TEST" = "yes" ]
  _unload_env_file
  [ -z "${CLEANUP_TEST:-}" ]
}
