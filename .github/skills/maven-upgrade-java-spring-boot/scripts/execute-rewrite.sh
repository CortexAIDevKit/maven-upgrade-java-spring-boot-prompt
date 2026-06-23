#!/usr/bin/env bash
#
# execute-rewrite.sh - run OpenRewrite (mvn rewrite:run) to upgrade Java and
# Spring Boot for the requested module.
#
# Works for both single-module and multi-module Maven projects:
#   * module "."        -> runs at the reactor root
#   * module "<name>"   -> runs with -pl <name> -am (build the module + its
#                          upstream dependencies so the reactor resolves)
#
# NON-BLOCKING: mvn rewrite:run can take a long time, so the Maven process is
# launched in the background. This script returns immediately after recording:
#   <out>/execute-rewrite.pid    (background pid)
#   <out>/execute-rewrite.log    (full mvn output)
# When the background job finishes it writes:
#   <out>/execute-rewrite.exit   (exit code)
# and updates run.log (status.execute-rewrite -> SUCCESS|FAILED).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
parse_common_args "$@"

LOG="${OUT_DIR}/execute-rewrite.log"
rm -f "${OUT_DIR}/execute-rewrite.exit"

# ---- safety gate: never run on an unvalidated project -----------------------
if ! require_preflight "$LOG" "execute-rewrite"; then
  echo 1 > "${OUT_DIR}/execute-rewrite.exit"
  state_set status_execute_rewrite FAILED
  exit 1
fi

# ---- resolve recipes --------------------------------------------------------
# Consolidate the per-version fragments under resources/rewrite into a single
# generated rewrite.yml + artifact-coordinates.txt in the run directory. This
# sets ACTIVE (composition recipe name), COORDS and REWRITE_CONFIG.
if ! generate_rewrite_assets "$LOG"; then
  log "$LOG" "ERROR: failed to generate OpenRewrite assets for java='${JAVA_VERSION}' spring-boot='${SPRING_BOOT_VERSION}'"
  echo 2 > "${OUT_DIR}/execute-rewrite.exit"
  state_set status_execute_rewrite FAILED
  exit 2
fi

# ---- module targeting -------------------------------------------------------
PL_ARGS=()
if [[ "$MODULE_NAME" != "." ]]; then
  PL_ARGS=(-pl "$MODULE_NAME" -am)
fi

log "$LOG" "Active recipes: ${ACTIVE}"
log "$LOG" "Recipe artifacts: ${COORDS}"
log "$LOG" "Rewrite config: ${REWRITE_CONFIG}"
log "$LOG" "Module target: ${MODULE_NAME} ${PL_ARGS[*]:-(reactor root)}"

# ---- launch in background ---------------------------------------------------
run_rewrite() {
  cd "$BASE_DIR" || return 3
  # ${PL_ARGS[@]+...} guards against "unbound variable" when the array is empty
  # (module ".") under `set -u` on Bash 3.2 (the default on macOS).
  mvn -U -B \
    org.openrewrite.maven:rewrite-maven-plugin:RELEASE:run \
    ${PL_ARGS[@]+"${PL_ARGS[@]}"} \
    -Drewrite.configLocation="$REWRITE_CONFIG" \
    -Drewrite.activeRecipes="$ACTIVE" \
    -Drewrite.recipeArtifactCoordinates="$COORDS"
}

{
  if run_rewrite; then rc=0; else rc=$?; fi
  # Set status BEFORE writing the .exit sentinel so the orchestrator (which
  # unblocks on the sentinel) always observes a committed status.
  if [[ $rc -eq 0 ]]; then
    state_set status_execute_rewrite SUCCESS
    log "$LOG" "rewrite:run COMPLETED (rc=0)"
  else
    state_set status_execute_rewrite FAILED
    log "$LOG" "rewrite:run FAILED (rc=${rc})"
  fi
  echo "$rc" > "${OUT_DIR}/execute-rewrite.exit"
} >> "$LOG" 2>&1 &

REWRITE_PID=$!
disown "$REWRITE_PID" 2>/dev/null || true
echo "$REWRITE_PID" > "${OUT_DIR}/execute-rewrite.pid"
log "$LOG" "rewrite:run launched in background pid=${REWRITE_PID} (non-blocking)"
exit 0
