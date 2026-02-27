#!/usr/bin/env bash
# muster/lib/core/scanner.sh — Project scanner

# Results (set by scan_project)
_SCAN_FILES=()       # "filename|description" entries
_SCAN_SERVICES=()    # service names detected
_SCAN_STACK=""       # k8s, compose, docker, bare
_SCAN_PATHS=()       # "service|type|relative_path" entries for template generation
_SCAN_HEALTH=()      # "service|type|endpoint|port" entries from live k8s
_SCAN_K8S_NAMES=()   # "stripped_name|original_deploy_name" entries
_SCAN_K8S_NS=""      # resolved namespace
_SCAN_K8S_PREFIX=""   # common deployment name prefix

# Subdirectories to check in addition to project root
_SCAN_SUBDIRS="docker deploy infra .github"

# Exclude patterns — external callers can set this before calling scan_project()
# Space-separated list of directory/file prefixes to skip
: "${_SCAN_EXCLUDES:=}"

# Prepend global scanner_exclude patterns from ~/.muster/settings.json
_scan_load_global_excludes() {
  local global_excludes=""
  if [[ -f "$HOME/.muster/settings.json" ]]; then
    if command -v jq &>/dev/null; then
      global_excludes=$(jq -r '.scanner_exclude // [] | .[]' "$HOME/.muster/settings.json" 2>/dev/null)
    elif command -v python3 &>/dev/null; then
      global_excludes=$(python3 -c "
import json
with open('$HOME/.muster/settings.json') as f:
    for p in json.load(f).get('scanner_exclude', []):
        print(p)
" 2>/dev/null)
    fi
  fi
  if [[ -n "$global_excludes" ]]; then
    local _line
    while IFS= read -r _line; do
      [[ -z "$_line" ]] && continue
      if [[ -n "$_SCAN_EXCLUDES" ]]; then
        _SCAN_EXCLUDES="$_line $_SCAN_EXCLUDES"
      else
        _SCAN_EXCLUDES="$_line"
      fi
    done <<< "$global_excludes"
  fi
}
_scan_load_global_excludes

# Auto-exclude directory names (exact matches only)
_SCAN_AUTO_EXCLUDES="archived deprecated old backup"

# Check if a path should be excluded based on _SCAN_EXCLUDES, .musterignore, and auto-excludes
# Usage: _scan_is_excluded "/abs/project/dir" "relative/path"
_scan_is_excluded() {
  local dir="$1" rel_path="$2"

  # Check auto-excludes: skip directories whose basename is in the auto-exclude list
  local _ae
  for _ae in $_SCAN_AUTO_EXCLUDES; do
    case "$rel_path" in
      "${_ae}"|"${_ae}/"*) return 0 ;;
      */"${_ae}"|*/"${_ae}/"*) return 0 ;;
    esac
  done

  # Check _SCAN_EXCLUDES
  local _ex
  for _ex in $_SCAN_EXCLUDES; do
    [[ -z "$_ex" ]] && continue
    case "$rel_path" in
      "${_ex}"|"${_ex}/"*) return 0 ;;
      */"${_ex}"|*/"${_ex}/"*) return 0 ;;
    esac
  done

  # Check .musterignore
  if [[ -f "${dir}/.musterignore" ]]; then
    local _line
    while IFS= read -r _line; do
      # Skip comments and empty lines
      case "$_line" in
        "#"*|"") continue ;;
      esac
      # Trim leading/trailing whitespace
      _line=$(printf '%s' "$_line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$_line" ]] && continue
      case "$rel_path" in
        "${_line}"|"${_line}/"*) return 0 ;;
        */"${_line}"|*/"${_line}/"*) return 0 ;;
      esac
    done < "${dir}/.musterignore"
  fi

  return 1
}

# Scan a project directory for deploy-relevant files and services
scan_project() {
  local dir="$1"
  _SCAN_FILES=()
  _SCAN_SERVICES=()
  _SCAN_STACK=""
  _SCAN_PATHS=()
  _SCAN_HEALTH=()
  _SCAN_K8S_NAMES=()
  _SCAN_K8S_NS=""
  _SCAN_K8S_PREFIX=""

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
      _scan_is_excluded "$dir" "$_subdir" && continue
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
      # Skip excluded directories
      _scan_is_excluded "$dir" "${k8s_rel}/${svc_name}" && continue
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
      _scan_is_excluded "$dir" "$_subdir" && continue
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
    _scan_is_excluded "$dir" "$_subdir" && continue

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
    _scan_is_excluded "$dir" "$_subdir" && continue
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
    _scan_is_excluded "$dir" "$_subdir" && continue
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

  # Grep for pattern (-w = whole word matching to avoid false positives)
  if grep -qwilE "$pattern" $files 2>/dev/null; then
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

# ══════════════════════════════════════════════════════════════
# Live Kubernetes cluster introspection
# ══════════════════════════════════════════════════════════════

# Resolve namespace via: flag → k8s YAML → kubectl config → "default"
# Usage: _scan_resolve_namespace "flag_ns" "project_dir"
_scan_resolve_namespace() {
  local flag_ns="$1" project_dir="$2"

  # Priority 1: explicit flag
  if [[ -n "$flag_ns" ]]; then
    echo "$flag_ns"
    return 0
  fi

  # Priority 2: grep namespace: from k8s YAML files
  if [[ -n "$project_dir" ]]; then
    local yaml_ns=""
    local yaml_files=""
    # Collect k8s YAML files from common locations
    local _search_dirs="k8s kubernetes deploy infra"
    local _sd
    for _sd in $_search_dirs; do
      if [[ -d "${project_dir}/${_sd}" ]]; then
        yaml_files="${yaml_files} $(ls "${project_dir}/${_sd}"/*.yaml "${project_dir}/${_sd}"/*.yml 2>/dev/null || true)"
        # Also check subdirs
        local _sub
        for _sub in "${project_dir}/${_sd}"/*/; do
          [[ -d "$_sub" ]] && yaml_files="${yaml_files} $(ls "${_sub}"*.yaml "${_sub}"*.yml 2>/dev/null || true)"
        done
      fi
    done
    # Also check root-level YAML
    yaml_files="${yaml_files} $(ls "${project_dir}"/*.yaml "${project_dir}"/*.yml 2>/dev/null || true)"

    if [[ -n "$yaml_files" ]]; then
      # Match: namespace: value or namespace: "value" or namespace: 'value'
      # Skip template placeholders like {{ .Release.Namespace }}
      yaml_ns=$(grep -h 'namespace:' $yaml_files 2>/dev/null \
        | grep -v '{{' \
        | head -1 \
        | sed 's/.*namespace:[[:space:]]*//' \
        | sed 's/^["'"'"']//' \
        | sed 's/["'"'"']$//' \
        | sed 's/[[:space:]]*$//' \
        || true)
      if [[ -n "$yaml_ns" ]]; then
        echo "$yaml_ns"
        return 0
      fi
    fi
  fi

  # Priority 3: kubectl config current namespace
  if [[ "${MUSTER_HAS_KUBECTL:-}" == "true" ]]; then
    local config_ns=""
    config_ns=$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null || true)
    if [[ -n "$config_ns" ]]; then
      echo "$config_ns"
      return 0
    fi
  fi

  # Priority 4: default
  echo "default"
}

# Strip common deployment name prefix
# Usage: _scan_strip_prefix "deployment_name"
_scan_strip_prefix() {
  local name="$1"
  if [[ -n "$_SCAN_K8S_PREFIX" && "$name" == "${_SCAN_K8S_PREFIX}-"* ]]; then
    echo "${name#${_SCAN_K8S_PREFIX}-}"
  else
    echo "$name"
  fi
}

# Core k8s cluster scan: read deployments, extract services and health probes
# Usage: scan_k8s_cluster "namespace"
scan_k8s_cluster() {
  local ns="${1:-default}"
  _SCAN_K8S_NS="$ns"

  # Guard: kubectl not available
  if [[ "${MUSTER_HAS_KUBECTL:-}" != "true" ]]; then
    return 0
  fi

  # Guard: cluster not reachable
  if ! kubectl cluster-info &>/dev/null; then
    warn "kubectl available but cluster not reachable — skipping live scan"
    return 0
  fi

  # Fetch deployments JSON
  local deploy_json=""
  deploy_json=$(kubectl get deployments -n "$ns" -o json 2>/dev/null) || {
    warn "Failed to list deployments in namespace '$ns'"
    return 0
  }

  # Parse deployment names — prefer jq, fall back to python3
  local dep_names=""
  if has_cmd jq; then
    dep_names=$(echo "$deploy_json" | jq -r '.items[].metadata.name' 2>/dev/null)
  elif has_cmd python3; then
    dep_names=$(echo "$deploy_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for item in data.get('items', []):
    print(item['metadata']['name'])
" 2>/dev/null)
  else
    warn "Neither jq nor python3 available — cannot parse k8s deployments"
    return 0
  fi

  if [[ -z "$dep_names" ]]; then
    return 0
  fi

  # ── Compute common prefix ──
  # Find longest "X-" prefix shared by ALL deployment names (only if >1)
  local dep_count=0
  local dep_arr=()
  local _dn
  while IFS= read -r _dn; do
    [[ -z "$_dn" ]] && continue
    dep_arr[${#dep_arr[@]}]="$_dn"
    dep_count=$((dep_count + 1))
  done <<< "$dep_names"

  _SCAN_K8S_PREFIX=""
  if (( dep_count > 1 )); then
    # Start with the first name's prefix (everything before first -)
    local first_name="${dep_arr[0]}"
    local candidate=""
    case "$first_name" in
      *-*) candidate="${first_name%%-*}" ;;
    esac

    if [[ -n "$candidate" ]]; then
      # Check if ALL names start with candidate-
      local all_match=true
      local _di=0
      while (( _di < dep_count )); do
        case "${dep_arr[$_di]}" in
          "${candidate}-"*) ;;
          *) all_match=false; break ;;
        esac
        _di=$((_di + 1))
      done
      if [[ "$all_match" == "true" ]]; then
        _SCAN_K8S_PREFIX="$candidate"
      fi
    fi
  fi

  # ── Process each deployment ──
  # Use jq for full extraction if available, otherwise python3
  if has_cmd jq; then
    local _idx=0
    while (( _idx < dep_count )); do
      local dep_name="${dep_arr[$_idx]}"
      local svc_name
      svc_name=$(_scan_strip_prefix "$dep_name")
      _scan_add_service "$svc_name"

      # Map stripped name to original k8s deployment name
      _SCAN_K8S_NAMES[${#_SCAN_K8S_NAMES[@]}]="${svc_name}|${dep_name}"

      # Extract container port and probes via jq
      local container_json=""
      container_json=$(echo "$deploy_json" | jq -r \
        --arg name "$dep_name" \
        '.items[] | select(.metadata.name == $name) | .spec.template.spec.containers[0]' 2>/dev/null)

      local container_port=""
      container_port=$(echo "$container_json" | jq -r '.ports[0].containerPort // empty' 2>/dev/null)

      # Check readinessProbe first, then livenessProbe
      local probe_json=""
      local probe_source=""
      local has_readiness=""
      has_readiness=$(echo "$container_json" | jq -r '.readinessProbe // empty' 2>/dev/null)
      if [[ -n "$has_readiness" ]]; then
        probe_json=$(echo "$container_json" | jq -r '.readinessProbe' 2>/dev/null)
        probe_source="readiness"
      else
        local has_liveness=""
        has_liveness=$(echo "$container_json" | jq -r '.livenessProbe // empty' 2>/dev/null)
        if [[ -n "$has_liveness" ]]; then
          probe_json=$(echo "$container_json" | jq -r '.livenessProbe' 2>/dev/null)
          probe_source="liveness"
        fi
      fi

      if [[ -n "$probe_json" && "$probe_json" != "null" ]]; then
        # httpGet probe
        local http_path=""
        http_path=$(echo "$probe_json" | jq -r '.httpGet.path // empty' 2>/dev/null)
        if [[ -n "$http_path" ]]; then
          local http_port=""
          http_port=$(echo "$probe_json" | jq -r '.httpGet.port // empty' 2>/dev/null)
          [[ -z "$http_port" ]] && http_port="$container_port"
          _SCAN_HEALTH[${#_SCAN_HEALTH[@]}]="${svc_name}|http|${http_path}|${http_port}"
        else
          # tcpSocket probe
          local tcp_port=""
          tcp_port=$(echo "$probe_json" | jq -r '.tcpSocket.port // empty' 2>/dev/null)
          if [[ -n "$tcp_port" ]]; then
            _SCAN_HEALTH[${#_SCAN_HEALTH[@]}]="${svc_name}|tcp||${tcp_port}"
          else
            # exec probe
            local exec_cmd=""
            exec_cmd=$(echo "$probe_json" | jq -r '(.exec.command // []) | join(" ")' 2>/dev/null)
            if [[ -n "$exec_cmd" ]]; then
              _SCAN_HEALTH[${#_SCAN_HEALTH[@]}]="${svc_name}|command|${exec_cmd}|"
            fi
          fi
        fi
      elif [[ -n "$container_port" ]]; then
        # No probe but has a port — default to tcp
        _SCAN_HEALTH[${#_SCAN_HEALTH[@]}]="${svc_name}|tcp||${container_port}"
      fi
      # Neither probe nor port: skip (no health entry)

      _idx=$((_idx + 1))
    done
  elif has_cmd python3; then
    # Full processing via python3 fallback
    local health_lines=""
    health_lines=$(echo "$deploy_json" | python3 -c "
import json, sys

data = json.load(sys.stdin)
prefix = sys.argv[1] if len(sys.argv) > 1 else ''

for item in data.get('items', []):
    dep_name = item['metadata']['name']
    # Strip prefix
    if prefix and dep_name.startswith(prefix + '-'):
        svc_name = dep_name[len(prefix)+1:]
    else:
        svc_name = dep_name

    # Always output name mapping
    print('NAME|' + svc_name + '|' + dep_name)

    containers = item.get('spec', {}).get('template', {}).get('spec', {}).get('containers', [])
    if not containers:
        print('SVC|' + svc_name)
        continue

    c = containers[0]
    ports = c.get('ports', [])
    container_port = str(ports[0].get('containerPort', '')) if ports else ''

    # Check readinessProbe first, then livenessProbe
    probe = c.get('readinessProbe') or c.get('livenessProbe')

    if probe:
        http_get = probe.get('httpGet')
        tcp_socket = probe.get('tcpSocket')
        exec_probe = probe.get('exec')

        if http_get:
            path = http_get.get('path', '/')
            port = str(http_get.get('port', container_port))
            print('HEALTH|' + svc_name + '|http|' + path + '|' + port)
        elif tcp_socket:
            port = str(tcp_socket.get('port', ''))
            print('HEALTH|' + svc_name + '|tcp||' + port)
        elif exec_probe:
            cmd = ' '.join(exec_probe.get('command', []))
            print('HEALTH|' + svc_name + '|command|' + cmd + '|')
        else:
            if container_port:
                print('HEALTH|' + svc_name + '|tcp||' + container_port)
            else:
                print('SVC|' + svc_name)
    elif container_port:
        print('HEALTH|' + svc_name + '|tcp||' + container_port)
    else:
        print('SVC|' + svc_name)
" "$_SCAN_K8S_PREFIX" 2>/dev/null)

    local _line
    while IFS= read -r _line; do
      [[ -z "$_line" ]] && continue
      case "$_line" in
        NAME\|*)
          local name_rest="${_line#NAME|}"
          local n_svc="${name_rest%%|*}"
          local n_orig="${name_rest#*|}"
          _SCAN_K8S_NAMES[${#_SCAN_K8S_NAMES[@]}]="${n_svc}|${n_orig}"
          ;;
        HEALTH\|*)
          local rest="${_line#HEALTH|}"
          local h_svc="${rest%%|*}"
          local h_rest="${rest#*|}"
          _scan_add_service "$h_svc"
          _SCAN_HEALTH[${#_SCAN_HEALTH[@]}]="${h_svc}|${h_rest}"
          ;;
        SVC\|*)
          local svc_name="${_line#SVC|}"
          _scan_add_service "$svc_name"
          ;;
      esac
    done <<< "$health_lines"
  fi
}

# Look up health info for a service from _SCAN_HEALTH
# Returns "type|endpoint|port" or empty string
# Usage: scan_get_health "api"
scan_get_health() {
  local svc="$1"
  local i=0
  while (( i < ${#_SCAN_HEALTH[@]} )); do
    local entry="${_SCAN_HEALTH[$i]}"
    local h_svc="${entry%%|*}"
    if [[ "$h_svc" == "$svc" ]]; then
      echo "${entry#*|}"
      return 0
    fi
    i=$((i + 1))
  done
  echo ""
}

# Look up original k8s deployment name for a service
# Returns original name or the input if not found
# Usage: scan_get_k8s_name "api"  →  "waity-api"
scan_get_k8s_name() {
  local svc="$1"
  local i=0
  while (( i < ${#_SCAN_K8S_NAMES[@]} )); do
    local entry="${_SCAN_K8S_NAMES[$i]}"
    local n_svc="${entry%%|*}"
    if [[ "$n_svc" == "$svc" ]]; then
      echo "${entry#*|}"
      return 0
    fi
    i=$((i + 1))
  done
  echo "$svc"
}
