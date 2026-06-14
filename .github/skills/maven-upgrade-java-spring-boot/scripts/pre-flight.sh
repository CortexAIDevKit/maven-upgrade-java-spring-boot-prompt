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

MODULE_NAME="$(normalize_module_name "$MODULE_NAME")"
JAVA_VERSION="$(normalize_java_version "$JAVA_VERSION")"
SPRING_BOOT_VERSION="$(normalize_spring_boot_version "$SPRING_BOOT_VERSION")"

if [[ -z "$TIMESTAMP" ]]; then
  TIMESTAMP="$(timestamp_now)"
fi

RUN_DIR="$(run_output_dir "$WORKSPACE_ROOT" "$TIMESTAMP" "$MODULE_NAME")"
mkdir -p "$RUN_DIR"

PREFLIGHT_LOG="$RUN_DIR/preflight.log"
PREFLIGHT_ERROR_LOG="$RUN_DIR/pre-flight-error.log"

log() {
  echo "[$(date +"%Y-%m-%d %H:%M:%S")] $*" | tee -a "$PREFLIGHT_LOG"
}

fail() {
  local message="$1"
  log "ERROR: $message"
  echo "$message" >>"$PREFLIGHT_ERROR_LOG"
  exit 1
}

log "Starting pre-flight validation"
log "application-id=$APPLICATION_ID module-name=$MODULE_NAME java-version=$JAVA_VERSION spring-boot-version=$SPRING_BOOT_VERSION"

if [[ -z "$APPLICATION_ID" ]]; then
  fail "application-id is required"
fi

case "$JAVA_VERSION" in
  17|21|25)
    ;;
  *)
    fail "java-version must be one of: 17, 21, 25"
    ;;
esac

case "$SPRING_BOOT_VERSION" in
  3.5|4.0)
    ;;
  *)
    fail "spring-boot-version must be one of: 3.5, 4.0"
    ;;
esac

ROOT_POM="$WORKSPACE_ROOT/pom.xml"
if [[ ! -f "$ROOT_POM" ]]; then
  fail "root pom.xml not found at $ROOT_POM"
fi

if [[ "$MODULE_NAME" == "." ]]; then
  TARGET_POM="$ROOT_POM"
else
  TARGET_POM="$WORKSPACE_ROOT/$MODULE_NAME/pom.xml"

  MODULE_LIST="$(awk '
    /<modules>/ { in_modules=1; next }
    /<\/modules>/ { in_modules=0 }
    in_modules {
      gsub(/^[ \t]+|[ \t]+$/, "", $0)
      if ($0 ~ /<module>/) {
        gsub(/<module>|<\/module>/, "", $0)
        gsub(/^[ \t]+|[ \t]+$/, "", $0)
        print $0
      }
    }
  ' "$ROOT_POM")"

  if ! echo "$MODULE_LIST" | grep -Fxq "$MODULE_NAME"; then
    fail "module-name '$MODULE_NAME' is not declared in root pom.xml <modules>"
  fi
fi

if [[ ! -f "$TARGET_POM" ]]; then
  fail "target pom.xml not found at $TARGET_POM"
fi

if ! grep -q "<project" "$TARGET_POM"; then
  fail "target pom.xml appears invalid (missing <project>) at $TARGET_POM"
fi

log "Pre-flight validation completed successfully"