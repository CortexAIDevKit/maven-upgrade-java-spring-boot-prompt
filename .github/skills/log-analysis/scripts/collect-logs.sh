#!/usr/bin/env bash
#
# collect-logs.sh - gather every log + run.log for a given run so the agent can
# analyse them and produce a report.
#
# Usage:
#   collect-logs.sh --timestamp <yyyyMMdd-HHmmss> --module-name <name|.> \
#                   [--base-dir <repo-root>]
#
# Prints, to stdout:
#   * run.log (verbatim)
#   * a tail of every *.log file in the run directory
# These are the raw inputs for the log-analysis report.

set -uo pipefail

SKILL_NAME="maven-upgrade-java-spring-boot"
TIMESTAMP=""
MODULE_NAME="."
BASE_DIR="$(pwd)"
TAIL_LINES=200

while [[ $# -gt 0 ]]; do
  case "$1" in
    --timestamp)   TIMESTAMP="${2:-}"; shift 2;;
    --module-name) MODULE_NAME="${2:-}"; shift 2;;
    --base-dir)    BASE_DIR="${2:-}"; shift 2;;
    --tail)        TAIL_LINES="${2:-200}"; shift 2;;
    *) echo "WARN: ignoring unknown argument '$1'" >&2; shift;;
  esac
done

if [[ -z "$TIMESTAMP" ]]; then
  echo "ERROR: --timestamp is required" >&2
  exit 2
fi

if [[ "$MODULE_NAME" == "." || -z "$MODULE_NAME" ]]; then
  MODULE_LABEL="root"
else
  MODULE_LABEL="${MODULE_NAME//\//-}"
fi

RUN_DIR="${BASE_DIR}/${SKILL_NAME}/${TIMESTAMP}/${MODULE_LABEL}"

if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR: run directory not found: ${RUN_DIR}" >&2
  exit 1
fi

echo "===== RUN DIRECTORY ====="
echo "$RUN_DIR"
echo

echo "===== run.log ====="
if [[ -f "${RUN_DIR}/run.log" ]]; then
  cat "${RUN_DIR}/run.log"
else
  echo "(run.log missing)"
fi
echo

for f in "${RUN_DIR}"/*.log; do
  [[ -e "$f" ]] || continue
  echo "===== $(basename "$f") (last ${TAIL_LINES} lines) ====="
  tail -n "$TAIL_LINES" "$f"
  echo
done
