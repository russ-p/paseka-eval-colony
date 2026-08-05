#!/usr/bin/env bash
# Run all Tier B eval cases in lexical order.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

keep_runtime=false
if [[ "${1:-}" == "--keep-runtime" ]]; then
  keep_runtime=true
fi

case_ids=()
for dir in "${EVAL_ROOT}/cases"/*; do
  [[ -d "${dir}" && -f "${dir}/case.yaml" ]] || continue
  case_ids+=("$(basename "${dir}")")
done
IFS=$'\n' case_ids=($(printf '%s\n' "${case_ids[@]}" | sort))
unset IFS

if [[ "${#case_ids[@]}" -eq 0 ]]; then
  echo "no cases found under ${EVAL_ROOT}/cases" >&2
  exit 1
fi

failed=()
passed=()

for case_id in "${case_ids[@]}"; do
  echo "========== ${case_id} =========="
  run_args=("${SCRIPT_DIR}/run-case.sh" "${case_id}")
  if [[ "${keep_runtime}" == "true" ]]; then
    run_args+=(--keep-runtime)
  fi
  if "${run_args[@]}"; then
    passed+=("${case_id}")
    echo "PASS: ${case_id}"
  else
    failed+=("${case_id}")
    echo "FAIL: ${case_id}" >&2
  fi
  echo
done

echo "========== SUMMARY =========="
echo "passed: ${#passed[@]}/${#case_ids[@]}"
if [[ "${#failed[@]}" -gt 0 ]]; then
  echo "failed: ${failed[*]}" >&2
  exit 1
fi
echo "all cases passed"
