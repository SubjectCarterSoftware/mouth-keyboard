#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SCHEME="TypeLessBuddy"
PROJECT_PATH="${REPO_ROOT}/TypeLessBuddy.xcodeproj"
DERIVED_DATA_DIR="${REPO_ROOT}/build/DerivedData-tests"
OUTPUT_DIR="${EXTERNAL_TEXT_EVAL_OUTPUT_DIR:-${REPO_ROOT}/build/external-text-scenario-eval}"
MARKER_PATH="${TMPDIR:-/tmp}/run_external_text_scenario_eval_tests"
OUTPUT_CONFIG_PATH="${TMPDIR:-/tmp}/external_text_eval_output_dir"
SCENARIO_IDS_CONFIG_PATH="${TMPDIR:-/tmp}/external_text_eval_scenario_ids"
LIMIT_CONFIG_PATH="${TMPDIR:-/tmp}/external_text_eval_limit"
MODEL_TIER_CONFIG_PATH="${TMPDIR:-/tmp}/external_text_eval_model_tier"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Missing required command: xcodebuild" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"
touch "${MARKER_PATH}"
printf "%s" "${OUTPUT_DIR}" > "${OUTPUT_CONFIG_PATH}"
if [[ -n "${EXTERNAL_TEXT_EVAL_SCENARIO_IDS:-}" ]]; then
  printf "%s" "${EXTERNAL_TEXT_EVAL_SCENARIO_IDS}" > "${SCENARIO_IDS_CONFIG_PATH}"
else
  rm -f "${SCENARIO_IDS_CONFIG_PATH}"
fi
if [[ -n "${EXTERNAL_TEXT_EVAL_LIMIT:-}" ]]; then
  printf "%s" "${EXTERNAL_TEXT_EVAL_LIMIT}" > "${LIMIT_CONFIG_PATH}"
else
  rm -f "${LIMIT_CONFIG_PATH}"
fi
if [[ -n "${EXTERNAL_TEXT_EVAL_MODEL_TIER:-}" ]]; then
  printf "%s" "${EXTERNAL_TEXT_EVAL_MODEL_TIER}" > "${MODEL_TIER_CONFIG_PATH}"
else
  rm -f "${MODEL_TIER_CONFIG_PATH}"
fi
trap 'rm -f "${MARKER_PATH}" "${OUTPUT_CONFIG_PATH}" "${SCENARIO_IDS_CONFIG_PATH}" "${LIMIT_CONFIG_PATH}" "${MODEL_TIER_CONFIG_PATH}"' EXIT

echo "Running external text scenario eval..."
echo "Reports: ${OUTPUT_DIR}"

RUN_EXTERNAL_TEXT_SCENARIO_EVAL_TESTS=1 \
EXTERNAL_TEXT_EVAL_OUTPUT_DIR="${OUTPUT_DIR}" \
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_DIR}" \
  -only-testing:TypeLessBuddyTests/ExternalTextScenarioMatrixEvaluationTests \
  test
