#!/usr/bin/env bash
# muster/lib/core/scanner.sh — Project scanner

# Results (set by scan_project)
_SCAN_FILES=()       # "filename|description" entries
_SCAN_SERVICES=()    # service names detected
_SCAN_STACK=""       # k8s, compose, docker, bare

# Scan a project directory for deploy-relevant files and services
scan_project() {
  local dir="$1"
  _SCAN_FILES=()
  _SCAN_SERVICES=()
  _SCAN_STACK=""

  local has_k8s=false has_compose=false has_docker=false has_systemd=false

  # ── File detection ──

  # Kubernetes
  if [[ -d "${dir}/k8s" || -d "${dir}/kubernetes" ]]; then
    has_k8s=true
    local k8s_dir="${dir}/k8s"
    [[ -d "${dir}/kubernetes" ]] && k8s_dir="${dir}/kubernetes"
    _SCAN_FILES[${#_SCAN_FILES[@]}]="$(basename "$k8s_dir")/|Kubernetes manifests"

    # Detect services from k8s subdirectories
    for sub in "${k8s_dir}"/*/; do
      [[ ! -d "$sub" ]] && continue
      local svc_name
      svc_name=$(basename "$sub")
      # Only count as service if it has a deployment or service yaml
      local _svc_files
      _svc_files=$(ls "${sub}"*.yaml "${sub}"*.yml 2>/dev/null || true)
      if echo "$_svc_files" | grep -qiE 'deploy|service' 2>/dev/null; then
        _SCAN_SERVICES[${#_SCAN_SERVICES[@]}]="$svc_name"
        _SCAN_FILES[${#_SCAN_FILES[@]}]="$(basename "$k8s_dir")/${svc_name}/|Kubernetes service"
      fi
    done
  fi

  # Docker Compose
  local compose_file=""
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${dir}/${f}" ]]; then
      has_compose=true
      compose_file="${dir}/${f}"
      _SCAN_FILES[${#_SCAN_FILES[@]}]="${f}|Docker Compose config"
      break
    fi
  done

  # Parse compose services
  if [[ -n "$compose_file" ]]; then
    local in_services=false
    while IFS= read -r line; do
      if [[ "$line" =~ ^services: ]]; then
        in_services=true
        continue
      fi
      if [[ "$in_services" == "true" ]]; then
        # Top-level key under services (2-space indent, no further indent)
        if [[ "$line" =~ ^[[:space:]][[:space:]][a-zA-Z_-]+: && ! "$line" =~ ^[[:space:]][[:space:]][[:space:]] ]]; then
          local svc
          svc=$(printf '%s' "$line" | sed 's/^[[:space:]]*//' | sed 's/:.*//')
          # Don't duplicate if already found via k8s
          local already=false
          local si=0
          while (( si < ${#_SCAN_SERVICES[@]} )); do
            [[ "${_SCAN_SERVICES[$si]}" == "$svc" ]] && already=true
            si=$((si + 1))
          done
          [[ "$already" == "false" ]] && _SCAN_SERVICES[${#_SCAN_SERVICES[@]}]="$svc"
        fi
        # Stop if we hit another top-level key
        if [[ "$line" =~ ^[a-zA-Z] && ! "$line" =~ ^services ]]; then
          in_services=false
        fi
      fi
    done < "$compose_file"
  fi

  # Dockerfile
  if [[ -f "${dir}/Dockerfile" ]]; then
    has_docker=true
    _SCAN_FILES[${#_SCAN_FILES[@]}]="Dockerfile|Docker build"
  fi

  # Systemd service files
  for f in "${dir}"/*.service; do
    if [[ -f "$f" ]]; then
      has_systemd=true
      _SCAN_FILES[${#_SCAN_FILES[@]}]="$(basename "$f")|Systemd service"
    fi
  done

  # Language / framework files
  [[ -f "${dir}/package.json" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="package.json|Node.js project"
  [[ -f "${dir}/go.mod" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="go.mod|Go project"
  [[ -f "${dir}/Cargo.toml" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="Cargo.toml|Rust project"
  [[ -f "${dir}/requirements.txt" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="requirements.txt|Python project"
  [[ -f "${dir}/pyproject.toml" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="pyproject.toml|Python project"
  [[ -f "${dir}/Gemfile" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="Gemfile|Ruby project"
  [[ -f "${dir}/pom.xml" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="pom.xml|Java project"
  [[ -f "${dir}/Makefile" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="Makefile|Build system"
  [[ -f "${dir}/nginx.conf" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="nginx.conf|Nginx config"
  [[ -f "${dir}/Procfile" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="Procfile|Process manager"
  [[ -f "${dir}/Capfile" ]] && _SCAN_FILES[${#_SCAN_FILES[@]}]="Capfile|Capistrano deploy"

  # ── Service hints via grep ──
  local hint_files=""
  for pattern in "*.json" "*.yml" "*.yaml" "*.env" "*.env.*"; do
    hint_files="${hint_files} $(ls ${dir}/${pattern} 2>/dev/null || true)"
  done

  if [[ -n "$hint_files" ]]; then
    _scan_hint "$hint_files" "redis" "redis"
    _scan_hint "$hint_files" "postgres|postgresql" "postgres"
    _scan_hint "$hint_files" "mysql|mariadb" "mysql"
    _scan_hint "$hint_files" "mongo|mongodb" "mongo"
    _scan_hint "$hint_files" "meilisearch" "meilisearch"
    _scan_hint "$hint_files" "minio" "minio"
    _scan_hint "$hint_files" "nginx" "nginx"
    _scan_hint "$hint_files" "rabbitmq" "rabbitmq"
    _scan_hint "$hint_files" "kafka" "kafka"
    _scan_hint "$hint_files" "elasticsearch|opensearch" "elasticsearch"
  fi

  # ── Determine stack ──
  if [[ "$has_k8s" == "true" ]]; then
    _SCAN_STACK="k8s"
  elif [[ "$has_compose" == "true" ]]; then
    _SCAN_STACK="compose"
  elif [[ "$has_docker" == "true" ]]; then
    _SCAN_STACK="docker"
  elif [[ "$has_systemd" == "true" ]]; then
    _SCAN_STACK="bare"
  else
    _SCAN_STACK=""
  fi
}

# Check if a service hint is found in files and not already in _SCAN_SERVICES
_scan_hint() {
  local files="$1" pattern="$2" name="$3"

  # Already detected?
  local i=0
  while (( i < ${#_SCAN_SERVICES[@]} )); do
    [[ "${_SCAN_SERVICES[$i]}" == "$name" ]] && return 0
    i=$((i + 1))
  done

  # Grep for pattern
  if grep -qilE "$pattern" $files 2>/dev/null; then
    _SCAN_SERVICES[${#_SCAN_SERVICES[@]}]="$name"
  fi
}

# Pretty-print scan results
scan_print_results() {
  if (( ${#_SCAN_FILES[@]} == 0 )); then
    info "No project files detected"
    return 1
  fi

  echo -e "  ${BOLD}Detected:${RESET}"

  local i=0
  while (( i < ${#_SCAN_FILES[@]} )); do
    local entry="${_SCAN_FILES[$i]}"
    local file="${entry%%|*}"
    local desc="${entry#*|}"
    printf '    %-28s %b%s%b\n' "$file" "${DIM}" "$desc" "${RESET}"
    i=$((i + 1))
  done

  if [[ -n "$_SCAN_STACK" ]]; then
    echo ""
    local stack_label=""
    case "$_SCAN_STACK" in
      k8s)     stack_label="Kubernetes" ;;
      compose) stack_label="Docker Compose" ;;
      docker)  stack_label="Docker" ;;
      bare)    stack_label="Bare metal / Systemd" ;;
    esac
    echo -e "  Stack: ${ACCENT_BRIGHT}${stack_label}${RESET}"
  fi

  return 0
}
