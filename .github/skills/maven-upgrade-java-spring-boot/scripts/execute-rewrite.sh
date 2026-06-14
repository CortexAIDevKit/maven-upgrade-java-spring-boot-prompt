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
REWRITE_MAVEN_PLUGIN_VERSION="6.40.0"

if [[ "$MODULE_NAME" == "." ]]; then
  MVN_CMD=(mvn -U org.openrewrite.maven:rewrite-maven-plugin:$REWRITE_MAVEN_PLUGIN_VERSION:run)
else
  MVN_CMD=(mvn -pl "$MODULE_NAME" -am org.openrewrite.maven:rewrite-maven-plugin:$REWRITE_MAVEN_PLUGIN_VERSION:run)
fi

{
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] execute-rewrite launch"
  echo "application-id=$APPLICATION_ID module-name=$MODULE_NAME java-version=$JAVA_VERSION spring-boot-version=$SPRING_BOOT_VERSION"
  printf "command="
  printf '%q ' "${MVN_CMD[@]}"
  echo
} >>"$EXECUTE_REWRITE_LOG"

(
  set +e
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

  echo "[$(date +"%Y-%m-%d %H:%M:%S")] execute-rewrite finished with code=$rewrite_exit_code" >>"$EXECUTE_REWRITE_LOG"
) &

bg_pid=$!
echo "$bg_pid" >"$PID_FILE"
echo "[$(date +"%Y-%m-%d %H:%M:%S")] execute-rewrite started in background pid=$bg_pid" >>"$EXECUTE_REWRITE_LOG"