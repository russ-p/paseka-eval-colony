#!/usr/bin/env bash
# Tier B eval runner: reset, dispatch task, wait, oracle, replay report.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

case_id="${1:-}"
keep_runtime=false
if [[ "${2:-}" == "--keep-runtime" ]]; then
  keep_runtime=true
fi

if [[ -z "${case_id}" ]]; then
  echo "usage: $0 <case-id> [--keep-runtime]" >&2
  exit 1
fi

require_case "${case_id}"

trace="$(read_case_field "${case_id}" trace)"
title="$(read_case_field "${case_id}" task_title)"
bee="$(read_case_field "${case_id}" task_bee)"
intent="$(read_case_field "${case_id}" task_intent)"
review="$(read_case_field "${case_id}" task_review)"
timeout_raw="$(read_case_field "${case_id}" timeout)"
timeout_secs="$(timeout_seconds "${timeout_raw}")"
task_body_file="$(case_dir_for "${case_id}")/task.body"

if [[ -z "${title}" ]]; then
  echo "case ${case_id}: task.title missing in case.yaml" >&2
  exit 1
fi
if [[ ! -f "${task_body_file}" ]]; then
  echo "case ${case_id}: missing ${task_body_file}" >&2
  exit 1
fi

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
wall_start=$(date +%s)

reset_case "${case_id}"
ensure_nats
ensure_runtime

echo "creating task on trace ${trace}..."
paseka task create \
  --trace "${trace}" \
  --title "${title}" \
  --file "${task_body_file}" \
  --bee "${bee}" \
  --intent "${intent}" \
  --review "${review}" \
  --autorun \
  -C "${EVAL_ROOT}"

echo "waiting for terminal task status (timeout ${timeout_secs}s)..."
task_status="$(wait_for_terminal_task "${trace}" "${timeout_secs}")" || {
  task_status="timeout"
}

oracle_ok=false
if [[ "${task_status}" == "completed" ]]; then
  if run_oracle "${case_id}" "${trace}"; then
    oracle_ok=true
  fi
else
  echo "task did not complete successfully (status=${task_status})" >&2
fi

replay_out="$(collect_replay_lines "${trace}")"
wall_end=$(date +%s)
duration=$(( wall_end - wall_start ))

mkdir -p "${REPORTS_DIR}"
report_file="${REPORTS_DIR}/${case_id}-$(date -u +%Y%m%dT%H%M%SZ).json"

python3 - "${report_file}" <<PY
import json
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
replay = """${replay_out}"""
passed = ${oracle_ok} and "${task_status}" == "completed"

report = {
    "case_id": "${case_id}",
    "trace": "${trace}",
    "seed_sha": pathlib.Path("${EVAL_META_DIR}/seed-sha").read_text().strip(),
    "started_at": "${started_at}",
    "duration_sec": ${duration},
    "task_status": "${task_status}",
    "tests_passed": ${oracle_ok},
    "passed": passed,
    "replay": [line for line in replay.splitlines() if line.strip()],
}
report_path.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
PY

echo ""
echo "report: ${report_file}"
echo "replay:"
echo "${replay_out}"

if [[ "${keep_runtime}" != "true" ]]; then
  stop_runtime
fi

if [[ "${task_status}" == "completed" && "${oracle_ok}" == "true" ]]; then
  exit 0
fi
exit 1
