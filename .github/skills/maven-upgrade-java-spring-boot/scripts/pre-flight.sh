#!/usr/bin/env bash
#
# pre-flight.sh - validate the user inputs before any mutation happens.
#
# Rules enforced:
#   * java-version          -> one of 17, 21, 25
#   * spring-boot-version   -> one of 3.5, 4.0
#   * module-name           -> "." (root) OR a <module> declared in the root
#                              pom.xml, and the resolved module must contain a
#                              parseable pom.xml.
#
# Logs are written to:
#   <out>/preflight.log            (full trace)
#   <out>/pre-flight-error.log     (validation errors only)
#
# Exit code: 0 = all good, 1 = at least one validation failure.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"
parse_common_args "$@"

LOG="${OUT_DIR}/preflight.log"
ERRLOG="${OUT_DIR}/pre-flight-error.log"
: > "$ERRLOG"

errors=0
fail() {
  local line="[$(date +%Y-%m-%dT%H:%M:%S%z)] ERROR: $*"
  printf '%s\n' "$line" | tee -a "$ERRLOG" "$LOG" >&2
  errors=$((errors + 1))
}

log "$LOG" "Preflight started: module='${MODULE_NAME}' java='${JAVA_VERSION}' spring-boot='${SPRING_BOOT_VERSION}'"

# ---- 1. java-version --------------------------------------------------------
case "$JAVA_VERSION" in
  17|21|25) log "$LOG" "java-version '${JAVA_VERSION}' is valid";;
  *)        fail "Invalid java-version '${JAVA_VERSION}'. Allowed values: 17, 21, 25";;
esac

# ---- 2. spring-boot-version -------------------------------------------------
case "$SPRING_BOOT_VERSION" in
  3.5|4.0) log "$LOG" "spring-boot-version '${SPRING_BOOT_VERSION}' is valid";;
  *)       fail "Invalid spring-boot-version '${SPRING_BOOT_VERSION}'. Allowed values: 3.5, 4.0";;
esac

# ---- 3. root pom must exist -------------------------------------------------
ROOT_POM="${BASE_DIR}/pom.xml"
if [[ ! -f "$ROOT_POM" ]]; then
  fail "Root pom.xml not found at '${ROOT_POM}'"
fi

# ---- 4. module-name validity -----------------------------------------------
if [[ "$MODULE_NAME" == "." ]]; then
  if [[ -f "$ROOT_POM" ]]; then
    log "$LOG" "Targeting root project (module='.')"
    TARGET_POM="$ROOT_POM"
  fi
else
  if [[ -f "$ROOT_POM" ]] && grep -q "<module>[[:space:]]*${MODULE_NAME}[[:space:]]*</module>" "$ROOT_POM"; then
    TARGET_POM="${BASE_DIR}/${MODULE_NAME}/pom.xml"
    if [[ -f "$TARGET_POM" ]]; then
      log "$LOG" "Module '${MODULE_NAME}' declared in root pom and has its own pom.xml"
    else
      fail "Module '${MODULE_NAME}' is declared in root pom but has no pom.xml at '${TARGET_POM}'"
    fi
  else
    fail "Module '${MODULE_NAME}' is not declared in the root pom.xml <modules> section. Use '.' for the root project."
  fi
fi

# ---- 5. pom well-formedness (best effort) ----------------------------------
if [[ -n "${TARGET_POM:-}" && -f "${TARGET_POM:-}" ]]; then
  if command -v xmllint >/dev/null 2>&1; then
    if xmllint --noout "$TARGET_POM" >>"$LOG" 2>>"$ERRLOG"; then
      log "$LOG" "pom.xml is well-formed: ${TARGET_POM}"
    else
      fail "pom.xml is not well-formed XML: ${TARGET_POM}"
    fi
  else
    log "$LOG" "xmllint not available; skipping XML well-formedness check"
  fi
fi

# ---- result -----------------------------------------------------------------
if [[ $errors -gt 0 ]]; then
  log "$LOG" "Preflight FAILED with ${errors} error(s). See ${ERRLOG}"
  state_set status_preflight FAILED
  exit 1
fi

log "$LOG" "Preflight SUCCESS"
state_set status_preflight SUCCESS
exit 0
