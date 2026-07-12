#!/usr/bin/env bash
# Shared helpers for eval colony runner scripts.
set -euo pipefail

EVAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVAL_META_DIR="${EVAL_ROOT}/.eval"
REPORTS_DIR="${EVAL_ROOT}/reports"

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
else:
    raise SystemExit(f"unknown field: {field}")
PY
)
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
  paseka purge --runs --worktrees --state --yes -C "${EVAL_ROOT}"
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

reset_case() {
  local case_id="$1"
  require_case "$case_id"
  local trace_id
  trace_id="$(read_case_field "$case_id" trace)"
  purge_colony
  clear_trace_ledger "${trace_id}"
  materialize_seed "$case_id"
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

clear_trace_ledger() {
  local trace_id="$1"
  local bucket="paseka_paseka_eval_colony_task_ledger"
  if command -v nats >/dev/null 2>&1; then
    nats kv del "${bucket}" "${trace_id}" >/dev/null 2>&1 || true
    return 0
  fi

  local compose="${EVAL_ROOT}/../paseka/docker-compose.yml"
  if [[ -f "${compose}" ]]; then
    echo "resetting NATS JetStream state (no nats CLI)..."
    docker compose -f "${compose}" stop nats >/dev/null 2>&1 || true
    docker volume rm paseka_nats-data >/dev/null 2>&1 || true
    docker compose -f "${compose}" up -d nats >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
      if paseka doctor -C "${EVAL_ROOT}" >/dev/null 2>&1; then
        return 0
      fi
      sleep 1
    done
  fi
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

collect_replay_lines() {
  local trace_id="$1"
  paseka replay "${trace_id}" -C "${EVAL_ROOT}" 2>/dev/null
}
