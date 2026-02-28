#!/usr/bin/env bats
load test_helper

setup() {
  TEST_TEMP="$(mktemp -d)"
  source "$MUSTER_ROOT/lib/core/scanner.sh"
  source "$MUSTER_ROOT/lib/tui/menu.sh"
  source "$MUSTER_ROOT/lib/tui/checklist.sh"
  source "$MUSTER_ROOT/lib/tui/spinner.sh"
  source "$MUSTER_ROOT/lib/tui/order.sh"
  source "$MUSTER_ROOT/lib/commands/setup.sh"
}

# ── Template file existence ──

@test "k8s templates: all 5 hook files exist" {
  for hook in deploy.sh health.sh rollback.sh logs.sh cleanup.sh; do
    [ -f "$MUSTER_ROOT/templates/hooks/k8s/$hook" ]
  done
}

@test "k8s infra templates: all 5 hook files exist" {
  for hook in deploy.sh health.sh rollback.sh logs.sh cleanup.sh; do
    [ -f "$MUSTER_ROOT/templates/hooks/k8s/infra/$hook" ]
  done
}

@test "all templates pass bash -n" {
  for stack in k8s compose docker bare dev; do
    local dir="$MUSTER_ROOT/templates/hooks/$stack"
    [ -d "$dir" ] || continue
    for f in "$dir"/*.sh; do
      [ -f "$f" ] || continue
      bash -n "$f"
    done
    if [ -d "$dir/infra" ]; then
      for f in "$dir/infra"/*.sh; do
        [ -f "$f" ] || continue
        bash -n "$f"
      done
    fi
  done
}

# ── _setup_copy_hooks: k8s app service ──

@test "generate k8s app hooks: creates all 5 executable files" {
  local hook_dir="$TEST_TEMP/hooks/api"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "api" "api" "$hook_dir" \
    "docker-compose.yml" "Dockerfile" "k8s/api/" "production" "8080" "waity-api" ""

  for hook in deploy.sh health.sh rollback.sh logs.sh cleanup.sh; do
    [ -f "$hook_dir/$hook" ]
    [ -x "$hook_dir/$hook" ]
  done
}

@test "generate k8s app hooks: substitutes service name" {
  local hook_dir="$TEST_TEMP/hooks/api"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "api" "api" "$hook_dir" \
    "docker-compose.yml" "Dockerfile" "k8s/api/" "production" "8080" "waity-api" ""

  grep -q 'waity-api' "$hook_dir/deploy.sh"
  grep -q 'production' "$hook_dir/deploy.sh"
}

@test "generate k8s app hooks: no leftover placeholders" {
  local hook_dir="$TEST_TEMP/hooks/api"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "api" "api" "$hook_dir" \
    "docker-compose.yml" "Dockerfile" "k8s/api/" "production" "8080" "waity-api" ""

  for f in "$hook_dir"/*.sh; do
    ! grep -q '{{' "$f"
  done
}

@test "generate k8s app hooks: deploy uses docker build by default" {
  local hook_dir="$TEST_TEMP/hooks/api"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "api" "api" "$hook_dir" \
    "" "Dockerfile" "k8s/api/" "production" "8080" "waity-api" ""

  grep -q 'docker build' "$hook_dir/deploy.sh"
  grep -q 'MUSTER_DEPLOY_MODE:-update' "$hook_dir/deploy.sh"
}

@test "generate k8s app hooks: generated files pass bash -n" {
  local hook_dir="$TEST_TEMP/hooks/api"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "api" "api" "$hook_dir" \
    "docker-compose.yml" "Dockerfile" "k8s/api/" "production" "8080" "waity-api" ""

  for f in "$hook_dir"/*.sh; do
    bash -n "$f"
  done
}

# ── _setup_copy_hooks: k8s infra service (redis) ──

@test "generate k8s infra hooks: redis gets infra templates" {
  local hook_dir="$TEST_TEMP/hooks/redis"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "redis" "redis" "$hook_dir" \
    "" "" "k8s/redis/" "production" "6379" "waity-redis" ""

  [ -f "$hook_dir/deploy.sh" ]
  [ -x "$hook_dir/deploy.sh" ]
  # Infra deploy uses rollout restart by default (not docker build)
  grep -q 'rollout restart' "$hook_dir/deploy.sh"
  grep -q 'MUSTER_DEPLOY_MODE:-restart' "$hook_dir/deploy.sh"
  ! grep -q 'docker build' "$hook_dir/deploy.sh"
}

@test "generate k8s infra hooks: redis gets default image" {
  local hook_dir="$TEST_TEMP/hooks/redis"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "redis" "redis" "$hook_dir" \
    "" "" "k8s/redis/" "production" "6379" "waity-redis" ""

  grep -q 'redis:7-alpine' "$hook_dir/deploy.sh"
}

@test "generate k8s infra hooks: postgres gets infra templates" {
  local hook_dir="$TEST_TEMP/hooks/postgres"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "postgres" "postgres" "$hook_dir" \
    "" "" "k8s/postgres/" "production" "5432" "waity-postgres" ""

  grep -q 'rollout restart' "$hook_dir/deploy.sh"
  grep -q 'postgres:16-alpine' "$hook_dir/deploy.sh"
  ! grep -q 'docker build' "$hook_dir/deploy.sh"
}

@test "generate k8s infra hooks: all 5 files, no leftover placeholders" {
  local hook_dir="$TEST_TEMP/hooks/redis"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "redis" "redis" "$hook_dir" \
    "" "" "k8s/redis/" "production" "6379" "waity-redis" ""

  for hook in deploy.sh health.sh rollback.sh logs.sh cleanup.sh; do
    [ -f "$hook_dir/$hook" ]
    [ -x "$hook_dir/$hook" ]
  done
  for f in "$hook_dir"/*.sh; do
    ! grep -q '{{' "$f"
  done
}

@test "generate k8s infra hooks: generated files pass bash -n" {
  local hook_dir="$TEST_TEMP/hooks/redis"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "redis" "redis" "$hook_dir" \
    "" "" "k8s/redis/" "production" "6379" "waity-redis" ""

  for f in "$hook_dir"/*.sh; do
    bash -n "$f"
  done
}

# ── _setup_copy_hooks: compose stack ──

@test "generate compose hooks: creates all files with service name" {
  local hook_dir="$TEST_TEMP/hooks/web"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "compose" "web" "web" "$hook_dir" \
    "docker-compose.prod.yml" "Dockerfile" "" "" "3000" "" ""

  for hook in deploy.sh health.sh rollback.sh logs.sh cleanup.sh; do
    [ -f "$hook_dir/$hook" ]
    [ -x "$hook_dir/$hook" ]
  done
  grep -q 'web' "$hook_dir/deploy.sh"
  grep -q 'docker-compose.prod.yml' "$hook_dir/deploy.sh"
}

# ── _setup_copy_hooks: dev stack ──

@test "generate dev hooks: creates hooks for app service" {
  local hook_dir="$TEST_TEMP/hooks/api"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "dev" "api" "api" "$hook_dir" \
    "" "" "" "" "3000" "" "npm start"

  [ -f "$hook_dir/deploy.sh" ]
  [ -x "$hook_dir/deploy.sh" ]
  grep -q 'npm start' "$hook_dir/deploy.sh"
}

@test "generate dev hooks: infra service gets docker compose template" {
  local hook_dir="$TEST_TEMP/hooks/redis"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "dev" "redis" "redis" "$hook_dir" \
    "docker-compose.yml" "" "" "" "6379" "" ""

  [ -f "$hook_dir/deploy.sh" ]
  [ -x "$hook_dir/deploy.sh" ]
  # Dev infra uses docker compose, not PID management
  ! grep -q 'npm start' "$hook_dir/deploy.sh"
}

# ── _setup_copy_hooks: bare stack (stub hooks) ──

@test "generate bare hooks: creates stub hooks" {
  local hook_dir="$TEST_TEMP/hooks/myapp"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "bare" "myapp" "myapp" "$hook_dir" \
    "" "" "" "" "" "" ""

  for hook in deploy.sh health.sh rollback.sh logs.sh cleanup.sh; do
    [ -f "$hook_dir/$hook" ]
    [ -x "$hook_dir/$hook" ]
  done
}

# ── _is_infra_service ──

@test "_is_infra_service: detects known infra services" {
  _is_infra_service "redis"
  _is_infra_service "postgres"
  _is_infra_service "mongodb"
  _is_infra_service "rabbitmq"
  _is_infra_service "nginx"
}

@test "_is_infra_service: rejects app services" {
  ! _is_infra_service "api"
  ! _is_infra_service "web"
  ! _is_infra_service "worker"
  ! _is_infra_service "frontend"
}

@test "_is_infra_service: case insensitive" {
  _is_infra_service "Redis"
  _is_infra_service "POSTGRES"
  _is_infra_service "MongoDB"
}

# ── _infra_default_image ──

@test "_infra_default_image: returns correct images" {
  [ "$(_infra_default_image redis)" = "redis:7-alpine" ]
  [ "$(_infra_default_image postgres)" = "postgres:16-alpine" ]
  [ "$(_infra_default_image mongo)" = "mongo:7" ]
  [ "$(_infra_default_image nginx)" = "nginx:alpine" ]
}

@test "_infra_default_image: returns empty for app services" {
  [ "$(_infra_default_image api)" = "" ]
  [ "$(_infra_default_image web)" = "" ]
}

# ── Different k8s deploy name vs service name ──

@test "generate hooks: k8s_deploy_name differs from service name" {
  local hook_dir="$TEST_TEMP/hooks/api"
  mkdir -p "$hook_dir"
  _setup_copy_hooks "k8s" "api" "api" "$hook_dir" \
    "" "Dockerfile" "k8s/api/" "staging" "8080" "myproject-api-server" ""

  # Deploy name in hooks should be the k8s deploy name, not the service key
  grep -q 'myproject-api-server' "$hook_dir/deploy.sh"
  grep -q 'staging' "$hook_dir/deploy.sh"
}
