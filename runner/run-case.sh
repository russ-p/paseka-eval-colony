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
must_pass_tests="$(read_case_field "${case_id}" score_must_pass_tests)"
expect_task_status="$(read_case_field "${case_id}" score_expect_task_status)"
task_body_file="$(case_dir_for "${case_id}")/task.body"

if [[ -z "${title}" ]]; then
  echo "case ${case_id}: task.title missing in case.yaml" >&2
  exit 1
fi
if [[ ! -f "${task_body_file}" ]]; then
  echo "case ${case_id}: missing ${task_body_file}" >&2
  exit 1
fi

cleanup() {
  restore_colony_config
  if [[ "${keep_runtime}" != "true" ]]; then
    stop_runtime
  fi
}
trap cleanup EXIT

started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
wall_start=$(date +%s)

reset_case "${case_id}"
ensure_nats
ensure_runtime

echo "creating task on trace ${trace}..."
create_out="$(
  paseka task create \
    --trace "${trace}" \
    --title "${title}" \
    --file "${task_body_file}" \
    --bee "${bee}" \
    --intent "${intent}" \
    --review "${review}" \
    --autorun \
    -C "${EVAL_ROOT}" 2>&1
)"
echo "${create_out}"
task_id="$(echo "${create_out}" | awk '/^  task:/{print $2}')"
if [[ -z "${task_id}" ]]; then
  echo "failed to parse task id from paseka task create output" >&2
  exit 1
fi

echo "waiting for hive loop + oracle (timeout ${timeout_secs}s)..."
if [[ "${must_pass_tests}" == "false" && -n "${expect_task_status}" ]]; then
  task_status="$(wait_for_expected_task_status "${trace}" "${task_id}" "${expect_task_status}" "${timeout_secs}")" || true
else
  task_status="$(wait_for_terminal_task "${trace}" "${task_id}" "${timeout_secs}")" || true
fi

oracle_ok=false
if [[ "${must_pass_tests}" == "false" ]]; then
  if check_energy_exhaustion_oracle "${case_id}" "${trace}" "${task_id}"; then
    oracle_ok=true
  fi
else
  if wait_for_oracle "${case_id}" "${trace}" "${timeout_secs}"; then
    oracle_ok=true
  fi
fi

replay_out="$(collect_replay_lines "${trace}")"
wall_end=$(date +%s)
duration=$(( wall_end - wall_start ))

passed=false
if [[ "${must_pass_tests}" == "false" ]]; then
  if [[ "${oracle_ok}" == "true" && "${task_status}" == "${expect_task_status}" ]]; then
    passed=true
  fi
else
  if [[ "${oracle_ok}" == "true" ]]; then
    passed=true
  fi
fi

mkdir -p "${REPORTS_DIR}"
report_file="${REPORTS_DIR}/${case_id}-$(date -u +%Y%m%dT%H%M%SZ).json"

REPORT_CASE_ID="${case_id}" \
REPORT_TRACE="${trace}" \
REPORT_TASK_ID="${task_id}" \
REPORT_SEED_SHA="${EVAL_META_DIR}/seed-sha" \
REPORT_STARTED_AT="${started_at}" \
REPORT_DURATION="${duration}" \
REPORT_TASK_STATUS="${task_status}" \
REPORT_TESTS_PASSED="${oracle_ok}" \
REPORT_PASSED="${passed}" \
REPORT_REPLAY="${replay_out}" \
python3 - "${report_file}" <<'PY'
import json
import os
import pathlib
import sys

report_path = pathlib.Path(sys.argv[1])
replay = os.environ.get("REPORT_REPLAY", "")

def as_bool(name: str) -> bool:
    return os.environ.get(name, "false").lower() == "true"

report = {
    "case_id": os.environ["REPORT_CASE_ID"],
    "trace": os.environ["REPORT_TRACE"],
    "task_id": os.environ["REPORT_TASK_ID"],
    "seed_sha": pathlib.Path(os.environ["REPORT_SEED_SHA"]).read_text().strip(),
    "started_at": os.environ["REPORT_STARTED_AT"],
    "duration_sec": int(os.environ["REPORT_DURATION"]),
    "task_status": os.environ["REPORT_TASK_STATUS"],
    "tests_passed": as_bool("REPORT_TESTS_PASSED"),
    "passed": as_bool("REPORT_PASSED"),
    "replay": [line for line in replay.splitlines() if line.strip()],
}
report_path.write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
PY

echo ""
echo "report: ${report_file}"
echo "replay:"
echo "${replay_out}"

if [[ "${passed}" == "true" ]]; then
  exit 0
fi
exit 1
