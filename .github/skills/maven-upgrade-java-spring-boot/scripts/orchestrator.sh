#!/usr/bin/env bash
#
# orchestrator.sh - drives the maven-upgrade-java-spring-boot pipeline.
#
# Responsibilities:
#   1. Compute the run identity and the shared <timestamp> (yyyyMMdd-HHmmss).
#   2. Own and continuously update run.log.
#   3. Chain the steps:
#        pre-flight  -> execute-rewrite  -> maven-build
#      Each long-running mvn step is launched non-blocking by its own script;
#      the orchestrator waits on the step's *.exit sentinel before chaining the
#      next step (so build only runs once rewrite finished).
#
# Usage:
#   orchestrator.sh --module-name <name|.> \
#                   --java-version <17|21|25> \
#                   --spring-boot-version <3.5|4.0> \
#                   [--timestamp <yyyyMMdd-HHmmss>] \
#                   [--base-dir <repo-root>]
#
# Because rewrite + build can take a long time, the SKILL launches this
# orchestrator itself in the background (nohup ... &) and then polls run.log.
#
# Output: maven-upgrade-java-spring-boot/<timestamp>/<module-label>/run.log

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
parse_common_args "$@"

LOG="${OUT_DIR}/orchestrator.log"
: > "$LOG"

# ---- initialise run state ---------------------------------------------------
RUN_ID="${TIMESTAMP}-$$-${RANDOM}"
state_set runId "$RUN_ID"
state_set timestamp "$TIMESTAMP"
state_set overallStatus STARTED
state_set status_orchestrator ""
state_set status_preflight ""
state_set status_execute_rewrite ""
state_set status_maven_build ""

log "$LOG" "==== Run ${RUN_ID} started ===="
log "$LOG" "module='${MODULE_NAME}' (label='${MODULE_LABEL}') java='${JAVA_VERSION}' spring-boot='${SPRING_BOOT_VERSION}'"
log "$LOG" "timestamp='${TIMESTAMP}' base-dir='${BASE_DIR}'"
log "$LOG" "output dir: ${OUT_DIR}"

COMMON_ARGS=(
  --module-name "$MODULE_NAME"
  --java-version "$JAVA_VERSION"
  --spring-boot-version "$SPRING_BOOT_VERSION"
  --timestamp "$TIMESTAMP"
  --base-dir "$BASE_DIR"
)

abort_failed() {
  # Orchestrator did its job (it orchestrated) even when a step fails, so
  # status_orchestrator is SUCCESS while overallStatus reflects the failure.
  log "$LOG" "Pipeline halted: $*"
  state_set overallStatus FAILED
  state_set status_orchestrator SUCCESS
  log "$LOG" "==== Run ${RUN_ID} finished: FAILED ===="
  exit 1
}

# ---- 1. pre-flight (synchronous, fast) -------------------------------------
state_set overallStatus AT_PRE_FLIGHT
log "$LOG" "Step 1/3: pre-flight"
if bash "${SCRIPT_DIR}/pre-flight.sh" "${COMMON_ARGS[@]}" >>"$LOG" 2>&1; then
  log "$LOG" "pre-flight SUCCESS"
else
  abort_failed "pre-flight validation failed (see pre-flight-error.log)"
fi

# ---- 2. execute-rewrite (non-blocking launch, then wait on sentinel) -------
state_set overallStatus AT_EXECUTE_REWRITE
log "$LOG" "Step 2/3: execute-rewrite (OpenRewrite)"
if ! bash "${SCRIPT_DIR}/execute-rewrite.sh" "${COMMON_ARGS[@]}" >>"$LOG" 2>&1; then
  abort_failed "failed to launch execute-rewrite"
fi

log "$LOG" "Waiting for execute-rewrite to complete..."
if wait_for_exit "execute-rewrite"; then
  log "$LOG" "execute-rewrite SUCCESS"
else
  rc=$?
  [[ $rc -eq 124 ]] && abort_failed "execute-rewrite timed out"
  abort_failed "execute-rewrite returned rc=${rc}"
fi

# ---- 3. maven-build (non-blocking launch, then wait on sentinel) -----------
state_set overallStatus AT_MAVEN_BUILD
log "$LOG" "Step 3/3: maven-build (mvn clean install)"
if ! bash "${SCRIPT_DIR}/maven-build.sh" "${COMMON_ARGS[@]}" >>"$LOG" 2>&1; then
  abort_failed "failed to launch maven-build"
fi

log "$LOG" "Waiting for maven-build to complete..."
if wait_for_exit "maven-build"; then
  log "$LOG" "maven-build SUCCESS"
else
  rc=$?
  [[ $rc -eq 124 ]] && abort_failed "maven-build timed out"
  abort_failed "maven-build returned rc=${rc}"
fi

# ---- done -------------------------------------------------------------------
state_set overallStatus COMPLETED
state_set status_orchestrator SUCCESS
log "$LOG" "==== Run ${RUN_ID} finished: COMPLETED ===="
exit 0
