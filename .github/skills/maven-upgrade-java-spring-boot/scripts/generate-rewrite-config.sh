#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOURCE_ROOT="$SCRIPT_DIR/../resources/rewrite"
WORKSPACE_ROOT="$(pwd)"
OUTPUT_FILE=""
JAVA_VERSION=""
SPRING_BOOT_VERSION=""

usage() {
  cat <<'EOF'
Usage:
  generate-rewrite-config.sh --java-version <17|21|25> --spring-boot-version <3.5|4.0> [--workspace-root <path>] [--output-file <path>]

Description:
  1) Reads rewrite resources for the selected Java and Spring Boot versions.
  2) Generates a combined rewrite.yml at the repository root (or --output-file).
  3) Prints a Maven flags string:
     -Drewrite.activeRecipes=<combinedRecipe> -Drewrite.recipeArtifactCoordinates=<csv>
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

normalize_spring_boot_dir() {
  local value="$1"
  case "$value" in
    3.5)
      echo "3_5"
      ;;
    4.0|4)
      echo "4_0"
      ;;
    *)
      echo ""
      ;;
  esac
}

get_recipe_name() {
  local file="$1"
  awk '/^name:[[:space:]]+/ {print $2; exit}' "$file"
}

dedupe_documents_by_name() {
  local input_file="$1"
  local output_file="$2"

  awk '
    function ltrim(s) { sub(/^[ \t\r\n]+/, "", s); return s }
    function rtrim(s) { sub(/[ \t\r\n]+$/, "", s); return s }
    function trim(s) { return rtrim(ltrim(s)) }

    BEGIN {
      RS="---[ \t\r\n]*\n"
      ORS=""
    }

    {
      block = trim($0)
      if (block == "") {
        next
      }

      recipe_name = ""
      n = split(block, lines, /\n/)
      for (i = 1; i <= n; i++) {
        if (lines[i] ~ /^name:[ \t]+/) {
          recipe_name = lines[i]
          sub(/^name:[ \t]+/, "", recipe_name)
          recipe_name = trim(recipe_name)
          break
        }
      }

      if (recipe_name == "") {
        key = block
      } else {
        key = "name::" recipe_name
      }

      if (!(key in seen)) {
        seen[key] = 1
        print "---\n" block "\n\n"
      }
    }
  ' "$input_file" > "$output_file"
}

build_unique_coordinates_csv() {
  local java_coords_file="$1"
  local spring_coords_file="$2"

  awk -F',' '
    function ltrim(s) { sub(/^[ \t\r\n]+/, "", s); return s }
    function rtrim(s) { sub(/[ \t\r\n]+$/, "", s); return s }
    function trim(s) { return rtrim(ltrim(s)) }

    {
      for (i = 1; i <= NF; i++) {
        token = trim($i)
        if (token != "" && !(token in seen)) {
          seen[token] = 1
          ordered[++count] = token
        }
      }
    }

    END {
      for (i = 1; i <= count; i++) {
        printf "%s", ordered[i]
        if (i < count) {
          printf ","
        }
      }
    }
  ' "$java_coords_file" "$spring_coords_file"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --java-version)
      JAVA_VERSION="${2:-}"
      shift 2
      ;;
    --spring-boot-version)
      SPRING_BOOT_VERSION="${2:-}"
      shift 2
      ;;
    --workspace-root)
      WORKSPACE_ROOT="${2:-}"
      shift 2
      ;;
    --output-file)
      OUTPUT_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$JAVA_VERSION" || -z "$SPRING_BOOT_VERSION" ]]; then
  echo "Both --java-version and --spring-boot-version are required." >&2
  usage >&2
  exit 1
fi

case "$JAVA_VERSION" in
  17|21|25)
    ;;
  *)
    echo "Unsupported java version: $JAVA_VERSION (expected 17, 21, or 25)." >&2
    exit 1
    ;;
esac

SPRING_BOOT_DIR="$(normalize_spring_boot_dir "$SPRING_BOOT_VERSION")"
if [[ -z "$SPRING_BOOT_DIR" ]]; then
  echo "Unsupported spring boot version: $SPRING_BOOT_VERSION (expected 3.5 or 4.0)." >&2
  exit 1
fi

if [[ "$SPRING_BOOT_VERSION" == "4" ]]; then
  SPRING_BOOT_VERSION="4.0"
fi

JAVA_DIR="$RESOURCE_ROOT/java/$JAVA_VERSION"
SPRING_DIR="$RESOURCE_ROOT/spring-boot/$SPRING_BOOT_DIR"

JAVA_REWRITE_FILE="$JAVA_DIR/rewrite.yml"
SPRING_REWRITE_FILE="$SPRING_DIR/rewrite.yml"
JAVA_COORDS_FILE="$JAVA_DIR/artifact-coordinates.txt"
SPRING_COORDS_FILE="$SPRING_DIR/artifact-coordinates.txt"

for path in "$JAVA_REWRITE_FILE" "$SPRING_REWRITE_FILE" "$JAVA_COORDS_FILE" "$SPRING_COORDS_FILE"; do
  if [[ ! -f "$path" ]]; then
    echo "Required file not found: $path" >&2
    exit 1
  fi
done

if [[ -z "$OUTPUT_FILE" ]]; then
  OUTPUT_FILE="$WORKSPACE_ROOT/rewrite.yml"
fi

JAVA_RECIPE_NAME="$(get_recipe_name "$JAVA_REWRITE_FILE")"
SPRING_RECIPE_NAME="$(get_recipe_name "$SPRING_REWRITE_FILE")"

if [[ -z "$JAVA_RECIPE_NAME" || -z "$SPRING_RECIPE_NAME" ]]; then
  echo "Failed to parse recipe names from source rewrite.yml files." >&2
  exit 1
fi

SPRING_BOOT_UNDERSCORE="${SPRING_BOOT_VERSION//./_}"
COMBINED_RECIPE_NAME="org.cortexaidevkit.java.spring.boot.UpgradeJava${JAVA_VERSION}SpringBoot_${SPRING_BOOT_UNDERSCORE}"

TMP_INPUT="$(mktemp)"
TMP_OUTPUT="$(mktemp)"
trap 'rm -f "$TMP_INPUT" "$TMP_OUTPUT"' EXIT

{
  cat "$JAVA_REWRITE_FILE"
  echo
  cat "$SPRING_REWRITE_FILE"
  echo
  cat <<EOF
---
type: specs.openrewrite.org/v1beta/recipe
name: $COMBINED_RECIPE_NAME
displayName: Upgrade Java $JAVA_VERSION and Spring Boot $SPRING_BOOT_VERSION
recipeList:
  - $JAVA_RECIPE_NAME
  - $SPRING_RECIPE_NAME
EOF
} > "$TMP_INPUT"

dedupe_documents_by_name "$TMP_INPUT" "$TMP_OUTPUT"
mv "$TMP_OUTPUT" "$OUTPUT_FILE"

COORDINATES_CSV="$(build_unique_coordinates_csv "$JAVA_COORDS_FILE" "$SPRING_COORDS_FILE")"

if [[ -z "$COORDINATES_CSV" ]]; then
  echo "Failed to resolve rewrite recipe artifact coordinates." >&2
  exit 1
fi

echo "-Drewrite.activeRecipes=$COMBINED_RECIPE_NAME -Drewrite.recipeArtifactCoordinates=$COORDINATES_CSV"
