#!/usr/bin/env bash
# Shared helpers for eval colony runner scripts.
set -euo pipefail

EVAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVAL_META_DIR="${EVAL_ROOT}/.eval"
REPORTS_DIR="${EVAL_ROOT}/reports"
COLONY_CONFIG="${EVAL_ROOT}/.paseka/colony.yaml"
COLONY_CONFIG_BACKUP="${EVAL_META_DIR}/colony.yaml.bak"

case_dir_for() {
  local case_id="$1"
  echo "${EVAL_ROOT}/cases/${case_id}"
}

require_case() {
  local case_id="$1"
  local case_dir
  case_dir="$(case_dir_for "$case_id")"
  if [[ ! -f "${case_dir}/case.yaml" ]]; then
    echo "case not found: ${case_id} (expected ${case_dir}/case.yaml)" >&2
    exit 1
  fi
}

read_case_field() {
  local case_id="$1"
  local field="$2"
  (cd "${EVAL_ROOT}" && python3 - "$case_id" "$field" <<'PY'
import pathlib
import re
import sys

case_id, field = sys.argv[1], sys.argv[2]
path = pathlib.Path("cases") / case_id / "case.yaml"
text = path.read_text()

def scalar(key: str) -> str:
    m = re.search(rf"^{re.escape(key)}:\s*(.+)$", text, re.M)
    return m.group(1).strip().strip('"').strip("'") if m else ""

def nested(parent: str, key: str) -> str:
    block = re.search(
        rf"^{re.escape(parent)}:\s*\n((?:  .*\n?)*)",
        text,
        re.M,
    )
    if not block:
        return ""
    body = block.group(1)
    m = re.search(rf"^\s+{re.escape(key)}:\s*(.+)$", body, re.M)
    if not m:
        return ""
    return m.group(1).strip().strip('"').strip("'")

if field == "trace":
    print(scalar("trace"))
elif field == "seed":
    print(scalar("seed") or "seed/")
elif field == "timeout":
    print(scalar("timeout") or "10m")
elif field == "oracle_command":
    print(nested("oracle", "command") or "go test ./...")
elif field == "oracle_workdir":
    print(nested("oracle", "workdir") or ".")
elif field == "task_title":
    print(nested("task", "title"))
elif field == "task_bee":
    print(nested("task", "bee") or "builder")
elif field == "task_intent":
    print(nested("task", "intent") or "test-fix")
elif field == "task_review":
    print(nested("task", "review") or "none")
elif field == "fault_mode":
    print(nested("fault", "mode") or "scripted")
elif field == "fault_broken_diff":
    print(nested("fault", "broken_diff") or "")
elif field == "energy_budget":
    print(nested("energy", "budget") or "")
elif field == "energy_topup":
    val = nested("energy", "topup")
    print(val if val != "" else "24")
elif field == "score_must_pass_tests":
    val = nested("score", "must_pass_tests")
    print(val if val != "" else "true")
elif field == "score_expect_task_status":
    print(nested("score", "expect_task_status") or "")
elif field == "score_expect_summary":
    print(nested("score", "expect_summary") or "")
else:
    raise SystemExit(f"unknown field: {field}")
PY
)
}

read_case_event_chain_json() {
  local case_id="$1"
  (cd "${EVAL_ROOT}" && python3 - "$case_id" <<'PY'
import json
import pathlib
import re
import sys

case_id = sys.argv[1]
text = (pathlib.Path("cases") / case_id / "case.yaml").read_text()
block = re.search(r"^oracle:\s*\n((?:  .*\n?)*)", text, re.M)
chain = []
if block:
    for m in re.finditer(
        r"^\s+- type:\s*(\S+)\s*\n\s+kind:\s*(\S+)\s*$",
        block.group(1),
        re.M,
    ):
        chain.append({"type": m.group(1), "kind": m.group(2)})
print(json.dumps(chain))
PY
)
}

check_replay_event_chain() {
  local case_id="$1"
  local replay_out="$2"
  local chain_json
  chain_json="$(read_case_event_chain_json "${case_id}")"
  REPLAY_TEXT="${replay_out}" EXPECTED_CHAIN="${chain_json}" python3 - <<'PY'
import json
import os
import re
import sys

expected = json.loads(os.environ.get("EXPECTED_CHAIN", "[]"))
if not expected:
    sys.exit(0)

replay = os.environ.get("REPLAY_TEXT", "")
actual = []
for line in replay.splitlines():
    m = re.match(r"^\s*\d+\.\s+(\S+)\s+\(([^)]+)\)", line)
    if m:
        actual.append({"type": m.group(1), "kind": m.group(2)})

idx = 0
for item in expected:
    while idx < len(actual):
        if actual[idx] == item:
            idx += 1
            break
        idx += 1
    else:
        print(
            f"event chain: missing {item['type']}/{item['kind']} "
            f"(expected subsequence of {len(expected)} step(s), got {len(actual)} replay event(s))",
            file=sys.stderr,
        )
        sys.exit(1)
sys.exit(0)
PY
}

timeout_seconds() {
  local raw="$1"
  if [[ "${raw}" =~ ^([0-9]+)m$ ]]; then
    echo $(( ${BASH_REMATCH[1]} * 60 ))
  elif [[ "${raw}" =~ ^([0-9]+)s$ ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo 600
  fi
}

purge_colony() {
  local trace_id="$1"
  # --reseed-energy restores honey to colony defaults.energy_budget after bus wipe
  # (see paseka backlog "Trace reset helper"). Apply case budget overrides before calling.
  paseka purge --runs --worktrees --state --bus --trace "${trace_id}" --reseed-energy --yes -C "${EVAL_ROOT}"
  git -C "${EVAL_ROOT}" worktree prune >/dev/null 2>&1 || true
  while IFS= read -r branch; do
    [[ -z "${branch}" ]] && continue
    git -C "${EVAL_ROOT}" branch -D "${branch}" >/dev/null 2>&1 || true
  done < <(git -C "${EVAL_ROOT}" branch --list 'paseka/eval-*' | sed 's/^[* ] //')
}

materialize_seed() {
  local case_id="$1"
  local case_dir seed_rel seed_dir
  case_dir="$(case_dir_for "$case_id")"
  seed_rel="$(read_case_field "$case_id" seed)"
  seed_dir="${case_dir}/${seed_rel}"

  rm -rf "${EVAL_ROOT}/pkg" "${EVAL_ROOT}/go.mod" "${EVAL_ROOT}/go.sum"
  rsync -a "${seed_dir}/" "${EVAL_ROOT}/"

  mkdir -p "${EVAL_META_DIR}"
  echo "${case_id}" > "${EVAL_META_DIR}/case-id"
  echo "${case_dir}" > "${EVAL_META_DIR}/case-dir"
  echo "0" > "${EVAL_META_DIR}/builder-runs"
  echo "$(read_case_field "$case_id" trace)" > "${EVAL_META_DIR}/trace"

  git -C "${EVAL_ROOT}" add go.mod pkg 2>/dev/null || true
  if ! git -C "${EVAL_ROOT}" rev-parse HEAD >/dev/null 2>&1; then
    git -C "${EVAL_ROOT}" add .gitignore README.md cases scripts runner .paseka
    git -C "${EVAL_ROOT}" commit -m "eval colony skeleton"
  fi
  if ! git -C "${EVAL_ROOT}" diff --cached --quiet; then
    git -C "${EVAL_ROOT}" commit -m "eval seed: ${case_id}"
  fi
  git -C "${EVAL_ROOT}" rev-parse HEAD > "${EVAL_META_DIR}/seed-sha"
}

set_colony_energy_budget() {
  local budget="$1"
  mkdir -p "${EVAL_META_DIR}"
  if [[ ! -f "${COLONY_CONFIG_BACKUP}" ]]; then
    cp "${COLONY_CONFIG}" "${COLONY_CONFIG_BACKUP}"
  fi
  python3 - "${budget}" "${COLONY_CONFIG}" <<'PY'
import pathlib
import re
import sys

budget = int(sys.argv[1])
path = pathlib.Path(sys.argv[2])
text = path.read_text()
if re.search(r"^\s+energy_budget:\s*\d+\s*$", text, re.M):
    text = re.sub(
        r"^(\s+energy_budget:)\s*\d+\s*$",
        rf"\g<1> {budget}",
        text,
        count=1,
        flags=re.M,
    )
else:
    text = re.sub(
        r"^(defaults:\s*\n)",
        rf"\1  energy_budget: {budget}\n",
        text,
        count=1,
        flags=re.M,
    )
path.write_text(text)
PY
}

restore_colony_config() {
  if [[ -f "${COLONY_CONFIG_BACKUP}" ]]; then
    cp "${COLONY_CONFIG_BACKUP}" "${COLONY_CONFIG}"
    rm -f "${COLONY_CONFIG_BACKUP}"
  fi
}

reset_case() {
  local case_id="$1"
  require_case "$case_id"
  local trace_id fault_mode energy_budget energy_topup
  trace_id="$(read_case_field "$case_id" trace)"
  fault_mode="$(read_case_field "$case_id" fault_mode)"
  energy_budget="$(read_case_field "$case_id" energy_budget)"
  energy_topup="$(read_case_field "$case_id" energy_topup)"
  stop_runtime
  # Case energy_budget must be on colony.yaml before purge --reseed-energy.
  restore_colony_config
  if [[ -n "${energy_budget}" ]]; then
    set_colony_energy_budget "${energy_budget}"
  fi
  purge_colony "${trace_id}"
  materialize_seed "$case_id"
  echo "${fault_mode}" > "${EVAL_META_DIR}/fault-mode"
  if [[ "${energy_topup}" =~ ^[0-9]+$ ]] && (( energy_topup > 0 )); then
    paseka energy add --trace "${trace_id}" --amount "${energy_topup}" -C "${EVAL_ROOT}" >/dev/null 2>&1 || true
  fi
  echo "reset case ${case_id} at seed $(cat "${EVAL_META_DIR}/seed-sha")"
}

ensure_nats() {
  if paseka doctor -C "${EVAL_ROOT}" >/dev/null 2>&1; then
    return 0
  fi
  local compose="${EVAL_ROOT}/../paseka/docker-compose.yml"
  if [[ -f "${compose}" ]]; then
    echo "starting NATS via docker compose..."
    docker compose -f "${compose}" up -d nats
    for _ in $(seq 1 30); do
      if paseka doctor -C "${EVAL_ROOT}" >/dev/null 2>&1; then
        return 0
      fi
      sleep 1
    done
  fi
  echo "NATS is not reachable; run paseka doctor for details" >&2
  return 1
}

runtime_pid_file() {
  echo "${EVAL_META_DIR}/paseka-run.pid"
}

ensure_runtime() {
  mkdir -p "${EVAL_META_DIR}"
  stop_runtime
  local pid_file
  pid_file="$(runtime_pid_file)"
  echo "starting paseka run..."
  (cd "${EVAL_ROOT}" && nohup paseka run -C "${EVAL_ROOT}" > "${EVAL_META_DIR}/paseka-run.log" 2>&1 & echo $! > "${pid_file}")
  sleep 2
}

stop_runtime() {
  local pid_file
  pid_file="$(runtime_pid_file)"
  pkill -f "paseka run.*paseka-eval-colony" >/dev/null 2>&1 || true
  [[ -f "${pid_file}" ]] || return 0
  local pid
  pid="$(cat "${pid_file}")"
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill "${pid}" >/dev/null 2>&1 || true
    wait "${pid}" 2>/dev/null || true
  fi
  rm -f "${pid_file}"
}

wait_for_expected_task_status() {
  local trace_id="$1"
  local task_id="$2"
  local expect_status="$3"
  local timeout_secs="$4"
  local start now status
  start=$(date +%s)
  while true; do
    status="$(
      paseka task list --trace "${trace_id}" -C "${EVAL_ROOT}" 2>/dev/null \
        | awk -v id="${task_id}" '$1 == id { print $2; found=1 } END { if (!found) print "" }'
    )"
    if [[ -z "${status}" ]]; then
      status="missing"
    fi
    if [[ "${status}" == "${expect_status}" ]]; then
      echo "${status}"
      return 0
    fi
    now=$(date +%s)
    if (( now - start >= timeout_secs )); then
      echo "${status}"
      return 1
    fi
    sleep 2
  done
}

wait_for_success_scoring() {
  local case_id="$1"
  local trace_id="$2"
  local task_id="$3"
  local expect_status="$4"
  local timeout_secs="$5"
  local start now status
  start=$(date +%s)
  while true; do
    status="$(task_show_field "${trace_id}" "${task_id}" status)"
    if [[ -z "${status}" ]]; then
      status="missing"
    fi
    if [[ "${status}" == "${expect_status}" ]]; then
      if run_oracle "${case_id}" "${trace_id}" >/dev/null; then
        echo "${status}"
        return 0
      fi
    fi
    now=$(date +%s)
    if (( now - start >= timeout_secs )); then
      echo "${status}"
      return 1
    fi
    sleep 3
  done
}

wait_for_terminal_task() {
  local trace_id="$1"
  local task_id="$2"
  local timeout_secs="$3"
  local start now status last_status unchanged_since
  start=$(date +%s)
  unchanged_since="${start}"
  last_status=""
  while true; do
    status="$(
      paseka task list --trace "${trace_id}" -C "${EVAL_ROOT}" 2>/dev/null \
        | awk -v id="${task_id}" '$1 == id { print $2; found=1 } END { if (!found) print "" }'
    )"
    if [[ -z "${status}" ]]; then
      status="missing"
    fi
    if [[ "${status}" != "${last_status}" ]]; then
      last_status="${status}"
      unchanged_since=$(date +%s)
    fi
    case "${status}" in
      completed|failed|blocked|waiting_review)
        echo "${status}"
        return 0
        ;;
      running)
        if (( $(date +%s) - unchanged_since >= 180 )); then
          echo "stuck_running"
          return 1
        fi
        ;;
    esac
    now=$(date +%s)
    if (( now - start >= timeout_secs )); then
      echo "timeout"
      return 1
    fi
    sleep 2
  done
}

worktree_for_trace() {
  local trace_id="$1"
  echo "${EVAL_ROOT}/.paseka/worktrees/${trace_id}"
}

run_oracle() {
  local case_id="$1"
  local trace_id="$2"
  local cmd workdir dir
  cmd="$(read_case_field "$case_id" oracle_command)"
  workdir="$(read_case_field "$case_id" oracle_workdir)"
  dir="$(worktree_for_trace "${trace_id}")"
  if [[ ! -d "${dir}" ]]; then
    dir="${EVAL_ROOT}"
  fi
  if [[ "${workdir}" != "." ]]; then
    dir="${dir}/${workdir}"
  fi
  (cd "${dir}" && bash -lc "${cmd}")
}

wait_for_oracle() {
  local case_id="$1"
  local trace_id="$2"
  local timeout_secs="$3"
  local start
  start=$(date +%s)
  while true; do
    if run_oracle "${case_id}" "${trace_id}"; then
      return 0
    fi
    if (( $(date +%s) - start >= timeout_secs )); then
      return 1
    fi
    sleep 3
  done
}

collect_replay_lines() {
  local trace_id="$1"
  paseka replay "${trace_id}" -C "${EVAL_ROOT}" 2>/dev/null
}

energy_show_field() {
  local trace_id="$1"
  local field="$2"
  paseka energy show --trace "${trace_id}" -C "${EVAL_ROOT}" 2>/dev/null \
    | awk -v key="${field}" '
      $1 == "budget:" && key == "budget" { print $2; found=1 }
      $1 == "remaining:" && key == "remaining" { print $2; found=1 }
      END { if (!found) print "" }
    '
}

task_show_field() {
  local trace_id="$1"
  local task_id="$2"
  local field="$3"
  paseka task show --trace "${trace_id}" --task "${task_id}" -C "${EVAL_ROOT}" 2>/dev/null \
    | awk -v key="${field}" '
      $1 == "status:" && key == "status" { print $2; found=1 }
      $1 == "summary:" && key == "summary" {
        sub(/^  summary:[[:space:]]*/, "")
        print $0
        found=1
      }
      END { if (!found) print "" }
    '
}

check_energy_exhaustion_oracle() {
  local case_id="$1"
  local trace_id="$2"
  local task_id="$3"
  local expect_status expect_summary energy_budget remaining status summary
  expect_status="$(read_case_field "$case_id" score_expect_task_status)"
  expect_summary="$(read_case_field "$case_id" score_expect_summary)"
  energy_budget="$(read_case_field "$case_id" energy_budget)"

  remaining="$(energy_show_field "${trace_id}" remaining)"
  status="$(task_show_field "${trace_id}" "${task_id}" status)"
  summary="$(task_show_field "${trace_id}" "${task_id}" summary)"

  if [[ "${remaining}" != "0" ]]; then
    echo "energy oracle: remaining=${remaining}, want 0" >&2
    return 1
  fi
  if [[ -n "${energy_budget}" && "${energy_budget}" != "$(energy_show_field "${trace_id}" budget)" ]]; then
    echo "energy oracle: budget mismatch" >&2
    return 1
  fi
  if [[ -n "${expect_status}" && "${status}" != "${expect_status}" ]]; then
    echo "energy oracle: status=${status}, want ${expect_status}" >&2
    return 1
  fi
  if [[ -n "${expect_summary}" && "${summary}" != "${expect_summary}" ]]; then
    echo "energy oracle: summary=${summary@Q}, want ${expect_summary@Q}" >&2
    return 1
  fi
  return 0
}
