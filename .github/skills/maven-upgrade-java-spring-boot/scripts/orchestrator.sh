#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

APPLICATION_ID=""
MODULE_NAME=""
JAVA_VERSION=""
SPRING_BOOT_VERSION=""
TIMESTAMP=""
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

if [[ -z "$APPLICATION_ID" ]]; then
  echo "application-id is required" >&2
  exit 1
fi

MODULE_NAME="$(normalize_module_name "$MODULE_NAME")"
JAVA_VERSION="$(normalize_java_version "$JAVA_VERSION")"
SPRING_BOOT_VERSION="$(normalize_spring_boot_version "$SPRING_BOOT_VERSION")"

if [[ -z "$TIMESTAMP" ]]; then
  TIMESTAMP="$(timestamp_now)"
fi

RUN_ID="$(generate_run_id)"
RUN_DIR="$(run_output_dir "$WORKSPACE_ROOT" "$TIMESTAMP" "$MODULE_NAME")"
mkdir -p "$RUN_DIR"

RUN_LOG="$RUN_DIR/run.log"
ORCHESTRATOR_LOG="$RUN_DIR/orchestrator.log"
PREFLIGHT_LOG="$RUN_DIR/preflight.log"
EXECUTE_REWRITE_LOG="$RUN_DIR/execute-rewrite.log"
MODULE_SEGMENT="$(artifact_module_segment "$MODULE_NAME")"

echo "[$(date +"%Y-%m-%d %H:%M:%S")] orchestrator started runId=$RUN_ID" >>"$ORCHESTRATOR_LOG"

REL_ORCHESTRATOR_LOG="maven-upgrade-java-spring-boot/$TIMESTAMP/$MODULE_SEGMENT/orchestrator.log"
REL_PREFLIGHT_LOG="maven-upgrade-java-spring-boot/$TIMESTAMP/$MODULE_SEGMENT/preflight.log"
REL_EXECUTE_REWRITE_LOG="maven-upgrade-java-spring-boot/$TIMESTAMP/$MODULE_SEGMENT/execute-rewrite.log"

write_run_log \
  "$RUN_LOG" \
  "$RUN_ID" \
  "$TIMESTAMP" \
  "STARTED" \
  "FAILED" \
  "FAILED" \
  "FAILED" \
  "$REL_ORCHESTRATOR_LOG" \
  "$REL_PREFLIGHT_LOG" \
  "$REL_EXECUTE_REWRITE_LOG"

echo "[$(date +"%Y-%m-%d %H:%M:%S")] invoking pre-flight" >>"$ORCHESTRATOR_LOG"
if ! bash "$SCRIPT_DIR/pre-flight.sh" \
  --application-id "$APPLICATION_ID" \
  --module-name "$MODULE_NAME" \
  --java-version "$JAVA_VERSION" \
  --spring-boot-version "$SPRING_BOOT_VERSION" \
  --timestamp "$TIMESTAMP" \
  --workspace-root "$WORKSPACE_ROOT"; then
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] pre-flight failed" >>"$ORCHESTRATOR_LOG"
  write_run_log \
    "$RUN_LOG" \
    "$RUN_ID" \
    "$TIMESTAMP" \
    "FAILED" \
    "FAILED" \
    "FAILED" \
    "FAILED" \
    "$REL_ORCHESTRATOR_LOG" \
    "$REL_PREFLIGHT_LOG" \
    "$REL_EXECUTE_REWRITE_LOG"
  exit 1
fi

echo "[$(date +"%Y-%m-%d %H:%M:%S")] pre-flight succeeded" >>"$ORCHESTRATOR_LOG"

write_run_log \
  "$RUN_LOG" \
  "$RUN_ID" \
  "$TIMESTAMP" \
  "IN-PROGRESS" \
  "SUCCESS" \
  "SUCCESS" \
  "FAILED" \
  "$REL_ORCHESTRATOR_LOG" \
  "$REL_PREFLIGHT_LOG" \
  "$REL_EXECUTE_REWRITE_LOG"

echo "[$(date +"%Y-%m-%d %H:%M:%S")] launching execute-rewrite" >>"$ORCHESTRATOR_LOG"
if ! bash "$SCRIPT_DIR/execute-rewrite.sh" \
  --application-id "$APPLICATION_ID" \
  --module-name "$MODULE_NAME" \
  --java-version "$JAVA_VERSION" \
  --spring-boot-version "$SPRING_BOOT_VERSION" \
  --timestamp "$TIMESTAMP" \
  --run-id "$RUN_ID" \
  --workspace-root "$WORKSPACE_ROOT"; then
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] execute-rewrite launch failed" >>"$ORCHESTRATOR_LOG"
  write_run_log \
    "$RUN_LOG" \
    "$RUN_ID" \
    "$TIMESTAMP" \
    "FAILED" \
    "FAILED" \
    "SUCCESS" \
    "FAILED" \
    "$REL_ORCHESTRATOR_LOG" \
    "$REL_PREFLIGHT_LOG" \
    "$REL_EXECUTE_REWRITE_LOG"
  exit 1
fi

echo "[$(date +"%Y-%m-%d %H:%M:%S")] execute-rewrite launched in non-blocking mode" >>"$ORCHESTRATOR_LOG"

write_run_log \
  "$RUN_LOG" \
  "$RUN_ID" \
  "$TIMESTAMP" \
  "IN-PROGRESS" \
  "SUCCESS" \
  "SUCCESS" \
  "SUCCESS" \
  "$REL_ORCHESTRATOR_LOG" \
  "$REL_PREFLIGHT_LOG" \
  "$REL_EXECUTE_REWRITE_LOG"

echo "[$(date +"%Y-%m-%d %H:%M:%S")] orchestrator completed without waiting for rewrite" >>"$ORCHESTRATOR_LOG"