#!/usr/bin/env bash
#
# maven-build.sh - run `mvn clean install` to validate the changes produced by
# OpenRewrite.
#
# Works for both single-module and multi-module Maven projects:
#   * module "."        -> builds the whole reactor
#   * module "<name>"   -> builds with -pl <name> -am
#
# NON-BLOCKING: the build can take a long time, so Maven is launched in the
# background. This script returns immediately after recording:
#   <out>/maven-build.pid    (background pid)
#   <out>/maven-build.log    (full mvn output)
# When the background job finishes it writes:
#   <out>/maven-build.exit   (exit code)
# and updates run.log (status.maven-build -> SUCCESS|FAILED).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
parse_common_args "$@"

LOG="${OUT_DIR}/maven-build.log"
rm -f "${OUT_DIR}/maven-build.exit"

# ---- safety gate: never build an unvalidated project ------------------------
if ! require_preflight "$LOG" "maven-build"; then
  echo 1 > "${OUT_DIR}/maven-build.exit"
  state_set status_maven_build FAILED
  exit 1
fi

# ---- module targeting -------------------------------------------------------
PL_ARGS=()
if [[ "$MODULE_NAME" != "." ]]; then
  PL_ARGS=(-pl "$MODULE_NAME" -am)
fi

log "$LOG" "Module target: ${MODULE_NAME} ${PL_ARGS[*]:-(reactor root)}"

# ---- launch in background ---------------------------------------------------
run_build() {
  cd "$BASE_DIR" || return 3
  # ${PL_ARGS[@]+...} guards against "unbound variable" when the array is empty
  # (module ".") under `set -u` on Bash 3.2 (the default on macOS).
  mvn -U -B clean install ${PL_ARGS[@]+"${PL_ARGS[@]}"}
}

{
  if run_build; then rc=0; else rc=$?; fi
  # Set status BEFORE writing the .exit sentinel so the orchestrator (which
  # unblocks on the sentinel) always observes a committed status.
  if [[ $rc -eq 0 ]]; then
    state_set status_maven_build SUCCESS
    log "$LOG" "clean install COMPLETED (rc=0)"
  else
    state_set status_maven_build FAILED
    log "$LOG" "clean install FAILED (rc=${rc})"
  fi
  echo "$rc" > "${OUT_DIR}/maven-build.exit"
} >> "$LOG" 2>&1 &

BUILD_PID=$!
disown "$BUILD_PID" 2>/dev/null || true
echo "$BUILD_PID" > "${OUT_DIR}/maven-build.pid"
log "$LOG" "clean install launched in background pid=${BUILD_PID} (non-blocking)"
exit 0
