#!/usr/bin/env bats
load test_helper

# _jq_quote tests
@test "_jq_quote: no hyphens passes through" {
  result=$(_jq_quote ".services.api.name")
  [ "$result" = ".services.api.name" ]
}

@test "_jq_quote: hyphenated key gets bracket notation" {
  result=$(_jq_quote ".services.my-worker.name")
  [ "$result" = '.services["my-worker"].name' ]
}

@test "_jq_quote: multiple hyphens" {
  result=$(_jq_quote ".services.my-cool-svc.health.enabled")
  [ "$result" = '.services["my-cool-svc"].health.enabled' ]
}

# config_get tests
@test "config_get: reads string value" {
  create_test_config
  result=$(config_get ".project")
  [ "$result" = "test-project" ]
}

@test "config_get: reads nested value" {
  create_test_config
  result=$(config_get ".services.api.name")
  [ "$result" = "API Server" ]
}

@test "config_get: reads hyphenated service key" {
  create_test_config
  result=$(config_get ".services.my-worker.name")
  [ "$result" = "My Worker" ]
}

@test "config_get: reads numeric value" {
  create_test_config
  result=$(config_get ".services.api.health.port")
  [ "$result" = "8080" ]
}

@test "config_get: reads boolean" {
  create_test_config
  result=$(config_get ".services.api.skip_deploy")
  [ "$result" = "false" ]
}

# config_services tests
@test "config_services: lists all service keys" {
  create_test_config
  result=$(config_services)
  echo "$result" | grep -q "api"
  echo "$result" | grep -q "redis"
  echo "$result" | grep -q "my-worker"
}

# k8s_env_for_service tests
@test "k8s_env_for_service: exports deployment and namespace" {
  create_test_config
  result=$(k8s_env_for_service "api")
  echo "$result" | grep -q "MUSTER_K8S_DEPLOYMENT=test-api"
  echo "$result" | grep -q "MUSTER_K8S_NAMESPACE=production"
  echo "$result" | grep -q "MUSTER_K8S_SERVICE=api"
}

@test "k8s_env_for_service: exports deploy_timeout when set" {
  create_test_config
  result=$(k8s_env_for_service "api")
  echo "$result" | grep -q "MUSTER_DEPLOY_TIMEOUT=300"
}

@test "k8s_env_for_service: exports deploy_mode when set" {
  create_test_config
  result=$(k8s_env_for_service "api")
  echo "$result" | grep -q "MUSTER_DEPLOY_MODE=update"
}

@test "k8s_env_for_service: skips when no k8s config" {
  create_test_config
  result=$(k8s_env_for_service "my-worker")
  [ -z "$result" ]
}

@test "k8s_env_for_service: omits timeout when not set" {
  create_test_config
  result=$(k8s_env_for_service "redis")
  ! echo "$result" | grep -q "MUSTER_DEPLOY_TIMEOUT"
}
