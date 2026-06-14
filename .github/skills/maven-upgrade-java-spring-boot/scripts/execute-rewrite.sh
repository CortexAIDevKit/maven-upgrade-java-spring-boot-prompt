#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

APPLICATION_ID=""
MODULE_NAME=""
JAVA_VERSION=""
SPRING_BOOT_VERSION=""
TIMESTAMP=""
RUN_ID=""
WORKSPACE_ROOT="$(pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --application-id)
      APPLICATION_ID="${2:-}"
      shift 2
      ;;
    --module-name)
      MODULE_NAME="${2:-}"
      shift 2
      ;;
    --java-version)
      JAVA_VERSION="${2:-}"
      shift 2
      ;;
    --spring-boot-version)
      SPRING_BOOT_VERSION="${2:-}"
      shift 2
      ;;
    --timestamp)
      TIMESTAMP="${2:-}"
      shift 2
      ;;
    --run-id)
      RUN_ID="${2:-}"
      shift 2
      ;;
    --workspace-root)
      WORKSPACE_ROOT="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

MODULE_NAME="$(normalize_module_name "$MODULE_NAME")"
JAVA_VERSION="$(normalize_java_version "$JAVA_VERSION")"
SPRING_BOOT_VERSION="$(normalize_spring_boot_version "$SPRING_BOOT_VERSION")"

if [[ -z "$TIMESTAMP" ]]; then
  TIMESTAMP="$(timestamp_now)"
fi

RUN_DIR="$(run_output_dir "$WORKSPACE_ROOT" "$TIMESTAMP" "$MODULE_NAME")"
mkdir -p "$RUN_DIR"

RUN_LOG="$RUN_DIR/run.log"
EXECUTE_REWRITE_LOG="$RUN_DIR/execute-rewrite.log"
PID_FILE="$RUN_DIR/execute-rewrite.pid"
REWRITE_COPY_FILE="$RUN_DIR/rewrite.yml"
REWRITE_MAVEN_PLUGIN_VERSION="6.40.0"
WORKSPACE_REWRITE_FILE="$WORKSPACE_ROOT/rewrite.yml"

log_execute_rewrite_line() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $1" >>"$EXECUTE_REWRITE_LOG"
}

log_execute_rewrite_command() {
  local label="$1"
  shift

  log_execute_rewrite_line "$label"
  for argument in "$@"; do
    printf '  %q\n' "$argument" >>"$EXECUTE_REWRITE_LOG"
  done
}

GENERATE_REWRITE_SCRIPT="$SCRIPT_DIR/generate-rewrite-config.sh"
if [[ ! -x "$GENERATE_REWRITE_SCRIPT" ]]; then
  echo "generate rewrite script is missing or not executable: $GENERATE_REWRITE_SCRIPT" >&2
  exit 1
fi

REWRITE_FLAGS="$($GENERATE_REWRITE_SCRIPT \
  --java-version "$JAVA_VERSION" \
  --spring-boot-version "$SPRING_BOOT_VERSION" \
  --workspace-root "$WORKSPACE_ROOT")"

if [[ -z "$REWRITE_FLAGS" ]]; then
  echo "failed to generate rewrite flags" >&2
  exit 1
fi

if [[ ! -f "$WORKSPACE_REWRITE_FILE" ]]; then
  echo "generated rewrite file not found: $WORKSPACE_REWRITE_FILE" >&2
  exit 1
fi

cp "$WORKSPACE_REWRITE_FILE" "$REWRITE_COPY_FILE"

read -r -a REWRITE_FLAGS_ARRAY <<< "$REWRITE_FLAGS"

if [[ "$MODULE_NAME" == "." ]]; then
  MVN_CMD=(mvn -B -U org.openrewrite.maven:rewrite-maven-plugin:$REWRITE_MAVEN_PLUGIN_VERSION:run "${REWRITE_FLAGS_ARRAY[@]}")
else
  MVN_CMD=(mvn -B -pl "$MODULE_NAME" -am org.openrewrite.maven:rewrite-maven-plugin:$REWRITE_MAVEN_PLUGIN_VERSION:run "${REWRITE_FLAGS_ARRAY[@]}")
fi

log_execute_rewrite_line "execute-rewrite launch"
log_execute_rewrite_line "application-id=$APPLICATION_ID"
log_execute_rewrite_line "module-name=$MODULE_NAME"
log_execute_rewrite_line "java-version=$JAVA_VERSION"
log_execute_rewrite_line "spring-boot-version=$SPRING_BOOT_VERSION"
log_execute_rewrite_line "rewrite-file=$REWRITE_COPY_FILE"
log_execute_rewrite_line "rewrite-flags:"
printf '  %s\n' "$REWRITE_FLAGS" >>"$EXECUTE_REWRITE_LOG"
log_execute_rewrite_command "command:" "${MVN_CMD[@]}"

(
  set +e
  cleanup_generated_rewrite() {
    rm -f "$WORKSPACE_REWRITE_FILE"
  }
  trap cleanup_generated_rewrite EXIT

  cd "$WORKSPACE_ROOT" || exit 1
  "${MVN_CMD[@]}" >>"$EXECUTE_REWRITE_LOG" 2>&1
  rewrite_exit_code=$?

  if [[ -f "$RUN_LOG" ]]; then
    if [[ $rewrite_exit_code -eq 0 ]]; then
      update_run_log_stage "$RUN_LOG" "execute-rewrite" "SUCCESS" "COMPLETED" || true
    else
      update_run_log_stage "$RUN_LOG" "execute-rewrite" "FAILED" "FAILED" || true
    fi
  fi

  log_execute_rewrite_line "execute-rewrite finished with code=$rewrite_exit_code"
) &

bg_pid=$!
echo "$bg_pid" >"$PID_FILE"
log_execute_rewrite_line "execute-rewrite started in background pid=$bg_pid"