#!/usr/bin/env bats
load test_helper

setup() {
  TEST_TEMP="$(mktemp -d)"
  source "$MUSTER_ROOT/lib/core/scanner.sh"
}

@test "k8s templates: deploy.sh exists and has correct placeholders" {
  local template="$MUSTER_ROOT/templates/hooks/k8s/deploy.sh"
  [ -f "$template" ]
  grep -q '{{SERVICE_NAME}}' "$template"
  grep -q '{{NAMESPACE}}' "$template"
  grep -q 'MUSTER_DEPLOY_MODE' "$template"
  grep -q 'MUSTER_DEPLOY_TIMEOUT' "$template"
}

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

@test "k8s infra deploy: uses rollout restart by default" {
  local template="$MUSTER_ROOT/templates/hooks/k8s/infra/deploy.sh"
  grep -q 'rollout restart' "$template"
  grep -q 'MUSTER_DEPLOY_MODE:-restart' "$template"
}

@test "k8s app deploy: uses build by default" {
  local template="$MUSTER_ROOT/templates/hooks/k8s/deploy.sh"
  grep -q 'docker build' "$template"
  grep -q 'MUSTER_DEPLOY_MODE:-update' "$template"
}

@test "sed substitution: replaces all placeholders" {
  local template="$MUSTER_ROOT/templates/hooks/k8s/deploy.sh"
  local output="$TEST_TEMP/deploy.sh"
  sed \
    -e 's|{{SERVICE_NAME}}|myapi|g' \
    -e 's|{{NAMESPACE}}|prod|g' \
    -e 's|{{K8S_DEPLOY_NAME}}|my-deploy|g' \
    -e 's|{{DOCKERFILE}}|Dockerfile|g' \
    -e 's|{{K8S_DIR}}|k8s/|g' \
    "$template" > "$output"
  ! grep -q '{{' "$output"
  grep -q 'myapi' "$output"
  grep -q 'prod' "$output"
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
