#!/usr/bin/env bash
#
# common.sh - shared helpers for the maven-upgrade-java-spring-boot skill.
#
# This file is sourced by every script in this directory. It centralises:
#   * argument parsing + defaulting of the user inputs
#   * resolution of the per-run output directory
#   * the run.log JSON renderer (no jq / python dependency required)
#   * timestamped logging helpers
#   * OpenRewrite recipe lookup tables
#
# Status values used in run.log:
#   overallStatus : STARTED | IN-PROGRESS | FAILED | COMPLETED
#   status.<step> : "" (pending) | SUCCESS | FAILED
#
# IMPORTANT: the <timestamp> is computed ONCE by the orchestrator and is then
# passed to every other script via --timestamp so the whole run shares a single
# output directory. The format is yyyyMMdd-HHmmss (24-hour clock).

set -uo pipefail

SKILL_NAME="maven-upgrade-java-spring-boot"

# Directory holding the per-version OpenRewrite fragments that get consolidated
# into the generated rewrite.yml. Resolved relative to this file so it works no
# matter which script sources common.sh.
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCES_DIR="${COMMON_DIR}/../resources/rewrite"

# ----------------------------------------------------------------------------
# parse_common_args <args...>
#   Populates the well-known globals used across all scripts and applies the
#   documented defaults (module=., java=25, spring-boot=4.0). Creates OUT_DIR.
# ----------------------------------------------------------------------------
parse_common_args() {
  MODULE_NAME=""
  JAVA_VERSION=""
  SPRING_BOOT_VERSION=""
  TIMESTAMP=""
  BASE_DIR="$(pwd)"
  FORCE=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --module-name)         MODULE_NAME="${2:-}"; shift 2;;
      --java-version)        JAVA_VERSION="${2:-}"; shift 2;;
      --spring-boot-version) SPRING_BOOT_VERSION="${2:-}"; shift 2;;
      --timestamp)           TIMESTAMP="${2:-}"; shift 2;;
      --base-dir)            BASE_DIR="${2:-}"; shift 2;;
      --force)               FORCE=1; shift;;
      *) echo "WARN: ignoring unknown argument '$1'" >&2; shift;;
    esac
  done

  # ---- defaults ----
  MODULE_NAME="${MODULE_NAME:-.}"
  JAVA_VERSION="${JAVA_VERSION:-25}"
  SPRING_BOOT_VERSION="${SPRING_BOOT_VERSION:-4.0}"
  [[ -z "$TIMESTAMP" ]] && TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

  # A filesystem-friendly label for the module ("." -> root).
  if [[ "$MODULE_NAME" == "." || -z "$MODULE_NAME" ]]; then
    MODULE_LABEL="root"
  else
    MODULE_LABEL="${MODULE_NAME//\//-}"
  fi

  REL_DIR="${SKILL_NAME}/${TIMESTAMP}/${MODULE_LABEL}"
  OUT_DIR="${BASE_DIR}/${REL_DIR}"
  STATE_FILE="${OUT_DIR}/run.state"
  RUN_LOG="${OUT_DIR}/run.log"

  mkdir -p "$OUT_DIR"
}

# ----------------------------------------------------------------------------
# log <logfile> <message...>
#   Appends a timestamped line to <logfile> and echoes it to stdout.
# ----------------------------------------------------------------------------
log() {
  local logfile="$1"; shift
  local line="[$(date +%Y-%m-%dT%H:%M:%S%z)] $*"
  printf '%s\n' "$line" | tee -a "$logfile"
}

# ----------------------------------------------------------------------------
# state_set <key> <value>   /   state_get <key>
#   Simple KEY=VALUE side-car (run.state) used to regenerate run.log.
#   Avoids any dependency on jq or python. Every mutation re-renders run.log.
# ----------------------------------------------------------------------------
state_set() {
  local key="$1" val="$2" tmp
  touch "$STATE_FILE"
  tmp="$(mktemp)"
  grep -v "^${key}=" "$STATE_FILE" > "$tmp" 2>/dev/null || true
  printf '%s=%s\n' "$key" "$val" >> "$tmp"
  mv "$tmp" "$STATE_FILE"
  render_run_log
}

state_get() {
  local key="$1"
  grep "^${key}=" "$STATE_FILE" 2>/dev/null | tail -n1 | cut -d= -f2-
}

# ----------------------------------------------------------------------------
# render_run_log
#   Regenerates run.log (JSON) from the current run.state contents.
# ----------------------------------------------------------------------------
render_run_log() {
  cat > "$RUN_LOG" <<EOF
{
  "runId": "$(state_get runId)",
  "timestamp": "${TIMESTAMP}",
  "overallStatus": "$(state_get overallStatus)",
  "status": {
    "orchestrator": "$(state_get status_orchestrator)",
    "preflight": "$(state_get status_preflight)",
    "execute-rewrite": "$(state_get status_execute_rewrite)",
    "maven-build": "$(state_get status_maven_build)"
  },
  "log": {
    "orchestrator": "${REL_DIR}/orchestrator.log",
    "preflight": "${REL_DIR}/preflight.log",
    "execute-rewrite": "${REL_DIR}/execute-rewrite.log",
    "maven-build": "${REL_DIR}/maven-build.log"
  }
}
EOF
}

# ----------------------------------------------------------------------------
# require_preflight <logfile> <step-name>
#   Safety gate so that execute-rewrite / maven-build cannot mutate or build an
#   unvalidated project when invoked directly (bypassing the orchestrator).
#
#   * If pre-flight already passed for THIS run (status.preflight == SUCCESS in
#     the shared run.state), this is a no-op -> orchestrated runs pay nothing.
#   * Otherwise it runs pre-flight inline against the same run dir, so a direct
#     standalone call is still validated before anything happens.
#   * --force bypasses the gate (escape hatch for advanced/manual use).
#
#   Returns 0 to proceed, 1 to abort the caller.
# ----------------------------------------------------------------------------
require_preflight() {
  local logfile="$1" step="$2"
  local lib_dir; lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [[ "${FORCE:-0}" == "1" ]]; then
    log "$logfile" "WARN: --force set; skipping pre-flight gate for ${step}"
    return 0
  fi

  if [[ "$(state_get status_preflight)" == "SUCCESS" ]]; then
    log "$logfile" "pre-flight already passed for this run; proceeding with ${step}"
    return 0
  fi

  log "$logfile" "pre-flight has not passed for this run; running it now before ${step}"
  if bash "${lib_dir}/pre-flight.sh" \
        --module-name "$MODULE_NAME" \
        --java-version "$JAVA_VERSION" \
        --spring-boot-version "$SPRING_BOOT_VERSION" \
        --timestamp "$TIMESTAMP" \
        --base-dir "$BASE_DIR" >>"$logfile" 2>&1; then
    log "$logfile" "pre-flight SUCCESS; proceeding with ${step}"
    return 0
  fi

  log "$logfile" "ERROR: pre-flight FAILED; refusing to run ${step} (see pre-flight-error.log)"
  return 1
}

# ----------------------------------------------------------------------------
# wait_for_exit <step> [timeout-seconds]
#   Polls for "<step>.exit" (written by a background mvn job) without busy
#   spinning. Returns the captured exit code, or 124 on timeout.
# ----------------------------------------------------------------------------
wait_for_exit() {
  local step="$1" timeout="${2:-7200}" waited=0 interval=5
  while [[ ! -f "${OUT_DIR}/${step}.exit" ]]; do
    sleep "$interval"
    waited=$((waited + interval))
    if [[ $waited -ge $timeout ]]; then
      return 124
    fi
  done
  return "$(cat "${OUT_DIR}/${step}.exit")"
}

# ----------------------------------------------------------------------------
# OpenRewrite resource resolution.
#
# The recipes and artifact coordinates are NOT hard-coded; they live as small
# fragments under resources/rewrite/<kind>/<version>/ and are consolidated into
# a single generated rewrite.yml per run.
#
#   resources/rewrite/java/<17|21|25>/{rewrite.yml,artifact-coordinates.txt}
#   resources/rewrite/spring-boot/<3_5|4_0>/{rewrite.yml,artifact-coordinates.txt}
# ----------------------------------------------------------------------------
java_resource_dir()   { printf '%s\n' "${RESOURCES_DIR}/java/$1"; }
# spring-boot version "4.0" maps to the directory "4_0".
spring_resource_dir() { printf '%s\n' "${RESOURCES_DIR}/spring-boot/${1//./_}"; }

# extract_recipes <yml...>
#   Prints every recipeList entry (the bare recipe id) from the given
#   rewrite.yml fragment(s), one per line, trimmed.
extract_recipes() {
  grep -hE '^[[:space:]]*-[[:space:]]+' "$@" 2>/dev/null \
    | sed -E 's/^[[:space:]]*-[[:space:]]+//; s/[[:space:]]+$//'
}

# ----------------------------------------------------------------------------
# generate_rewrite_assets <logfile>
#   Consolidates the per-version fragments for JAVA_VERSION + SPRING_BOOT_VERSION
#   into the run directory:
#
#     <OUT_DIR>/rewrite.yml               - each source fragment, followed by a
#                                           composition recipe whose recipeList
#                                           is the de-duplicated union of all the
#                                           included recipes.
#     <OUT_DIR>/artifact-coordinates.txt  - the de-duplicated union of the
#                                           source artifact coordinates.
#
#   On success sets the globals consumed by execute-rewrite.sh:
#     ACTIVE          - the composition recipe name (-> -Drewrite.activeRecipes)
#     COORDS          - comma-joined coordinates (-> recipeArtifactCoordinates)
#     REWRITE_CONFIG  - path to the generated rewrite.yml (-> configLocation)
#
#   Returns 0 on success, non-zero (with a logged ERROR) otherwise.
# ----------------------------------------------------------------------------
generate_rewrite_assets() {
  local logfile="$1"
  local java_dir spring_dir
  java_dir="$(java_resource_dir "$JAVA_VERSION")"
  spring_dir="$(spring_resource_dir "$SPRING_BOOT_VERSION")"

  local java_yml="${java_dir}/rewrite.yml"      java_coords="${java_dir}/artifact-coordinates.txt"
  local spring_yml="${spring_dir}/rewrite.yml"  spring_coords="${spring_dir}/artifact-coordinates.txt"

  local f
  for f in "$java_yml" "$java_coords" "$spring_yml" "$spring_coords"; do
    if [[ ! -f "$f" ]]; then
      log "$logfile" "ERROR: missing OpenRewrite resource '${f}' for java='${JAVA_VERSION}' spring-boot='${SPRING_BOOT_VERSION}'"
      return 1
    fi
  done

  # Composition name referenced by activeRecipes, e.g.
  #   org.cortexaidevkit.spring.boot.UpgradeJava25SpringBoot_4_0
  ACTIVE="org.cortexaidevkit.spring.boot.UpgradeJava${JAVA_VERSION}SpringBoot_${SPRING_BOOT_VERSION//./_}"

  # De-duplicated union of the underlying recipe ids (order preserved).
  local recipes
  recipes="$(extract_recipes "$java_yml" "$spring_yml" | awk 'NF && !seen[$0]++')"
  if [[ -z "$recipes" ]]; then
    log "$logfile" "ERROR: no recipes found in '${java_yml}' or '${spring_yml}'"
    return 1
  fi

  REWRITE_CONFIG="${OUT_DIR}/rewrite.yml"
  {
    cat "$java_yml"
    printf '\n'
    cat "$spring_yml"
    printf '\n---\n'
    printf 'type: specs.openrewrite.org/v1beta/recipe\n'
    printf 'name: %s\n' "$ACTIVE"
    printf 'displayName: Migrate to Java %s and Spring Boot %s\n' "$JAVA_VERSION" "$SPRING_BOOT_VERSION"
    printf 'recipeList:\n'
    printf '%s\n' "$recipes" | sed -E 's/^/  - /'
  } > "$REWRITE_CONFIG"

  # De-duplicated union of artifact coordinates, comma-joined for the plugin.
  # awk reads each file separately, so a source file without a trailing newline
  # does not get glued onto the first line of the next file (cat would do that).
  local coords_file="${OUT_DIR}/artifact-coordinates.txt"
  awk '{ sub(/[[:space:]]+$/, ""); if (length && !seen[$0]++) print }' \
    "$java_coords" "$spring_coords" > "$coords_file"
  COORDS="$(paste -sd, - < "$coords_file")"
  if [[ -z "$COORDS" ]]; then
    log "$logfile" "ERROR: no artifact coordinates found in '${java_coords}' or '${spring_coords}'"
    return 1
  fi

  log "$logfile" "Generated rewrite config: ${REWRITE_CONFIG}"
  log "$logfile" "Generated coordinates:    ${coords_file}"
  return 0
}
