#!/usr/bin/env bash

set -euo pipefail

timestamp_now() {
  date +"%Y%m%d-%H%M%S"
}

normalize_module_name() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    echo "."
  else
    echo "$value"
  fi
}

normalize_java_version() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    echo "25"
  else
    echo "$value"
  fi
}

normalize_spring_boot_version() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    echo "4.0"
    return
  fi

  if [[ "$value" == "4" ]]; then
    echo "4.0"
    return
  fi

  echo "$value"
}

generate_run_id() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen
  else
    echo "run-$(timestamp_now)-$$"
  fi
}

json_escape() {
  echo "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

run_output_dir() {
  local workspace_root="$1"
  local timestamp="$2"
  local module_name="$3"
  local module_segment
  module_segment="$(artifact_module_segment "$module_name")"
  echo "$workspace_root/maven-upgrade-java-spring-boot/$timestamp/$module_segment"
}

artifact_module_segment() {
  local module_name="$1"
  if [[ "$module_name" == "." ]]; then
    echo "root"
  else
    echo "$module_name"
  fi
}

write_run_log() {
  local run_log_file="$1"
  local run_id="$2"
  local timestamp="$3"
  local overall_status="$4"
  local orchestrator_status="$5"
  local preflight_status="$6"
  local execute_rewrite_status="$7"
  local orchestrator_log="$8"
  local preflight_log="$9"
  local execute_rewrite_log="${10}"

  local tmp_file
  tmp_file="$(mktemp)"

  cat >"$tmp_file" <<EOF
{
  "runId": "$(json_escape "$run_id")",
  "timestamp": "$(json_escape "$timestamp")",
  "overallStatus": "$(json_escape "$overall_status")",
  "status": {
    "orchestrator": "$(json_escape "$orchestrator_status")",
    "preflight": "$(json_escape "$preflight_status")",
    "execute-rewrite": "$(json_escape "$execute_rewrite_status")"
  },
  "log": {
    "orchestrator": "$(json_escape "$orchestrator_log")",
    "preflight": "$(json_escape "$preflight_log")",
    "execute-rewrite": "$(json_escape "$execute_rewrite_log")"
  }
}
EOF

  mv "$tmp_file" "$run_log_file"
}

extract_json_value() {
  local key="$1"
  local file="$2"

  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi

  awk -v key="$key" '
    $0 ~ "\\\"" key "\\\"" {
      match($0, /: "[^"]*"/)
      if (RSTART > 0) {
        value = substr($0, RSTART + 3, RLENGTH - 4)
        print value
        exit
      }
    }
  ' "$file"
}

extract_status_value() {
  local key="$1"
  local file="$2"

  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi

  awk -v key="$key" '
    /"status"[[:space:]]*:[[:space:]]*\{/ { in_status = 1; next }
    in_status && /\}/ { in_status = 0 }
    in_status && $0 ~ "\\\"" key "\\\"" {
      match($0, /: "[^"]*"/)
      if (RSTART > 0) {
        value = substr($0, RSTART + 3, RLENGTH - 4)
        print value
        exit
      }
    }
  ' "$file"
}

extract_log_value() {
  local key="$1"
  local file="$2"

  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi

  awk -v key="$key" '
    /"log"[[:space:]]*:[[:space:]]*\{/ { in_log = 1; next }
    in_log && /\}/ { in_log = 0 }
    in_log && $0 ~ "\\\"" key "\\\"" {
      match($0, /: "[^"]*"/)
      if (RSTART > 0) {
        value = substr($0, RSTART + 3, RLENGTH - 4)
        print value
        exit
      }
    }
  ' "$file"
}

update_run_log_stage() {
  local run_log_file="$1"
  local stage_key="$2"
  local stage_status="$3"
  local overall_status="$4"

  local run_id timestamp current_orchestrator current_preflight current_execute
  local orchestrator_log preflight_log execute_rewrite_log

  run_id="$(extract_json_value "runId" "$run_log_file")"
  timestamp="$(extract_json_value "timestamp" "$run_log_file")"
  current_orchestrator="$(extract_status_value "orchestrator" "$run_log_file")"
  current_preflight="$(extract_status_value "preflight" "$run_log_file")"
  current_execute="$(extract_status_value "execute-rewrite" "$run_log_file")"
  orchestrator_log="$(extract_log_value "orchestrator" "$run_log_file")"
  preflight_log="$(extract_log_value "preflight" "$run_log_file")"
  execute_rewrite_log="$(extract_log_value "execute-rewrite" "$run_log_file")"

  case "$stage_key" in
    orchestrator)
      current_orchestrator="$stage_status"
      ;;
    preflight)
      current_preflight="$stage_status"
      ;;
    execute-rewrite)
      current_execute="$stage_status"
      ;;
    *)
      echo "Unsupported stage key: $stage_key" >&2
      return 1
      ;;
  esac

  write_run_log \
    "$run_log_file" \
    "$run_id" \
    "$timestamp" \
    "$overall_status" \
    "$current_orchestrator" \
    "$current_preflight" \
    "$current_execute" \
    "$orchestrator_log" \
    "$preflight_log" \
    "$execute_rewrite_log"
}