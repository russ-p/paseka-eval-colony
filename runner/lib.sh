#!/usr/bin/env bash
# Shared helpers for eval colony runner scripts.
set -euo pipefail

EVAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVAL_META_DIR="${EVAL_ROOT}/.eval"
REPORTS_DIR="${EVAL_ROOT}/reports"
COLONY_CONFIG="${EVAL_ROOT}/.paseka/colony.yaml"
COLONY_CONFIG_BACKUP="${EVAL_META_DIR}/colony.yaml.bak"
BUILDER_BEE="${EVAL_ROOT}/.paseka/bees/builder.yaml"
BUILDER_BEE_BACKUP="${EVAL_META_DIR}/builder.yaml.bak"

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
elif field == "task_id":
    print(nested("task", "id"))
elif field == "task_title":
    print(nested("task", "title"))
elif field == "task_bee":
    print(nested("task", "bee") or "builder")
elif field == "task_intent":
    print(nested("task", "intent") or "test-fix")
elif field == "task_review":
    print(nested("task", "review") or "none")
elif field == "ingress_mode":
    print(nested("ingress", "mode") or "task")
elif field == "ingress_cue_id":
    print(nested("ingress", "id") or "")
elif field == "standing_ticks":
    print(nested("standing", "ticks") or "")
elif field == "standing_stipend":
    print(nested("standing", "stipend") or "")
elif field == "standing_overlap":
    print(nested("standing", "overlap") or "")
elif field == "standing_topup":
    print(nested("standing", "topup") or "")
elif field == "operator_watcher_hold_secs":
    print(nested("operator", "watcher_hold_secs") or "")
elif field == "operator_review_comments_file":
    print(nested("operator", "review_comments_file") or "")
elif field == "score_expect_rework_task":
    print(nested("score", "expect_rework_task") or "")
elif field == "score_expect_bee":
    print(nested("score", "expect_bee") or "")
elif field == "score_expect_intent":
    print(nested("score", "expect_intent") or "")
elif field == "score_expect_energy_budget_lte":
    print(nested("score", "expect_energy_budget_lte") or "")
elif field == "score_expect_scout_run":
    print(nested("score", "expect_scout_run") or "")
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
elif field == "score_expect_trace_killed":
    print(nested("score", "expect_trace_killed") or "")
elif field == "score_expect_energy_remaining_gt":
    print(nested("score", "expect_energy_remaining_gt") or "")
elif field == "operator_kill_after":
    print(nested("operator", "kill_after") or "")
elif field == "operator_kill_reason":
    print(nested("operator", "reason") or "")
elif field == "operator_builder_hold_secs":
    print(nested("operator", "builder_hold_secs") or "")
elif field == "operator_energy_add_after_kill":
    print(nested("operator", "energy_add_after_kill") or "")
elif field == "operator_settle_secs":
    print(nested("operator", "settle_secs") or "")
elif field == "score_expect_no_redispatch":
    print(nested("score", "expect_no_redispatch") or "")
elif field == "operator_reject_when":
    print(nested("operator", "reject_when") or "")
elif field == "operator_reject_feedback":
    print(nested("operator", "feedback") or "")
elif field == "operator_approve_when":
    print(nested("operator", "approve_when") or "")
elif field == "operator_approve_summary":
    print(nested("operator", "summary") or "")
elif field == "score_expect_artifact_written_count":
    print(nested("score", "expect_artifact_written_count") or "")
elif field == "score_expect_artifact_prompt":
    print(nested("score", "expect_artifact_prompt") or "")
elif field == "score_expect_artifact_export":
    print(nested("score", "expect_artifact_export") or "")
elif field == "score_expect_artifact_handoff":
    print(nested("score", "expect_artifact_handoff") or "")
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
  local reseed="${2:-true}"
  local purge_args=(
    purge --runs --worktrees --state --bus --trace "${trace_id}" --yes -C "${EVAL_ROOT}"
  )
  # --reseed-energy restores honey to colony defaults.energy_budget after bus wipe
  # (see paseka backlog "Trace reset helper"). Apply case budget overrides before calling.
  # Cue ingress cases skip reseed so cue run can seed its own energy_budget.
  if [[ "${reseed}" == "true" ]]; then
    purge_args+=(--reseed-energy)
  fi
  paseka "${purge_args[@]}"
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
  echo "0" > "${EVAL_META_DIR}/scout-runs"
  echo "0" > "${EVAL_META_DIR}/watcher-runs"
  echo "$(read_case_field "$case_id" trace)" > "${EVAL_META_DIR}/trace"
  # Script receiver reads this to skip auto-complete for HITL review gates.
  echo "$(read_case_field "$case_id" task_review)" > "${EVAL_META_DIR}/task-review"

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
  restore_builder_bee
}

# enable_builder_run_summary lets 015 assert flush-before-run.summary on success.
# Also points command at colony-root scripts/ so uncommitted builder.sh is visible
# (worktrees checkout HEAD; relative ./scripts would miss local edits).
# Registry is built at `paseka run` start — call before ensure_runtime.
enable_builder_run_summary() {
  mkdir -p "${EVAL_META_DIR}"
  if [[ ! -f "${BUILDER_BEE_BACKUP}" ]]; then
    cp "${BUILDER_BEE}" "${BUILDER_BEE_BACKUP}"
  fi
  python3 - "${BUILDER_BEE}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = text.replace("run_summary: disabled", "run_summary: auto", 1)
text = text.replace(
    "command: ./scripts/builder.sh",
    "command: ${COLONY_ROOT}/scripts/builder.sh",
    1,
)
if "kind: run.summary" not in text:
    needle = "  - type: MUTATION\n    kind: code.proposal.isolated\n"
    insert = needle + "  - type: INSIGHT\n    kind: run.summary\n"
    if needle not in text:
        raise SystemExit("builder.yaml: expected code.proposal.isolated publish rule")
    text = text.replace(needle, insert, 1)
path.write_text(text)
PY
}

# enable_builder_artifact_subscribe adds artifact.written direct dispatch for case 14.
enable_builder_artifact_subscribe() {
  mkdir -p "${EVAL_META_DIR}"
  if [[ ! -f "${BUILDER_BEE_BACKUP}" ]]; then
    cp "${BUILDER_BEE}" "${BUILDER_BEE_BACKUP}"
  fi
  python3 - "${BUILDER_BEE}" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = text.replace(
    "command: ./scripts/builder.sh",
    "command: ${COLONY_ROOT}/scripts/builder.sh",
    1,
)
subscribe = """  - type: SIGNAL
    kind: artifact.written
    dispatch: direct
"""
if "kind: artifact.written" not in text:
    needle = "  - type: VERIFICATION\n    kind: verification.failed\n    dispatch: direct\n"
    if needle not in text:
        raise SystemExit("builder.yaml: expected verification.failed subscribe")
    text = text.replace(needle, needle + subscribe, 1)
path.write_text(text)
PY
}

restore_builder_bee() {
  if [[ -f "${BUILDER_BEE_BACKUP}" ]]; then
    cp "${BUILDER_BEE_BACKUP}" "${BUILDER_BEE}"
    rm -f "${BUILDER_BEE_BACKUP}"
  fi
}

reset_case() {
  local case_id="$1"
  require_case "$case_id"
  local trace_id fault_mode energy_budget energy_topup ingress_mode
  local hold_secs kill_after watcher_hold_secs
  trace_id="$(read_case_field "$case_id" trace)"
  fault_mode="$(read_case_field "$case_id" fault_mode)"
  energy_budget="$(read_case_field "$case_id" energy_budget)"
  energy_topup="$(read_case_field "$case_id" energy_topup)"
  ingress_mode="$(read_case_field "$case_id" ingress_mode)"
  stop_runtime
  # Case energy_budget must be on colony.yaml before purge --reseed-energy.
  restore_colony_config
  if [[ -n "${energy_budget}" && "${ingress_mode}" != "cue" ]]; then
    set_colony_energy_budget "${energy_budget}"
  fi
  if [[ "${fault_mode}" == "deferred_emit" || "${fault_mode}" == "deferred_artifact" ]]; then
    enable_builder_run_summary
  fi
  if [[ "${fault_mode}" == "write_comb" && "${ingress_mode}" == "cue" ]]; then
    enable_builder_artifact_subscribe
    touch "${EVAL_META_DIR}/artifact-handoff"
  else
    rm -f "${EVAL_META_DIR}/artifact-handoff"
  fi
  if [[ "${ingress_mode}" == "cue" ]]; then
    purge_colony "${trace_id}" false
  else
    purge_colony "${trace_id}" true
  fi
  materialize_seed "$case_id"
  echo "${fault_mode}" > "${EVAL_META_DIR}/fault-mode"
  # Kill cases need an in-flight adapter window; default 30s when kill_after is set.
  hold_secs="$(read_case_field "$case_id" operator_builder_hold_secs)"
  kill_after="$(read_case_field "$case_id" operator_kill_after)"
  watcher_hold_secs="$(read_case_field "$case_id" operator_watcher_hold_secs)"
  if [[ -z "${hold_secs}" && -n "${kill_after}" ]]; then
    hold_secs=30
  fi
  if [[ "${hold_secs}" =~ ^[0-9]+$ ]] && (( hold_secs > 0 )); then
    echo "${hold_secs}" > "${EVAL_META_DIR}/builder-hold-secs"
  else
    rm -f "${EVAL_META_DIR}/builder-hold-secs"
  fi
  if [[ "${watcher_hold_secs}" =~ ^[0-9]+$ ]] && (( watcher_hold_secs > 0 )); then
    echo "${watcher_hold_secs}" > "${EVAL_META_DIR}/watcher-hold-secs"
  else
    rm -f "${EVAL_META_DIR}/watcher-hold-secs"
  fi
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
      completed|failed|blocked|waiting_review|cancelled)
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

commit_trace_worktree() {
  local trace_id="$1"
  local message="$2"
  local worktree
  worktree="$(worktree_for_trace "${trace_id}")"
  if [[ ! -d "${worktree}" ]]; then
    echo "worktree commit: missing ${worktree}" >&2
    return 1
  fi
  git -C "${worktree}" add -A
  if git -C "${worktree}" diff --cached --quiet; then
    echo "worktree commit: no changes for ${trace_id}"
    return 0
  fi
  git -C "${worktree}" commit --no-verify -m "${message}" >/dev/null
  echo "worktree commit: ${trace_id} ${message}"
  return 0
}

# ensure_inject_worktree creates the platform worktree path and applies broken/
# so guard sees bad code on disk when the runner signals MUTATION.
ensure_inject_worktree() {
  local case_id="$1"
  local trace_id="$2"
  local case_dir wt branch
  case_dir="$(case_dir_for "${case_id}")"
  wt="$(worktree_for_trace "${trace_id}")"
  branch="paseka/${trace_id}"

  mkdir -p "$(dirname "${wt}")"
  if [[ ! -d "${wt}" ]]; then
    echo "creating inject worktree at ${wt}..."
    if ! git -C "${EVAL_ROOT}" worktree add -b "${branch}" "${wt}" HEAD; then
      # Branch may linger after a partial reset; attach without -b.
      git -C "${EVAL_ROOT}" worktree add "${wt}" "${branch}" 2>/dev/null \
        || git -C "${EVAL_ROOT}" worktree add "${wt}" HEAD
    fi
  fi

  if [[ -d "${case_dir}/broken/pkg" ]]; then
    rsync -a "${case_dir}/broken/pkg/" "${wt}/pkg/"
    echo "applied broken/ into inject worktree"
  elif [[ -f "${case_dir}/broken/bad.patch" ]]; then
    (cd "${wt}" && patch -p1 < "${case_dir}/broken/bad.patch")
    echo "applied broken patch into inject worktree"
  else
    echo "inject-mutation: missing broken/ fixture in ${case_dir}" >&2
    return 1
  fi
}

publish_injected_mutation() {
  local trace_id="$1"
  local task_id="$2"
  local payload
  payload="$(printf '{"kind":"code.proposal.isolated","taskId":"%s","summary":"injected broken proposal"}' "${task_id}")"
  echo "publishing injected MUTATION/code.proposal.isolated for task ${task_id}..."
  paseka signal \
    --type MUTATION \
    --trace "${trace_id}" \
    --payload "${payload}" \
    -C "${EVAL_ROOT}"
}

# probe_deferred_fail_discard: one-shot builder exits 1 after --defer; pending stays
# off the bus; flush --discard clears the queue (015 fail path / US 25 companion).
probe_deferred_fail_discard() {
  local trace_id="$1"
  local bee_out agent pending_json flush_out replay_out
  local fail_summary="eval-08 deferred fail probe"

  echo "deferred emit fail probe: bee run builder (exit 1 after --defer)..."
  echo "deferred_fail" > "${EVAL_META_DIR}/fault-mode"
  set +e
  bee_out="$(paseka bee run builder --trace "${trace_id}" --body "${fail_summary}" -C "${EVAL_ROOT}" 2>&1)"
  set -e
  echo "${bee_out}"
  agent="$(echo "${bee_out}" | awk '/^  agent:/{print $2; exit}')"
  if [[ -z "${agent}" ]]; then
    echo "deferred fail probe: failed to parse agent id from bee run output" >&2
    echo "deferred_emit" > "${EVAL_META_DIR}/fault-mode"
    return 1
  fi

  pending_json="$(paseka event pending --trace "${trace_id}" --agent "${agent}" -C "${EVAL_ROOT}")"
  echo "pending after fail: ${pending_json}"
  if ! PENDING_JSON="${pending_json}" python3 - <<'PY'
import json, os, sys
p = json.loads(os.environ["PENDING_JSON"])
if not p.get("ok") or p.get("count") != 1 or "context.note" not in p.get("kinds", []):
    print(f"want pending count=1 kinds=[context.note], got {p}", file=sys.stderr)
    sys.exit(1)
PY
  then
    echo "deferred_emit" > "${EVAL_META_DIR}/fault-mode"
    return 1
  fi

  replay_out="$(collect_replay_lines "${trace_id}")"
  if echo "${replay_out}" | grep -q "${fail_summary}"; then
    echo "deferred fail probe: fail-probe note leaked onto bus before discard" >&2
    echo "deferred_emit" > "${EVAL_META_DIR}/fault-mode"
    return 1
  fi
  if echo "${replay_out}" | grep -E 'INSIGHT[[:space:]]+\(context\.note\)'; then
    echo "deferred fail probe: context.note on bus before discard" >&2
    echo "deferred_emit" > "${EVAL_META_DIR}/fault-mode"
    return 1
  fi

  flush_out="$(paseka event flush --discard --trace "${trace_id}" --agent "${agent}" -C "${EVAL_ROOT}")"
  echo "flush --discard: ${flush_out}"
  pending_json="$(paseka event pending --trace "${trace_id}" --agent "${agent}" -C "${EVAL_ROOT}")"
  echo "pending after discard: ${pending_json}"
  if ! PENDING_JSON="${pending_json}" python3 - <<'PY'
import json, os, sys
p = json.loads(os.environ["PENDING_JSON"])
if not p.get("ok") or p.get("count") != 0:
    print(f"want pending count=0 after discard, got {p}", file=sys.stderr)
    sys.exit(1)
PY
  then
    echo "deferred_emit" > "${EVAL_META_DIR}/fault-mode"
    return 1
  fi

  replay_out="$(collect_replay_lines "${trace_id}")"
  if echo "${replay_out}" | grep -q "${fail_summary}"; then
    echo "deferred fail probe: discard published the fail-probe note" >&2
    echo "deferred_emit" > "${EVAL_META_DIR}/fault-mode"
    return 1
  fi

  # Hive success path uses deferred_emit; reset builder-runs so scoring max_builder_runs=1.
  echo "deferred_emit" > "${EVAL_META_DIR}/fault-mode"
  echo "0" > "${EVAL_META_DIR}/builder-runs"
  echo "deferred fail probe: pending discarded; continuing to success path"
  return 0
}

# probe_artifact_fail_no_flush: builder writes comb then exit 1; no artifact.written on bus.
probe_artifact_fail_no_flush() {
  local trace_id="$1"
  local bee_out replay_out comb_file

  echo "artifact fail probe: bee run builder (exit 1 after comb write)..."
  echo "write_comb_fail" > "${EVAL_META_DIR}/fault-mode"
  set +e
  bee_out="$(paseka bee run builder --trace "${trace_id}" --body "artifact fail probe" -C "${EVAL_ROOT}" 2>&1)"
  set -e
  echo "${bee_out}"

  replay_out="$(collect_replay_lines "${trace_id}")"
  if echo "${replay_out}" | grep -qE 'SIGNAL[[:space:]]+\(artifact\.written\)'; then
    echo "artifact fail probe: artifact.written leaked on failed run" >&2
    echo "write_comb" > "${EVAL_META_DIR}/fault-mode"
    return 1
  fi

  comb_file="${EVAL_ROOT}/.paseka/runs/${trace_id}/artifacts/research.md"
  if [[ ! -f "${comb_file}" ]]; then
    echo "artifact fail probe: research.md not on disk after fail" >&2
    echo "write_comb" > "${EVAL_META_DIR}/fault-mode"
    return 1
  fi

  # Fail probe leaves comb on disk (014 audit). Clear before success path so the
  # next builder run captures an empty baseline and scan-flush sees new files.
  rm -rf "${EVAL_ROOT}/.paseka/runs/${trace_id}/artifacts"

  echo "write_comb" > "${EVAL_META_DIR}/fault-mode"
  echo "0" > "${EVAL_META_DIR}/builder-runs"
  echo "artifact fail probe: no bus flush; continuing to success path"
  return 0
}

# check_artifact_oracles scores 014 comb flush side effects (count, prompt, export).
check_artifact_oracles() {
  local case_id="$1"
  local trace_id="$2"
  local replay_out="$3"
  local want_count actual comb_dir prompt_file export_out

  want_count="$(read_case_field "$case_id" score_expect_artifact_written_count)"
  if [[ -n "${want_count}" ]]; then
    actual="$(echo "${replay_out}" | grep -cE 'SIGNAL[[:space:]]+\(artifact\.written\)' || true)"
    if [[ "${actual}" != "${want_count}" ]]; then
      echo "artifact oracle: want ${want_count} artifact.written, got ${actual}" >&2
      return 1
    fi
    echo "artifact oracle: artifact.written count=${actual}"
  fi

  if [[ "$(read_case_field "$case_id" score_expect_artifact_prompt)" == "true" ]]; then
    local partial="${EVAL_ROOT}/.paseka/prompts/_partials/emit-howto.md"
    comb_dir="${EVAL_ROOT}/.paseka/runs/${trace_id}/artifacts"
    if ! grep -q '{{.ArtifactsDir}}' "${partial}"; then
      echo "artifact oracle: emit-howto missing {{.ArtifactsDir}}" >&2
      return 1
    fi
    if [[ ! -f "${comb_dir}/research.md" ]]; then
      echo "artifact oracle: comb research.md missing under ${comb_dir}" >&2
      return 1
    fi
    echo "artifact oracle: ArtifactsDir documented; comb research.md present"
  fi

  if [[ "$(read_case_field "$case_id" score_expect_artifact_export)" == "true" ]]; then
    local export_path
    export_path="$(paseka export --trace "${trace_id}" --include artifacts --format md -C "${EVAL_ROOT}" 2>/dev/null | tail -1)"
    if [[ -z "${export_path}" || ! -f "${export_path}" ]]; then
      echo "artifact oracle: export --include artifacts did not write a report file" >&2
      return 1
    fi
    export_out="$(cat "${export_path}")"
    rm -f "${export_path}"
    if ! echo "${export_out}" | grep -q "Research brief"; then
      echo "artifact oracle: export --include artifacts missing Research brief" >&2
      return 1
    fi
    if echo "${export_out}" | grep -qE '\.hidden|scratch\.tmp'; then
      echo "artifact oracle: skip-list files leaked into export" >&2
      return 1
    fi
    echo "artifact oracle: export inlines research.md, skip-list omitted"
  fi

  return 0
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
      $1 == "added:" && key == "added" { print $2; found=1 }
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
      $1 == "bee:" && key == "bee" { print $2; found=1 }
      $1 == "summary:" && key == "summary" {
        sub(/^  summary:[[:space:]]*/, "")
        print $0
        found=1
      }
      END { if (!found) print "" }
    '
}

colony_energy_budget() {
  awk '/^[[:space:]]*energy_budget:[[:space:]]*[0-9]+/ {
    sub(/^[[:space:]]*energy_budget:[[:space:]]*/, "")
    print
    exit
  }' "${COLONY_CONFIG}" 2>/dev/null
}

task_projection_intent() {
  local trace_id="$1"
  local task_id="$2"
  local task_md="${EVAL_ROOT}/.paseka/runs/${trace_id}/tasks/${task_id}/task.md"
  if [[ ! -f "${task_md}" ]]; then
    echo ""
    return 0
  fi
  awk '/^intent:/{sub(/^intent:[[:space:]]*/, ""); print; exit}' "${task_md}"
}

check_cue_energy_oracle() {
  local case_id="$1"
  local trace_id="$2"
  local max_budget budget colony_budget
  max_budget="$(read_case_field "$case_id" score_expect_energy_budget_lte)"
  budget="$(energy_show_field "${trace_id}" budget)"
  colony_budget="$(colony_energy_budget)"

  if [[ -z "${budget}" ]]; then
    echo "cue energy oracle: no budget on trace" >&2
    return 1
  fi
  if [[ -n "${max_budget}" && "${budget}" -gt "${max_budget}" ]]; then
    echo "cue energy oracle: budget=${budget}, want <= ${max_budget}" >&2
    return 1
  fi
  if [[ -n "${colony_budget}" && "${budget}" -ge "${colony_budget}" ]]; then
    echo "cue energy oracle: budget=${budget}, want < colony default ${colony_budget} (likely reseeded before cue run)" >&2
    return 1
  fi
  echo "cue energy oracle: budget=${budget} (colony default=${colony_budget})"
  return 0
}

check_cue_task_oracle() {
  local case_id="$1"
  local trace_id="$2"
  local task_id="$3"
  local expect_bee expect_intent actual_bee actual_intent
  expect_bee="$(read_case_field "$case_id" score_expect_bee)"
  expect_intent="$(read_case_field "$case_id" score_expect_intent)"

  if [[ -z "${expect_bee}" && -z "${expect_intent}" ]]; then
    return 0
  fi

  actual_bee="$(task_show_field "${trace_id}" "${task_id}" bee)"
  actual_intent="$(task_projection_intent "${trace_id}" "${task_id}")"

  if [[ -n "${expect_bee}" && "${actual_bee}" != "${expect_bee}" ]]; then
    echo "cue task oracle: bee=${actual_bee@Q}, want ${expect_bee@Q}" >&2
    return 1
  fi
  if [[ -n "${expect_intent}" && "${actual_intent}" != "${expect_intent}" ]]; then
    echo "cue task oracle: intent=${actual_intent@Q}, want ${expect_intent@Q}" >&2
    return 1
  fi
  echo "cue task oracle: bee=${actual_bee}, intent=${actual_intent}"
  return 0
}

replay_event_count() {
  local replay="$1"
  local event_type="$2"
  local event_kind="$3"
  printf '%s\n' "${replay}" | grep -cE "${event_type}[[:space:]]+\(${event_kind}\)" || true
}

wait_for_watcher_activity() {
  local trace_id="$1"
  local task_id="$2"
  local timeout_secs="$3"
  local start now runs status
  start=$(date +%s)
  while true; do
    runs=0
    if [[ -f "${EVAL_META_DIR}/watcher-runs" ]]; then
      runs="$(cat "${EVAL_META_DIR}/watcher-runs")"
    fi
    if [[ "${runs}" =~ ^[0-9]+$ ]] && (( runs >= 1 )); then
      echo "watcher-runs=${runs}"
      return 0
    fi
    status="$(task_show_field "${trace_id}" "${task_id}" status)"
    case "${status}" in
      running|waiting_review|blocked)
        echo "task-status=${status}"
        return 0
        ;;
    esac
    now=$(date +%s)
    if (( now - start >= timeout_secs )); then
      echo "timeout (watcher-runs=${runs} status=${status:-missing})" >&2
      return 1
    fi
    sleep 1
  done
}

run_standing_trail_flow() {
  local case_id="$1"
  local trace_id="$2"
  local task_body_file="$3"
  local timeout_secs="$4"
  local cue_id="$5"
  local ticks="$6"
  local stipend="$7"
  local overlap="$8"
  local topup="$9"
  local cue_text first_out first_task second_out second_task
  local first_status second_status overlap_rc overlap_out
  local replay_before replay_after plans_before plans_after
  local stipends_before stipends_after

  STANDING_TASK_ID=""
  STANDING_FIRST_TASK_ID=""
  STANDING_TASK_STATUS="timeout"
  STANDING_REPLAY=""
  STANDING_OVERLAP_REFUSED=false

  if ! [[ "${ticks}" =~ ^[0-9]+$ ]] || (( ticks != 2 )); then
    echo "standing oracle: this flow requires exactly 2 ticks" >&2
    return 1
  fi
  if ! [[ "${stipend}" =~ ^[0-9]+$ ]] || (( stipend < 1 )); then
    echo "standing oracle: stipend must be a positive integer" >&2
    return 1
  fi
  if ! [[ "${topup}" =~ ^[0-9]+$ ]]; then
    topup=0
  fi

  cue_text="$(tr -d '\n' < "${task_body_file}" | sed 's/[[:space:]]*$//')"
  if ! first_out="$(paseka cue run "${cue_id}" "${cue_text}" --trace "${trace_id}" -C "${EVAL_ROOT}" 2>&1)"; then
    echo "${first_out}" >&2
    STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "${first_out}"
  first_task="$(printf '%s\n' "${first_out}" | awk '/^Task:/{print $2; exit}')"
  if [[ -z "${first_task}" ]]; then
    echo "standing oracle: first cue did not return a task id" >&2
    STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  STANDING_TASK_ID="${first_task}"
  STANDING_FIRST_TASK_ID="${first_task}"
  echo "first standing tick task=${first_task}"
  echo "waiting for first standing tick activity (timeout ${timeout_secs}s)..."
  if ! wait_for_watcher_activity "${trace_id}" "${first_task}" "${timeout_secs}"; then
    STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi

  if [[ "${overlap}" == "true" ]]; then
    replay_before="$(collect_replay_lines "${trace_id}")"
    plans_before="$(replay_event_count "${replay_before}" INSIGHT task.plan)"
    stipends_before="$(replay_event_count "${replay_before}" SIGNAL energy.stipend)"
    set +e
    overlap_out="$(paseka cue run "${cue_id}" "${cue_text}" --trace "${trace_id}" -C "${EVAL_ROOT}" 2>&1)"
    overlap_rc=$?
    set -e
    echo "${overlap_out}"
    if (( overlap_rc == 0 )); then
      echo "standing oracle: overlapping cue run unexpectedly succeeded" >&2
      STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
      return 1
    fi
    if ! printf '%s\n' "${overlap_out}" | grep -qiE 'busy|in flight'; then
      echo "standing oracle: overlap error did not identify a busy tick" >&2
      STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
      return 1
    fi
    sleep 1
    replay_after="$(collect_replay_lines "${trace_id}")"
    plans_after="$(replay_event_count "${replay_after}" INSIGHT task.plan)"
    stipends_after="$(replay_event_count "${replay_after}" SIGNAL energy.stipend)"
    if [[ "${plans_after}" != "${plans_before}" || "${stipends_after}" != "${stipends_before}" ]]; then
      echo "standing oracle: overlap refusal published ingress or stipend" >&2
      STANDING_REPLAY="${replay_after}"
      return 1
    fi
    STANDING_OVERLAP_REFUSED=true
    echo "standing overlap refusal verified"
  fi

  if ! first_status="$(wait_for_expected_task_status "${trace_id}" "${first_task}" completed "${timeout_secs}")"; then
    echo "standing oracle: first task status=${first_status}, want completed" >&2
    STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "first standing tick status=${first_status}"

  if (( topup > 0 )); then
    if ! operator_energy_add_trace "${trace_id}" "${topup}"; then
      echo "standing oracle: energy top-up failed" >&2
      STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
      return 1
    fi
  fi

  if ! second_out="$(paseka cue run "${cue_id}" "${cue_text}" --trace "${trace_id}" -C "${EVAL_ROOT}" 2>&1)"; then
    echo "${second_out}" >&2
    STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "${second_out}"
  second_task="$(printf '%s\n' "${second_out}" | awk '/^Task:/{print $2; exit}')"
  if [[ -z "${second_task}" || "${second_task}" == "${first_task}" ]]; then
    echo "standing oracle: second task id=${second_task@Q}, want a new id" >&2
    STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "second standing tick task=${second_task}"
  if ! second_status="$(wait_for_expected_task_status "${trace_id}" "${second_task}" completed "${timeout_secs}")"; then
    echo "standing oracle: second task status=${second_status}, want completed" >&2
    STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi

  STANDING_TASK_ID="${second_task}"
  STANDING_TASK_STATUS="${second_status}"
  STANDING_REPLAY="$(collect_replay_lines "${trace_id}")"
  return 0
}

check_standing_trail_oracle() {
  local trace_id="$1"
  local first_task="$2"
  local second_task="$3"
  local ticks="$4"
  local stipend="$5"
  local topup="$6"
  local overlap="$7"
  local runs budget remaining added expected_remaining checkpoint
  local plans ready completions consumes stipends titles artifacts

  runs="$(cat "${EVAL_META_DIR}/watcher-runs" 2>/dev/null || true)"
  budget="$(energy_show_field "${trace_id}" budget)"
  remaining="$(energy_show_field "${trace_id}" remaining)"
  added="$(energy_show_field "${trace_id}" added)"
  [[ -n "${added}" ]] || added=0
  expected_remaining=$(( stipend - 1 ))
  checkpoint="${EVAL_ROOT}/.paseka/runs/${trace_id}/artifacts/checkpoint.json"

  [[ "${runs}" == "${ticks}" ]] || { echo "standing oracle: watcher-runs=${runs}, want ${ticks}" >&2; return 1; }
  [[ "${first_task}" != "${second_task}" ]] || { echo "standing oracle: task ids did not change" >&2; return 1; }
  [[ "${budget}" == "${stipend}" ]] || { echo "standing oracle: budget=${budget}, want ${stipend}" >&2; return 1; }
  [[ "${remaining}" == "${expected_remaining}" ]] || { echo "standing oracle: remaining=${remaining}, want ${expected_remaining}" >&2; return 1; }
  [[ "${added}" == "${topup}" ]] || { echo "standing oracle: added=${added}, want ${topup}" >&2; return 1; }
  [[ -f "${checkpoint}" ]] || { echo "standing oracle: checkpoint missing: ${checkpoint}" >&2; return 1; }

  CHECKPOINT_FILE="${checkpoint}" EXPECTED_TICKS="${ticks}" python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

data = json.loads(Path(os.environ["CHECKPOINT_FILE"]).read_text())
if data.get("ticks") != int(os.environ["EXPECTED_TICKS"]):
    print(f"checkpoint ticks={data.get('ticks')}, want {os.environ['EXPECTED_TICKS']}", file=sys.stderr)
    raise SystemExit(1)
if data.get("previous") != int(os.environ["EXPECTED_TICKS"]) - 1:
    print(f"checkpoint previous={data.get('previous')}, want {int(os.environ['EXPECTED_TICKS']) - 1}", file=sys.stderr)
    raise SystemExit(1)
PY

  plans="$(replay_event_count "${STANDING_REPLAY}" INSIGHT task.plan)"
  ready="$(replay_event_count "${STANDING_REPLAY}" SIGNAL task.ready)"
  completions="$(replay_event_count "${STANDING_REPLAY}" VERIFICATION task.completed)"
  consumes="$(replay_event_count "${STANDING_REPLAY}" SIGNAL energy.consume)"
  stipends="$(replay_event_count "${STANDING_REPLAY}" SIGNAL energy.stipend)"
  titles="$(replay_event_count "${STANDING_REPLAY}" INSIGHT trace.title)"
  artifacts="$(replay_event_count "${STANDING_REPLAY}" SIGNAL artifact.written)"
  [[ "${plans}" == "${ticks}" ]] || { echo "standing oracle: task.plan count=${plans}, want ${ticks}" >&2; return 1; }
  [[ "${ready}" == "${ticks}" ]] || { echo "standing oracle: task.ready count=${ready}, want ${ticks}" >&2; return 1; }
  [[ "${completions}" == "${ticks}" ]] || { echo "standing oracle: task.completed count=${completions}, want ${ticks}" >&2; return 1; }
  [[ "${consumes}" == "${ticks}" ]] || { echo "standing oracle: energy.consume count=${consumes}, want ${ticks}" >&2; return 1; }
  [[ "${stipends}" == "1" ]] || { echo "standing oracle: energy.stipend count=${stipends}, want 1" >&2; return 1; }
  [[ "${titles}" == "1" ]] || { echo "standing oracle: trace.title count=${titles}, want 1" >&2; return 1; }
  [[ "${artifacts}" == "${ticks}" ]] || { echo "standing oracle: artifact.written count=${artifacts}, want ${ticks}" >&2; return 1; }
  if [[ "${overlap}" == "true" && "${STANDING_OVERLAP_REFUSED}" != "true" ]]; then
    echo "standing oracle: overlap refusal was not verified" >&2
    return 1
  fi
  echo "standing oracle: ticks=${ticks} stipend=${stipend} remaining=${remaining} checkpoint reused"
  return 0
}

run_final_request_changes_flow() {
  local case_id="$1"
  local trace_id="$2"
  local task_body_file="$3"
  local timeout_secs="$4"
  local title="$5"
  local bee="$6"
  local intent="$7"
  local review="$8"
  local comments_file="$9"
  local feedback="${10}"
  local summary="${11}"
  local create_out initial_task final_status reject_out rework_task rework_status approve_out
  local -a create_args

  FINAL_REVIEW_TASK_ID="_review"
  FINAL_REVIEW_INITIAL_TASK_ID=""
  FINAL_REVIEW_REWORK_TASK_ID=""
  FINAL_REVIEW_HELD=false
  FINAL_REVIEW_REPLAY=""

  if [[ ! -f "${comments_file}" ]]; then
    echo "final request-changes oracle: comments file missing: ${comments_file}" >&2
    return 1
  fi

  create_args=(
    task create
    --trace "${trace_id}"
    --title "${title}"
    --file "${task_body_file}"
    --bee "${bee}"
    --intent "${intent}"
    --review "${review}"
    --autorun
    -C "${EVAL_ROOT}"
  )
  if ! create_out="$(paseka "${create_args[@]}" 2>&1)"; then
    echo "${create_out}" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "${create_out}"
  initial_task="$(printf '%s\n' "${create_out}" | awk '/^  task:/{print $2; exit}')"
  if [[ -z "${initial_task}" ]]; then
    echo "final request-changes oracle: initial task id missing" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  FINAL_REVIEW_INITIAL_TASK_ID="${initial_task}"
  echo "initial work task=${initial_task}"
  if ! wait_for_success_scoring "${case_id}" "${trace_id}" "${initial_task}" completed "${timeout_secs}" >/dev/null; then
    echo "final request-changes oracle: initial work did not complete" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi

  if ! final_status="$(wait_for_expected_task_status "${trace_id}" "${FINAL_REVIEW_TASK_ID}" waiting_review "${timeout_secs}")"; then
    echo "final request-changes oracle: final gate status=${final_status}, want waiting_review" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "final gate status=${final_status}"
  if ! commit_trace_worktree "${trace_id}" "eval final request changes: initial proposal"; then
    echo "final request-changes oracle: initial worktree commit failed" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi

  if ! reject_out="$(operator_reject_comments "${trace_id}" "${FINAL_REVIEW_TASK_ID}" "${comments_file}" "${feedback}" 2>&1)"; then
    echo "${reject_out}" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "${reject_out}"
  rework_task="$(printf '%s\n' "${reject_out}" | awk '/rework task:/{print $3; exit}')"
  if [[ -z "${rework_task}" || "${rework_task}" == "${initial_task}" ]]; then
    echo "final request-changes oracle: rework task id=${rework_task@Q}" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  FINAL_REVIEW_REWORK_TASK_ID="${rework_task}"
  echo "rework task=${rework_task}"
  if [[ "$(task_show_field "${trace_id}" "${FINAL_REVIEW_TASK_ID}" status)" != "waiting_review" ]]; then
    echo "final request-changes oracle: final gate left waiting_review after request changes" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi

  if ! rework_status="$(wait_for_expected_task_status "${trace_id}" "${rework_task}" completed "${timeout_secs}")"; then
    echo "final request-changes oracle: rework status=${rework_status}, want completed" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if [[ "$(task_show_field "${trace_id}" "${FINAL_REVIEW_TASK_ID}" status)" != "waiting_review" ]]; then
    echo "final request-changes oracle: final gate changed while rework was in flight" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  FINAL_REVIEW_HELD=true
  echo "final gate held open after rework status=${rework_status}"
  if ! commit_trace_worktree "${trace_id}" "eval final request changes: rework"; then
    echo "final request-changes oracle: rework worktree commit failed" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi

  if ! approve_out="$(operator_approve_proposal "${trace_id}" "${FINAL_REVIEW_TASK_ID}" "${summary}" 2>&1)"; then
    echo "${approve_out}" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "${approve_out}"
  if ! final_status="$(wait_for_expected_task_status "${trace_id}" "${FINAL_REVIEW_TASK_ID}" completed "${timeout_secs}")"; then
    echo "final request-changes oracle: final status=${final_status}, want completed" >&2
    FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  FINAL_REVIEW_REPLAY="$(collect_replay_lines "${trace_id}")"
  return 0
}

check_final_request_changes_oracle() {
  local trace_id="$1"
  local initial_task="$2"
  local rework_task="$3"
  local expect_rework_task="$4"
  local final_status comments_path task_projection
  local plans ready proposals successes completions artifacts feedback

  final_status="$(task_show_field "${trace_id}" "${FINAL_REVIEW_TASK_ID}" status)"
  [[ "${final_status}" == "completed" ]] || { echo "final request-changes oracle: final status=${final_status}, want completed" >&2; return 1; }
  [[ "${FINAL_REVIEW_HELD}" == "true" ]] || { echo "final request-changes oracle: final gate was not held open" >&2; return 1; }
  if [[ "${expect_rework_task}" == "true" ]]; then
    [[ -n "${rework_task}" && "${rework_task}" != "${initial_task}" ]] || { echo "final request-changes oracle: rework task id missing or reused" >&2; return 1; }
  fi

  comments_path="${EVAL_ROOT}/.paseka/runs/${trace_id}/artifacts/review-comments.md"
  [[ -f "${comments_path}" ]] || { echo "final request-changes oracle: comb packet missing: ${comments_path}" >&2; return 1; }
  grep -q 'short revision note' "${comments_path}" || { echo "final request-changes oracle: review packet content missing" >&2; return 1; }
  task_projection="${EVAL_ROOT}/.paseka/runs/${trace_id}/tasks/${rework_task}/task.md"
  [[ -f "${task_projection}" ]] || { echo "final request-changes oracle: rework projection missing: ${task_projection}" >&2; return 1; }
  grep -q 'review-comments.md' "${task_projection}" || { echo "final request-changes oracle: rework body does not reference comb packet" >&2; return 1; }

  plans="$(replay_event_count "${FINAL_REVIEW_REPLAY}" INSIGHT task.plan)"
  ready="$(replay_event_count "${FINAL_REVIEW_REPLAY}" SIGNAL task.ready)"
  proposals="$(replay_event_count "${FINAL_REVIEW_REPLAY}" MUTATION code.proposal.isolated)"
  successes="$(replay_event_count "${FINAL_REVIEW_REPLAY}" VERIFICATION verification.success)"
  completions="$(replay_event_count "${FINAL_REVIEW_REPLAY}" VERIFICATION task.completed)"
  artifacts="$(replay_event_count "${FINAL_REVIEW_REPLAY}" SIGNAL artifact.written)"
  feedback="$(replay_event_count "${FINAL_REVIEW_REPLAY}" INSIGHT human.feedback)"
  [[ "${plans}" == "3" ]] || { echo "final request-changes oracle: task.plan count=${plans}, want 3" >&2; return 1; }
  [[ "${ready}" == "2" ]] || { echo "final request-changes oracle: task.ready count=${ready}, want 2" >&2; return 1; }
  [[ "${proposals}" == "2" ]] || { echo "final request-changes oracle: isolated proposal count=${proposals}, want 2" >&2; return 1; }
  [[ "${successes}" == "2" ]] || { echo "final request-changes oracle: verification.success count=${successes}, want 2" >&2; return 1; }
  [[ "${completions}" == "3" ]] || { echo "final request-changes oracle: task.completed count=${completions}, want 3" >&2; return 1; }
  [[ "${artifacts}" == "1" ]] || { echo "final request-changes oracle: artifact.written count=${artifacts}, want 1" >&2; return 1; }
  [[ "${feedback}" == "1" ]] || { echo "final request-changes oracle: human.feedback count=${feedback}, want 1" >&2; return 1; }
  echo "final request-changes oracle: rework=${rework_task} final held then approved"
  return 0
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

# wait_for_hive_activity blocks until the script builder has started (builder-runs >= 1)
# or the task is visibly non-idle — used before operator kill so the loop is in flight.
wait_for_hive_activity() {
  local trace_id="$1"
  local task_id="$2"
  local timeout_secs="$3"
  local start now runs status
  start=$(date +%s)
  while true; do
    runs=0
    if [[ -f "${EVAL_META_DIR}/builder-runs" ]]; then
      runs="$(cat "${EVAL_META_DIR}/builder-runs")"
    fi
    if [[ "${runs}" =~ ^[0-9]+$ ]] && (( runs >= 1 )); then
      echo "builder-runs=${runs}"
      return 0
    fi
    status="$(task_show_field "${trace_id}" "${task_id}" status)"
    case "${status}" in
      running|waiting_review|blocked)
        echo "task-status=${status}"
        return 0
        ;;
    esac
    now=$(date +%s)
    if (( now - start >= timeout_secs )); then
      echo "timeout (builder-runs=${runs} status=${status:-missing})" >&2
      return 1
    fi
    sleep 1
  done
}

operator_kill_trace() {
  local trace_id="$1"
  local reason="$2"
  local args=(kill --trace "${trace_id}" -C "${EVAL_ROOT}")
  if [[ -n "${reason}" ]]; then
    args+=(--reason "${reason}")
  fi
  echo "operator kill: paseka ${args[*]}"
  paseka "${args[@]}"
}

builder_runs_count() {
  if [[ -f "${EVAL_META_DIR}/builder-runs" ]]; then
    cat "${EVAL_META_DIR}/builder-runs"
  else
    echo "0"
  fi
}

scout_runs_count() {
  if [[ -f "${EVAL_META_DIR}/scout-runs" ]]; then
    cat "${EVAL_META_DIR}/scout-runs"
  else
    echo "0"
  fi
}

check_scout_run_oracle() {
  local trace_id="$1"
  local runs
  runs="$(scout_runs_count)"
  if [[ ! "${runs}" =~ ^[0-9]+$ ]] || (( runs < 1 )); then
    echo "scout run oracle: scout-runs=${runs@Q}, want >= 1" >&2
    return 1
  fi
  if ! find "${EVAL_ROOT}/.paseka/runs/${trace_id}" -mindepth 1 -maxdepth 1 -type d ! -name 'tasks' -print -quit | grep -q .; then
    echo "scout run oracle: no agent run dir under .paseka/runs/${trace_id}" >&2
    return 1
  fi
  echo "scout run oracle: scout-runs=${runs}, agent run dir present"
  return 0
}

# Agent adapter runs live at .paseka/runs/<trace>/<agentId>/ (tasks/ is separate).
count_trace_agent_run_dirs() {
  local trace_id="$1"
  local runs_dir="${EVAL_ROOT}/.paseka/runs/${trace_id}"
  if [[ ! -d "${runs_dir}" ]]; then
    echo "0"
    return 0
  fi
  find "${runs_dir}" -mindepth 1 -maxdepth 1 -type d ! -name 'tasks' | wc -l | tr -d ' '
}

operator_energy_add_trace() {
  local trace_id="$1"
  local amount="$2"
  local args=(energy add --trace "${trace_id}" --amount "${amount}" -C "${EVAL_ROOT}")
  echo "operator energy add: paseka ${args[*]}"
  paseka "${args[@]}"
}

# settle_no_redispatch polls builder-runs during the settle window; early fail on growth.
settle_no_redispatch() {
  local trace_id="$1"
  local task_id="$2"
  local runs_before="$3"
  local settle_secs="$4"
  local start now runs
  start=$(date +%s)
  while true; do
    runs="$(builder_runs_count)"
    if [[ "${runs}" =~ ^[0-9]+$ ]] && (( runs > runs_before )); then
      echo "no-redispatch settle: builder-runs grew ${runs_before} -> ${runs}" >&2
      return 1
    fi
    now=$(date +%s)
    if (( now - start >= settle_secs )); then
      echo "settle window complete (${settle_secs}s, builder-runs=${runs})"
      return 0
    fi
    sleep 1
  done
}

# check_no_redispatch_oracle asserts US4: energy.add after kill tops up honey without redispatch.
check_no_redispatch_oracle() {
  local case_id="$1"
  local trace_id="$2"
  local task_id="$3"
  local runs_before="$4"
  local remaining_before="$5"
  local add_amount="$6"
  local run_dirs_before="${7:-0}"
  local expect_no_redispatch expect_status status runs remaining run_dirs_after want_remaining
  expect_no_redispatch="$(read_case_field "$case_id" score_expect_no_redispatch)"
  if [[ "${expect_no_redispatch}" != "true" ]]; then
    return 0
  fi

  expect_status="$(read_case_field "$case_id" score_expect_task_status)"
  status="$(task_show_field "${trace_id}" "${task_id}" status)"
  if [[ -n "${expect_status}" && "${status}" != "${expect_status}" ]]; then
    echo "no-redispatch oracle: status=${status}, want ${expect_status}" >&2
    return 1
  fi

  runs="$(builder_runs_count)"
  if [[ ! "${runs}" =~ ^[0-9]+$ ]]; then
    echo "no-redispatch oracle: builder-runs=${runs@Q}, want integer" >&2
    return 1
  fi
  if (( runs > runs_before )); then
    echo "no-redispatch oracle: builder-runs grew ${runs_before} -> ${runs}" >&2
    return 1
  fi

  remaining="$(energy_show_field "${trace_id}" remaining)"
  if [[ -z "${remaining}" ]] || ! [[ "${remaining}" =~ ^[0-9]+$ ]]; then
    echo "no-redispatch oracle: remaining=${remaining@Q}, want integer" >&2
    return 1
  fi
  if [[ ! "${remaining_before}" =~ ^[0-9]+$ ]] || [[ ! "${add_amount}" =~ ^[0-9]+$ ]]; then
    echo "no-redispatch oracle: invalid baseline remaining=${remaining_before} add=${add_amount}" >&2
    return 1
  fi
  want_remaining=$(( remaining_before + add_amount ))
  if (( remaining < want_remaining )); then
    echo "no-redispatch oracle: remaining=${remaining}, want >= ${want_remaining} (before=${remaining_before} + add=${add_amount})" >&2
    return 1
  fi

  run_dirs_after="$(count_trace_agent_run_dirs "${trace_id}")"
  if [[ "${run_dirs_before}" =~ ^[0-9]+$ ]] && [[ "${run_dirs_after}" =~ ^[0-9]+$ ]]; then
    if (( run_dirs_after > run_dirs_before )); then
      echo "no-redispatch oracle: run dirs grew ${run_dirs_before} -> ${run_dirs_after}" >&2
      return 1
    fi
  fi

  return 0
}

# wait_for_replay_kind blocks until paseka replay shows TYPE (kind) for the trace.
wait_for_replay_kind() {
  local trace_id="$1"
  local event_type="$2"
  local event_kind="$3"
  local timeout_secs="$4"
  local start now replay
  start=$(date +%s)
  while true; do
    replay="$(collect_replay_lines "${trace_id}")"
    if echo "${replay}" | grep -qE "${event_type}[[:space:]]+\(${event_kind}\)"; then
      echo "replay has ${event_type}/${event_kind}" >&2
      return 0
    fi
    now=$(date +%s)
    if (( now - start >= timeout_secs )); then
      echo "timeout waiting for replay ${event_type}/${event_kind}" >&2
      return 1
    fi
    sleep 1
  done
}

# wait_for_task_status_change returns when status differs from from_status (or timeout).
wait_for_task_status_change() {
  local trace_id="$1"
  local task_id="$2"
  local from_status="$3"
  local timeout_secs="$4"
  local start now status
  start=$(date +%s)
  while true; do
    status="$(task_show_field "${trace_id}" "${task_id}" status)"
    if [[ -z "${status}" ]]; then
      status="missing"
    fi
    if [[ "${status}" != "${from_status}" ]]; then
      echo "${status}"
      return 0
    fi
    now=$(date +%s)
    if (( now - start >= timeout_secs )); then
      echo "${status}"
      return 1
    fi
    sleep 1
  done
}

operator_reject_comments() {
  local trace_id="$1"
  local task_id="$2"
  local comments_file="$3"
  local feedback="$4"
  local args=(
    proposal reject
    --trace "${trace_id}"
    --task "${task_id}"
    --comments-file "${comments_file}"
    -C "${EVAL_ROOT}"
  )
  if [[ -n "${feedback}" ]]; then
    args+=(--feedback "${feedback}")
  fi
  echo "operator request changes: paseka ${args[*]}" >&2
  paseka "${args[@]}"
}

operator_reject_proposal() {
  local trace_id="$1"
  local task_id="$2"
  local feedback="$3"
  local args=(
    proposal reject
    --trace "${trace_id}"
    --task "${task_id}"
    -C "${EVAL_ROOT}"
  )
  if [[ -n "${feedback}" ]]; then
    args+=(--feedback "${feedback}")
  fi
  echo "operator reject: paseka ${args[*]}" >&2
  paseka "${args[@]}" >&2
}

operator_approve_proposal() {
  local trace_id="$1"
  local task_id="$2"
  local summary="$3"
  local args=(
    proposal approve
    --trace "${trace_id}"
    --task "${task_id}"
    -C "${EVAL_ROOT}"
  )
  if [[ -n "${summary}" ]]; then
    args+=(--summary "${summary}")
  fi
  echo "operator approve: paseka ${args[*]}" >&2
  paseka "${args[@]}" >&2
}

# replay_has_verification_after_feedback exits 0 when VERIFICATION/verification.success
# appears after INSIGHT/human.feedback in the given replay text.
replay_has_verification_after_feedback() {
  local replay_out="$1"
  REPLAY_TEXT="${replay_out}" python3 - <<'INNER'
import os, re, sys
actual = []
for line in os.environ.get("REPLAY_TEXT", "").splitlines():
    m = re.match(r"^\s*\d+\.\s+(\S+)\s+\(([^)]+)\)", line)
    if m:
        actual.append((m.group(1), m.group(2)))
seen_feedback = False
for typ, kind in actual:
    if typ == "INSIGHT" and kind == "human.feedback":
        seen_feedback = True
        continue
    if seen_feedback and typ == "VERIFICATION" and kind == "verification.success":
        sys.exit(0)
sys.exit(1)
INNER
}

# run_human_reject_loop drives reject → rework → approve for review: required cases.
# Returns 0 when the expected terminal status is reached and worktree oracle passes.
run_human_reject_loop() {
  local case_id="$1"
  local trace_id="$2"
  local task_id="$3"
  local timeout_secs="$4"
  local reject_when approve_when feedback summary expect_status
  local start remaining status gate_wait post_start

  reject_when="$(read_case_field "${case_id}" operator_reject_when)"
  approve_when="$(read_case_field "${case_id}" operator_approve_when)"
  feedback="$(read_case_field "${case_id}" operator_reject_feedback)"
  summary="$(read_case_field "${case_id}" operator_approve_summary)"
  expect_status="$(read_case_field "${case_id}" score_expect_task_status)"
  [[ -z "${reject_when}" ]] && reject_when="waiting_review"
  [[ -z "${approve_when}" ]] && approve_when="waiting_review"
  [[ -z "${expect_status}" ]] && expect_status="completed"

  start=$(date +%s)
  remaining="${timeout_secs}"

  echo "waiting for first ${reject_when} before reject (up to ${remaining}s)..." >&2
  if ! status="$(wait_for_expected_task_status "${trace_id}" "${task_id}" "${reject_when}" "${remaining}")"; then
    echo "human-reject: first gate status=${status}, want ${reject_when}" >&2
    return 1
  fi

  # Isolated review:required enters waiting_review right after builder; wait for
  # guard verification.success before reject so the event chain is ordered.
  remaining=$(( timeout_secs - ($(date +%s) - start) ))
  (( remaining < 30 )) && remaining=30
  gate_wait="${remaining}"
  (( gate_wait > 120 )) && gate_wait=120
  echo "waiting for guard verification.success before reject (up to ${gate_wait}s)..." >&2
  if ! wait_for_replay_kind "${trace_id}" "VERIFICATION" "verification.success" "${gate_wait}"; then
    echo "human-reject: verification.success not seen before reject; continuing anyway" >&2
  fi

  remaining=$(( timeout_secs - ($(date +%s) - start) ))
  if (( remaining <= 0 )); then
    echo "human-reject: timed out before reject" >&2
    return 1
  fi
  operator_reject_proposal "${trace_id}" "${task_id}" "${feedback}"

  remaining=$(( timeout_secs - ($(date +%s) - start) ))
  (( remaining < 30 )) && remaining=30
  echo "waiting for task to leave ${reject_when} after reject..." >&2
  if ! status="$(wait_for_task_status_change "${trace_id}" "${task_id}" "${reject_when}" "${remaining}")"; then
    echo "human-reject: stuck at ${status} after reject" >&2
    return 1
  fi
  echo "post-reject status=${status}" >&2

  remaining=$(( timeout_secs - ($(date +%s) - start) ))
  if (( remaining <= 0 )); then
    echo "human-reject: timed out before second ${approve_when}" >&2
    return 1
  fi
  echo "waiting for second ${approve_when} before approve (up to ${remaining}s)..." >&2
  if ! status="$(wait_for_expected_task_status "${trace_id}" "${task_id}" "${approve_when}" "${remaining}")"; then
    echo "human-reject: second gate status=${status}, want ${approve_when}" >&2
    return 1
  fi

  remaining=$(( timeout_secs - ($(date +%s) - start) ))
  (( remaining < 30 )) && remaining=30
  gate_wait="${remaining}"
  (( gate_wait > 120 )) && gate_wait=120
  echo "waiting for post-rework verification.success before approve (up to ${gate_wait}s)..." >&2
  post_start=$(date +%s)
  while true; do
    if replay_has_verification_after_feedback "$(collect_replay_lines "${trace_id}")"; then
      echo "replay has post-rework verification.success" >&2
      break
    fi
    if (( $(date +%s) - post_start >= gate_wait )); then
      echo "human-reject: post-rework verification.success not seen; approving anyway" >&2
      break
    fi
    sleep 1
  done

  remaining=$(( timeout_secs - ($(date +%s) - start) ))
  if (( remaining <= 0 )); then
    echo "human-reject: timed out before approve" >&2
    return 1
  fi
  operator_approve_proposal "${trace_id}" "${task_id}" "${summary}"

  remaining=$(( timeout_secs - ($(date +%s) - start) ))
  (( remaining < 30 )) && remaining=30
  if ! status="$(wait_for_success_scoring "${case_id}" "${trace_id}" "${task_id}" "${expect_status}" "${remaining}")"; then
    echo "human-reject: final status=${status}, want ${expect_status} with oracle pass" >&2
    echo "${status}"
    return 1
  fi
  echo "${status}"
  return 0
}

# check_kill_oracle asserts hard stop while honey remains: cancelled task, optional
# reason summary, remaining energy > threshold, and SIGNAL/system.kill in replay.
check_kill_oracle() {
  local case_id="$1"
  local trace_id="$2"
  local task_id="$3"
  local replay_out="${4:-}"
  local expect_status expect_summary expect_killed min_remaining remaining status summary
  expect_status="$(read_case_field "$case_id" score_expect_task_status)"
  expect_summary="$(read_case_field "$case_id" score_expect_summary)"
  expect_killed="$(read_case_field "$case_id" score_expect_trace_killed)"
  min_remaining="$(read_case_field "$case_id" score_expect_energy_remaining_gt)"
  [[ -z "${min_remaining}" ]] && min_remaining="0"

  remaining="$(energy_show_field "${trace_id}" remaining)"
  status="$(task_show_field "${trace_id}" "${task_id}" status)"
  summary="$(task_show_field "${trace_id}" "${task_id}" summary)"

  if [[ -z "${remaining}" ]] || ! [[ "${remaining}" =~ ^[0-9]+$ ]]; then
    echo "kill oracle: remaining=${remaining@Q}, want integer > ${min_remaining}" >&2
    return 1
  fi
  if (( remaining <= min_remaining )); then
    echo "kill oracle: remaining=${remaining}, want > ${min_remaining} (honey must remain)" >&2
    return 1
  fi
  if [[ -n "${expect_status}" && "${status}" != "${expect_status}" ]]; then
    echo "kill oracle: status=${status}, want ${expect_status}" >&2
    return 1
  fi
  if [[ -n "${expect_summary}" && "${summary}" != "${expect_summary}" ]]; then
    echo "kill oracle: summary=${summary@Q}, want ${expect_summary@Q}" >&2
    return 1
  fi
  if [[ "${expect_killed}" == "true" ]]; then
    if [[ -z "${replay_out}" ]]; then
      replay_out="$(collect_replay_lines "${trace_id}")"
    fi
    if ! echo "${replay_out}" | grep -qE 'SIGNAL[[:space:]]+\(system\.kill\)'; then
      echo "kill oracle: replay missing SIGNAL/system.kill" >&2
      return 1
    fi
  fi
  return 0
}
