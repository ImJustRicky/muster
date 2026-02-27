#!/usr/bin/env bash
# muster/lib/core/scanner.sh — Project scanner

# Results (set by scan_project)
_SCAN_FILES=()       # "filename|description" entries
_SCAN_SERVICES=()    # service names detected
_SCAN_STACK=""       # k8s, compose, docker, bare
_SCAN_PATHS=()       # "service|type|relative_path" entries for template generation

# Subdirectories to check in addition to project root
_SCAN_SUBDIRS="docker deploy infra .github"

# Scan a project directory for deploy-relevant files and services
scan_project() {
  local dir="$1"
  _SCAN_FILES=()
  _SCAN_SERVICES=()
  _SCAN_STACK=""
  _SCAN_PATHS=()

  local has_k8s=false has_compose=false has_docker=false has_systemd=false

  # ── File detection ──

  # Kubernetes — check root-level k8s/ and kubernetes/, plus subdirs
  local k8s_dir=""
  if [[ -d "${dir}/k8s" ]]; then
    k8s_dir="${dir}/k8s"
  elif [[ -d "${dir}/kubernetes" ]]; then
    k8s_dir="${dir}/kubernetes"
  else
    # Check subdirectories for k8s manifests
    local _subdir
    for _subdir in $_SCAN_SUBDIRS; do
      if [[ -d "${dir}/${_subdir}/k8s" ]]; then
        k8s_dir="${dir}/${_subdir}/k8s"
        break
      elif [[ -d "${dir}/${_subdir}/kubernetes" ]]; then
        k8s_dir="${dir}/${_subdir}/kubernetes"
        break
      fi
    done
  fi

  if [[ -n "$k8s_dir" ]]; then
    has_k8s=true
    local k8s_rel="${k8s_dir#${dir}/}"
    _SCAN_FILES[${#_SCAN_FILES[@]}]="${k8s_rel}/|Kubernetes manifests"

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
        _SCAN_FILES[${#_SCAN_FILES[@]}]="${k8s_rel}/${svc_name}/|Kubernetes service"
        _SCAN_PATHS[${#_SCAN_PATHS[@]}]="${svc_name}|k8s_dir|${k8s_rel}/${svc_name}/"
      fi
    done
  fi

  # Docker Compose — check root, then subdirectories
  local compose_file="" compose_rel=""
  for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "${dir}/${f}" ]]; then
      has_compose=true
      compose_file="${dir}/${f}"
      compose_rel="$f"
      _SCAN_FILES[${#_SCAN_FILES[@]}]="${f}|Docker Compose config"
      break
    fi
  done

  # Check subdirectories for compose files if not found at root
  if [[ -z "$compose_file" ]]; then
    local _subdir
    for _subdir in $_SCAN_SUBDIRS; do
      [[ ! -d "${dir}/${_subdir}" ]] && continue
      for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        if [[ -f "${dir}/${_subdir}/${f}" ]]; then
          has_compose=true
          compose_file="${dir}/${_subdir}/${f}"
          compose_rel="${_subdir}/${f}"
          _SCAN_FILES[${#_SCAN_FILES[@]}]="${_subdir}/${f}|Docker Compose config"
          break 2
        fi
      done
    done
  fi

  # Store compose file path for template generation
  if [[ -n "$compose_file" ]]; then
    _SCAN_PATHS[${#_SCAN_PATHS[@]}]="_compose|compose_file|${compose_rel}"
  fi

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

  # Dockerfiles — check root, then subdirectories
  if [[ -f "${dir}/Dockerfile" ]]; then
    has_docker=true
    _SCAN_FILES[${#_SCAN_FILES[@]}]="Dockerfile|Docker build"
    _SCAN_PATHS[${#_SCAN_PATHS[@]}]="_default|dockerfile|Dockerfile"
  fi

  # Multi-service Dockerfiles (Dockerfile.api, Dockerfile.worker, etc.)
  for f in "${dir}"/Dockerfile.*; do
    [[ ! -f "$f" ]] && continue
    has_docker=true
    local df_name
    df_name=$(basename "$f")
    local df_svc="${df_name#Dockerfile.}"
    _SCAN_FILES[${#_SCAN_FILES[@]}]="${df_name}|Docker build (${df_svc})"
    _SCAN_PATHS[${#_SCAN_PATHS[@]}]="${df_svc}|dockerfile|${df_name}"
    # Add as service if not already known
    _scan_add_service "$df_svc"
  done

  # Check subdirectories for Dockerfiles
  local _subdir
  for _subdir in $_SCAN_SUBDIRS; do
    [[ ! -d "${dir}/${_subdir}" ]] && continue

    # Plain Dockerfile in subdir
    if [[ -f "${dir}/${_subdir}/Dockerfile" ]]; then
      has_docker=true
      _SCAN_FILES[${#_SCAN_FILES[@]}]="${_subdir}/Dockerfile|Docker build"
      _SCAN_PATHS[${#_SCAN_PATHS[@]}]="_default|dockerfile|${_subdir}/Dockerfile"
    fi

    # Multi-service Dockerfiles in subdir (docker/Dockerfile.api, etc.)
    for f in "${dir}/${_subdir}"/Dockerfile.*; do
      [[ ! -f "$f" ]] && continue
      has_docker=true
      local df_name
      df_name=$(basename "$f")
      local df_svc="${df_name#Dockerfile.}"
      _SCAN_FILES[${#_SCAN_FILES[@]}]="${_subdir}/${df_name}|Docker build (${df_svc})"
      _SCAN_PATHS[${#_SCAN_PATHS[@]}]="${df_svc}|dockerfile|${_subdir}/${df_name}"
      _scan_add_service "$df_svc"
    done
  done

  # Systemd service files (root and subdirs)
  for f in "${dir}"/*.service; do
    if [[ -f "$f" ]]; then
      has_systemd=true
      _SCAN_FILES[${#_SCAN_FILES[@]}]="$(basename "$f")|Systemd service"
    fi
  done
  local _subdir
  for _subdir in $_SCAN_SUBDIRS; do
    for f in "${dir}/${_subdir}"/*.service; do
      if [[ -f "$f" ]]; then
        has_systemd=true
        _SCAN_FILES[${#_SCAN_FILES[@]}]="${_subdir}/$(basename "$f")|Systemd service"
      fi
    done
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

  # ── Service hints via grep (root + subdirectories) ──
  local hint_files=""
  for pattern in "*.json" "*.yml" "*.yaml" "*.env" "*.env.*"; do
    hint_files="${hint_files} $(ls ${dir}/${pattern} 2>/dev/null || true)"
  done
  for _subdir in $_SCAN_SUBDIRS; do
    [[ ! -d "${dir}/${_subdir}" ]] && continue
    for pattern in "*.json" "*.yml" "*.yaml" "*.env" "*.env.*"; do
      hint_files="${hint_files} $(ls ${dir}/${_subdir}/${pattern} 2>/dev/null || true)"
    done
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

# Add a service name if not already in _SCAN_SERVICES
_scan_add_service() {
  local name="$1"
  local i=0
  while (( i < ${#_SCAN_SERVICES[@]} )); do
    [[ "${_SCAN_SERVICES[$i]}" == "$name" ]] && return 0
    i=$((i + 1))
  done
  _SCAN_SERVICES[${#_SCAN_SERVICES[@]}]="$name"
}

# Look up a path from _SCAN_PATHS by service name and type
# Usage: scan_get_path "api" "dockerfile"  -> prints the path or ""
# Prefers exact service match; falls back to _default entries
scan_get_path() {
  local svc="$1" type="$2"
  local fallback=""
  local i=0
  while (( i < ${#_SCAN_PATHS[@]} )); do
    local entry="${_SCAN_PATHS[$i]}"
    local p_svc="${entry%%|*}"
    local rest="${entry#*|}"
    local p_type="${rest%%|*}"
    local p_path="${rest#*|}"
    if [[ "$p_type" == "$type" ]]; then
      if [[ "$p_svc" == "$svc" ]]; then
        echo "$p_path"
        return 0
      fi
      if [[ "$p_svc" == "_default" && -z "$fallback" ]]; then
        fallback="$p_path"
      fi
    fi
    i=$((i + 1))
  done
  echo "$fallback"
}

# Get the compose file path from scan results
scan_get_compose_file() {
  local i=0
  while (( i < ${#_SCAN_PATHS[@]} )); do
    local entry="${_SCAN_PATHS[$i]}"
    local p_svc="${entry%%|*}"
    local rest="${entry#*|}"
    local p_type="${rest%%|*}"
    local p_path="${rest#*|}"
    if [[ "$p_type" == "compose_file" ]]; then
      echo "$p_path"
      return 0
    fi
    i=$((i + 1))
  done
  echo ""
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

  printf '%b\n' "  ${BOLD}Detected:${RESET}"

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
    printf '%b\n' "  Stack: ${ACCENT_BRIGHT}${stack_label}${RESET}"
  fi

  return 0
}
