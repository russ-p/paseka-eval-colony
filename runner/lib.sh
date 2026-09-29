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
# Pull-request delivery (017): forge driver fixture, its state dir, and the local
# bare "origin" that keeps the head push on this machine.
FORGE_FIXTURE="${EVAL_ROOT}/scripts/forge-fixture.sh"
FORGE_STATE_DIR="${EVAL_ROOT}/.eval/forge"
FORGE_BARE_ORIGIN="${EVAL_ROOT}/.eval/forge-origin.git"
HOME_CONFIG="${HOME}/.config/paseka/paseka-eval-colony/config.yaml"
HOME_CONFIG_BACKUP="${EVAL_META_DIR}/home-config.bak"
ORIGIN_URL_BACKUP="${EVAL_META_DIR}/origin-url.bak"

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
elif field == "defaults_delivery":
    print(nested("defaults", "delivery") or "")
elif field == "operator_pr_title":
    print(nested("operator", "pr_title") or "")
elif field == "operator_pr_draft":
    print(nested("operator", "draft") or "")
elif field == "score_expect_pr_body_marker":
    print(nested("score", "expect_pr_body_marker") or "")
elif field == "score_expect_no_local_merge":
    print(nested("score", "expect_no_local_merge") or "")
elif field == "worktree_branch":
    print(nested("worktree", "branch") or "")
elif field == "worktree_reject_branch":
    print(nested("worktree", "reject_branch") or "")
elif field == "worktree_second_task":
    print(nested("worktree", "second_task") or "")
elif field == "score_expect_reuse":
    print(nested("score", "expect_reuse") or "")
elif field == "score_expect_no_origin_push":
    print(nested("score", "expect_no_origin_push") or "")
elif field == "score_expect_stale_after_kill":
    print(nested("score", "expect_stale_after_kill") or "")
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
  # A successful head push updates refs/remotes/origin/<branch>; drop those too so a
  # recreated worktree branch pushes as a create, not a stale --force-with-lease.
  while IFS= read -r ref; do
    [[ -z "${ref}" ]] && continue
    git -C "${EVAL_ROOT}" update-ref -d "${ref}" >/dev/null 2>&1 || true
  done < <(git -C "${EVAL_ROOT}" for-each-ref --format='%(refname)' 'refs/remotes/origin/paseka/eval-*')
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

# purge_custom_worktree_branch drops the branch a previous 018-style case renamed the
# worktree to. It does not match the paseka/eval-* pattern that purge_colony sweeps,
# and a surviving branch makes worktree.Ensure fail closed with
# `worktree: branch %q already exists` on the next run.
purge_custom_worktree_branch() {
  local branch_file="${EVAL_META_DIR}/worktree-branch"
  local branch
  [[ -f "${branch_file}" ]] || return 0
  branch="$(cat "${branch_file}")"
  if [[ -z "${branch}" ]]; then
    return 0
  fi
  if git -C "${EVAL_ROOT}" show-ref --verify --quiet "refs/heads/${branch}"; then
    git -C "${EVAL_ROOT}" branch -D -- "${branch}" >/dev/null 2>&1 || true
    echo "reset: dropped stale worktree branch ${branch}"
  fi
  return 0
}

set_colony_delivery() {
  # defaults.delivery is colony-wide, so a pull_request case patches it for the case
  # window only. Colony.yaml is restored by restore_colony_config on reset/exit.
  local delivery="$1"
  mkdir -p "${EVAL_META_DIR}"
  if [[ ! -f "${COLONY_CONFIG_BACKUP}" ]]; then
    cp "${COLONY_CONFIG}" "${COLONY_CONFIG_BACKUP}"
  fi
  DELIVERY="${delivery}" python3 - "${COLONY_CONFIG}" <<'PY'
import os
import pathlib
import re
import sys

delivery = os.environ["DELIVERY"]
path = pathlib.Path(sys.argv[1])
text = path.read_text()
if re.search(r"^\s+delivery:\s*\S+\s*$", text, re.M):
    text = re.sub(
        r"^(\s+delivery:)\s*\S+\s*$",
        rf"\g<1> {delivery}",
        text,
        count=1,
        flags=re.M,
    )
else:
    if not re.search(r"^defaults:\s*$", text, re.M):
        raise SystemExit("colony.yaml: defaults block missing")
    text = re.sub(
        r"^(defaults:\s*\n)",
        rf"\1  delivery: {delivery}\n",
        text,
        count=1,
        flags=re.M,
    )
path.write_text(text)
PY
}

# enable_forge_fixture wires home forge.command to the deterministic driver and swaps
# colony `origin` for a local bare repo, so the publish path really pushes a head but
# never touches the GitHub remote. Called before `paseka run` starts: the runtime reads
# home config once at startup and would skip reconcile without a forge command.
enable_forge_fixture() {
  mkdir -p "${EVAL_META_DIR}"
  if [[ ! -x "${FORGE_FIXTURE}" ]]; then
    echo "forge fixture missing or not executable: ${FORGE_FIXTURE}" >&2
    return 1
  fi
  if [[ ! -f "${HOME_CONFIG_BACKUP}" ]]; then
    cp "${HOME_CONFIG}" "${HOME_CONFIG_BACKUP}"
  fi
  if [[ ! -f "${ORIGIN_URL_BACKUP}" ]]; then
    git -C "${EVAL_ROOT}" remote get-url origin > "${ORIGIN_URL_BACKUP}"
  fi
  FORGE_FIXTURE="${FORGE_FIXTURE}" python3 - "${HOME_CONFIG}" <<'PY'
import os
import pathlib
import re
import sys

fixture = os.environ["FORGE_FIXTURE"]
path = pathlib.Path(sys.argv[1])
text = path.read_text()
block = "forge:\n  command:\n    - " + fixture + "\n"
if re.search(r"^forge:\s*\n", text, re.M):
    text = re.sub(
        r"^forge:\s*\n(?:  .*\n?)*",
        block,
        text,
        count=1,
        flags=re.M,
    )
else:
    text = text.rstrip("\n") + "\n" + block
path.write_text(text)
PY
  local head_ref
  head_ref="$(git -C "${EVAL_ROOT}" symbolic-ref --short HEAD)"
  rm -rf "${FORGE_STATE_DIR}" "${FORGE_BARE_ORIGIN}"
  mkdir -p "${FORGE_STATE_DIR}"
  git init --bare -q "${FORGE_BARE_ORIGIN}"
  git -C "${EVAL_ROOT}" push -q "${FORGE_BARE_ORIGIN}" "refs/heads/${head_ref}:refs/heads/${head_ref}"
  git -C "${EVAL_ROOT}" remote set-url origin "${FORGE_BARE_ORIGIN}"
  echo "forge fixture: command=${FORGE_FIXTURE} origin=${FORGE_BARE_ORIGIN} (base ${head_ref})"
}

restore_forge_config() {
  if [[ -f "${HOME_CONFIG_BACKUP}" ]]; then
    cp "${HOME_CONFIG_BACKUP}" "${HOME_CONFIG}"
    rm -f "${HOME_CONFIG_BACKUP}"
  fi
  if [[ -f "${ORIGIN_URL_BACKUP}" ]]; then
    local saved
    saved="$(cat "${ORIGIN_URL_BACKUP}")"
    if [[ -n "${saved}" ]]; then
      git -C "${EVAL_ROOT}" remote set-url origin "${saved}" >/dev/null 2>&1 || true
    fi
    rm -f "${ORIGIN_URL_BACKUP}"
  fi
  rm -rf "${FORGE_STATE_DIR}" "${FORGE_BARE_ORIGIN}" >/dev/null 2>&1 || true
}

restore_colony_config() {
  if [[ -f "${COLONY_CONFIG_BACKUP}" ]]; then
    cp "${COLONY_CONFIG_BACKUP}" "${COLONY_CONFIG}"
    rm -f "${COLONY_CONFIG_BACKUP}"
  fi
  restore_builder_bee
  restore_forge_config
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
  local trace_id fault_mode energy_budget energy_topup ingress_mode delivery
  local hold_secs kill_after watcher_hold_secs
  local worktree_branch worktree_reject_branch
  trace_id="$(read_case_field "$case_id" trace)"
  fault_mode="$(read_case_field "$case_id" fault_mode)"
  energy_budget="$(read_case_field "$case_id" energy_budget)"
  energy_topup="$(read_case_field "$case_id" energy_topup)"
  ingress_mode="$(read_case_field "$case_id" ingress_mode)"
  delivery="$(read_case_field "$case_id" defaults_delivery)"
  stop_runtime
  # Case energy_budget must be on colony.yaml before purge --reseed-energy.
  restore_colony_config
  if [[ -n "${energy_budget}" && "${ingress_mode}" != "cue" ]]; then
    set_colony_energy_budget "${energy_budget}"
  fi
  if [[ -n "${delivery}" ]]; then
    set_colony_delivery "${delivery}"
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
  purge_custom_worktree_branch
  materialize_seed "$case_id"
  # Bare origin gets the post-seed HEAD so the pushed head has a real base branch.
  if [[ -n "${delivery}" ]]; then
    enable_forge_fixture
  fi
  # Worktree-branch knobs for 018: branch names the builder emits as INSIGHT and the
  # invalid ref it must fail to emit.
  worktree_branch="$(read_case_field "$case_id" worktree_branch)"
  worktree_reject_branch="$(read_case_field "$case_id" worktree_reject_branch)"
  rm -f "${EVAL_META_DIR}/worktree-branch" "${EVAL_META_DIR}/worktree-reject-branch" \
    "${EVAL_META_DIR}/builder-branch-1" "${EVAL_META_DIR}/builder-branch-2" \
    "${EVAL_META_DIR}/branch-reject"
  if [[ -n "${worktree_branch}" ]]; then
    mkdir -p "${EVAL_META_DIR}"
    echo "${worktree_branch}" > "${EVAL_META_DIR}/worktree-branch"
    if [[ -n "${worktree_reject_branch}" ]]; then
      echo "${worktree_reject_branch}" > "${EVAL_META_DIR}/worktree-reject-branch"
    fi
  fi
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

forge_upsert_request() {
  # Echoes the recorded upsert request of the fixture driver (one JSON object).
  local trace_id="$1"
  python3 - "${FORGE_STATE_DIR}/ops.log" "${trace_id}" <<'PY'
import json
import pathlib
import sys

log_path = pathlib.Path(sys.argv[1])
trace = sys.argv[2]
if not log_path.exists():
    raise SystemExit(0)
for line in log_path.read_text().splitlines():
    if not line.strip():
        continue
    row = json.loads(line)
    if row.get("op") == "upsert" and row.get("traceId") == trace:
        print(json.dumps(row))
PY
}

homestate_pull_request_field() {
  local trace_id="$1"
  local field="$2"
  python3 - "$(dirname "${HOME_CONFIG}")/state.json" "${trace_id}" "${field}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
trace, field = sys.argv[2], sys.argv[3]
if not path.exists():
    raise SystemExit(0)
state = json.loads(path.read_text())
for entry in state.get("pullRequests") or []:
    if entry.get("traceId") == trace:
        value = entry.get(field, "")
        if isinstance(value, bool):
            value = "true" if value else "false"
        print(value if value is not None else "")
        break
PY
}

mark_forge_pr_merged() {
  # Plays the host-side merge: the fixture reports the PR as merged from now on and
  # the next `paseka run` reconcile tick (30s) closes the trail.
  local trace_id="$1"
  mkdir -p "${FORGE_STATE_DIR}"
  touch "${FORGE_STATE_DIR}/${trace_id}.merged"
}

homestate_worktree_field() {
  local trace_id="$1"
  local field="$2"
  python3 - "$(dirname "${HOME_CONFIG}")/state.json" "${trace_id}" "${field}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
trace, field = sys.argv[2], sys.argv[3]
if not path.exists():
    raise SystemExit(0)
state = json.loads(path.read_text())
for entry in state.get("worktrees") or []:
    if entry.get("traceId") == trace:
        value = entry.get(field, "")
        print("" if value is None else value)
        break
PY
}

homestate_worktree_count() {
  local trace_id="$1"
  python3 - "$(dirname "${HOME_CONFIG}")/state.json" "${trace_id}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
trace = sys.argv[2]
count = 0
if path.exists():
    state = json.loads(path.read_text())
    count = sum(1 for e in (state.get("worktrees") or []) if e.get("traceId") == trace)
print(count)
PY
}

worktree_head_branch() {
  local trace_id="$1"
  local dir
  dir="$(worktree_for_trace "${trace_id}")"
  [[ -d "${dir}" ]] || return 1
  git -C "${dir}" rev-parse --abbrev-ref HEAD
}

wait_for_worktree_branch() {
  local trace_id="$1"
  local want_branch="$2"
  local timeout_secs="$3"
  local start now branch=""
  start=$(date +%s)
  while true; do
    branch="$(worktree_head_branch "${trace_id}" 2>/dev/null || true)"
    if [[ "${branch}" == "${want_branch}" ]]; then
      echo "${branch}"
      return 0
    fi
    now=$(date +%s)
    if (( now - start >= timeout_secs )); then
      echo "${branch:-missing}"
      return 1
    fi
    sleep 1
  done
}

export_branch_line() {
  # `paseka export` is offline but writes into cwd, so run it in a scratch dir.
  local trace_id="$1"
  local scratch line=""
  scratch="$(mktemp -d)"
  (cd "${scratch}" && paseka export --trace "${trace_id}" --format md -C "${EVAL_ROOT}" >/dev/null 2>&1) || true
  line="$(grep -hE '^-[[:space:]]\*\*Branch:\*\*' "${scratch}"/*.md 2>/dev/null \
    | head -1 | sed 's/^-[[:space:]]\*\*Branch:\*\*[[:space:]]*//' || true)"
  rm -rf "${scratch}"
  printf '%s' "${line}"
}

origin_has_branch() {
  local branch="$1"
  git -C "${EVAL_ROOT}" ls-remote --heads origin "refs/heads/${branch}" 2>/dev/null | grep -q .
}

operator_approve_publish() {
  local trace_id="$1"
  local task_id="$2"
  local pr_title="$3"
  local draft="$4"
  local args=(
    proposal approve
    --trace "${trace_id}"
    --task "${task_id}"
    -C "${EVAL_ROOT}"
  )
  if [[ -n "${pr_title}" ]]; then
    args+=(--pr-title "${pr_title}")
  fi
  if [[ "${draft}" == "true" ]]; then
    args+=(--draft)
  fi
  echo "operator publish: paseka ${args[*]}" >&2
  paseka "${args[@]}"
}

# run_pr_delivery_flow drives 017 end to end: isolated proposal -> publish (push head +
# forge upsert) -> gate held open while the PR is open -> host merge -> reconcile.
run_pr_delivery_flow() {
  local case_id="$1"
  local trace_id="$2"
  local task_body_file="$3"
  local timeout_secs="$4"
  local title="$5"
  local bee="$6"
  local intent="$7"
  local review="$8"
  local pr_title="$9"
  local draft="${10}"
  local create_out initial_task final_status approve_out pr_url branch head_ref
  local -a create_args

  PR_DELIVERY_TASK_ID="_review"
  PR_DELIVERY_INITIAL_TASK_ID=""
  PR_DELIVERY_BRANCH="paseka/${trace_id}"
  PR_DELIVERY_PR_URL=""
  PR_DELIVERY_REPLAY=""

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
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "${create_out}"
  initial_task="$(printf '%s\n' "${create_out}" | awk '/^  task:/{print $2; exit}')"
  if [[ -z "${initial_task}" ]]; then
    echo "pr delivery oracle: initial task id missing" >&2
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  PR_DELIVERY_INITIAL_TASK_ID="${initial_task}"
  echo "initial work task=${initial_task}"
  if ! wait_for_success_scoring "${case_id}" "${trace_id}" "${initial_task}" completed "${timeout_secs}" >/dev/null; then
    echo "pr delivery oracle: initial work did not complete" >&2
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi

  if ! final_status="$(wait_for_expected_task_status "${trace_id}" "${PR_DELIVERY_TASK_ID}" waiting_review "${timeout_secs}")"; then
    echo "pr delivery oracle: final gate status=${final_status}, want waiting_review" >&2
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "final gate status=${final_status}"
  if ! commit_trace_worktree "${trace_id}" "eval pr delivery: isolated head"; then
    echo "pr delivery oracle: worktree commit failed" >&2
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi

  if ! approve_out="$(operator_approve_publish "${trace_id}" "${PR_DELIVERY_TASK_ID}" "${pr_title}" "${draft}" 2>&1)"; then
    echo "${approve_out}" >&2
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "${approve_out}"
  pr_url="$(printf '%s\n' "${approve_out}" | awk '/^[[:space:]]*pull request:/{print $3; exit}')"
  if [[ -z "${pr_url}" ]]; then
    echo "pr delivery oracle: approve printed no pull request line" >&2
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  PR_DELIVERY_PR_URL="${pr_url}"
  echo "published pull request=${pr_url}"

  if [[ "$(task_show_field "${trace_id}" "${PR_DELIVERY_TASK_ID}" status)" != "waiting_review" ]]; then
    echo "pr delivery oracle: final gate left waiting_review after publish" >&2
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if ! origin_has_branch "${PR_DELIVERY_BRANCH}"; then
    echo "pr delivery oracle: head ${PR_DELIVERY_BRANCH} missing on origin" >&2
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if [[ "$(homestate_pull_request_field "${trace_id}" state)" != "open" ]]; then
    echo "pr delivery oracle: homestate pull request state is not open" >&2
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "final gate held open while pull request is open"

  head_ref="$(git -C "${EVAL_ROOT}" symbolic-ref --short HEAD)"
  if ! check_forge_upsert_request "${case_id}" "${trace_id}" "${PR_DELIVERY_BRANCH}" "${head_ref}" "${pr_title}"; then
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi

  mark_forge_pr_merged "${trace_id}"
  echo "pull request marked merged; waiting for runtime reconcile..."
  if ! final_status="$(wait_for_expected_task_status "${trace_id}" "${PR_DELIVERY_TASK_ID}" completed "${timeout_secs}")"; then
    echo "pr delivery oracle: final gate status=${final_status} after merge, want completed" >&2
    PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  PR_DELIVERY_REPLAY="$(collect_replay_lines "${trace_id}")"
  return 0
}

check_forge_upsert_request() {
  local case_id="$1"
  local trace_id="$2"
  local want_head="$3"
  local want_base="$4"
  local want_title="$5"
  local want_body_marker want_draft upsert
  want_body_marker="$(read_case_field "${case_id}" score_expect_pr_body_marker)"
  want_draft="$(read_case_field "${case_id}" operator_pr_draft)"
  upsert="$(forge_upsert_request "${trace_id}")"
  if [[ -z "${upsert}" ]]; then
    echo "pr delivery oracle: forge recorded no upsert for ${trace_id}" >&2
    return 1
  fi
  if ! FORGE_UPSERT="${upsert}" python3 - \
    "${want_head}" "${want_base}" "${want_title}" "${want_body_marker}" "${want_draft}" <<'PY'
import json
import os
import sys

row = json.loads(os.environ["FORGE_UPSERT"])
want_head, want_base, want_title, want_body, want_draft = sys.argv[1:6]
if row.get("head") != want_head:
    raise SystemExit(f"forge upsert head={row.get('head')!r}, want {want_head!r}")
if row.get("base") != want_base:
    raise SystemExit(f"forge upsert base={row.get('base')!r}, want {want_base!r}")
if want_title and row.get("title") != want_title:
    raise SystemExit(f"forge upsert title={row.get('title')!r}, want {want_title!r}")
if want_body and want_body not in (row.get("body") or ""):
    raise SystemExit(f"forge upsert body missing {want_body!r}")
if want_draft == "true" and not row.get("draft"):
    raise SystemExit("forge upsert draft=false, want true")
PY
  then
    return 1
  fi
  echo "forge upsert: head=${want_head} base=${want_base} draft=${want_draft:-false} title/body as expected"
  return 0
}

# check_pr_delivery_oracle scores the delivery choreography: publish-side state, the
# reconcile completion (agent=runtime), forge payload, cleanup, and the absence of a
# local merge. The delivered head is tested separately by check_pr_head_tests.
check_pr_delivery_oracle() {
  local case_id="$1"
  local trace_id="$2"
  local expect_body_marker="$3"
  local expect_no_local_merge="$4"
  local plans ready bodies proposals successes completions feedback runtime_completed
  local summary seed_sha head_now

  if [[ "$(task_show_field "${trace_id}" "${PR_DELIVERY_TASK_ID}" status)" != "completed" ]]; then
    echo "pr delivery oracle: final gate is not completed" >&2
    return 1
  fi
  summary="$(task_show_field "${trace_id}" "${PR_DELIVERY_TASK_ID}" summary)"
  if [[ "${summary}" != *"Pull request merged"* || "${summary}" != *"${PR_DELIVERY_PR_URL}"* ]]; then
    echo "pr delivery oracle: final summary=${summary@Q}, want reconcile merge summary with PR url" >&2
    return 1
  fi

  plans="$(replay_event_count "${PR_DELIVERY_REPLAY}" INSIGHT task.plan)"
  ready="$(replay_event_count "${PR_DELIVERY_REPLAY}" SIGNAL task.ready)"
  bodies="$(replay_event_count "${PR_DELIVERY_REPLAY}" INSIGHT pr.body)"
  proposals="$(replay_event_count "${PR_DELIVERY_REPLAY}" MUTATION code.proposal.isolated)"
  successes="$(replay_event_count "${PR_DELIVERY_REPLAY}" VERIFICATION verification.success)"
  completions="$(replay_event_count "${PR_DELIVERY_REPLAY}" VERIFICATION task.completed)"
  feedback="$(replay_event_count "${PR_DELIVERY_REPLAY}" INSIGHT human.feedback)"
  [[ "${plans}" == "2" ]] || { echo "pr delivery oracle: task.plan count=${plans}, want 2" >&2; return 1; }
  [[ "${ready}" == "1" ]] || { echo "pr delivery oracle: task.ready count=${ready}, want 1" >&2; return 1; }
  [[ "${bodies}" == "1" ]] || { echo "pr delivery oracle: pr.body count=${bodies}, want 1" >&2; return 1; }
  [[ "${proposals}" == "1" ]] || { echo "pr delivery oracle: isolated proposal count=${proposals}, want 1" >&2; return 1; }
  [[ "${successes}" == "1" ]] || { echo "pr delivery oracle: verification.success count=${successes}, want 1" >&2; return 1; }
  [[ "${completions}" == "2" ]] || { echo "pr delivery oracle: task.completed count=${completions}, want 2" >&2; return 1; }
  [[ "${feedback}" == "0" ]] || { echo "pr delivery oracle: human.feedback count=${feedback}, want 0" >&2; return 1; }
  runtime_completed="$(printf '%s\n' "${PR_DELIVERY_REPLAY}" | grep -cE 'VERIFICATION[[:space:]]+\(task.completed\) agent=runtime' || true)"
  [[ "${runtime_completed}" == "1" ]] || { echo "pr delivery oracle: runtime task.completed count=${runtime_completed}, want 1" >&2; return 1; }

  if [[ -n "${expect_body_marker}" ]]; then
    local upsert
    upsert="$(forge_upsert_request "${trace_id}")"
    if ! FORGE_UPSERT="${upsert}" python3 - "${expect_body_marker}" <<'PY'
import json
import os
import sys

row = json.loads(os.environ.get("FORGE_UPSERT") or "{}")
if sys.argv[1] not in (row.get("body") or ""):
    raise SystemExit(f"forge upsert body missing {sys.argv[1]!r}")
PY
    then
      return 1
    fi
  fi

  if [[ -d "$(worktree_for_trace "${trace_id}")" ]]; then
    echo "pr delivery oracle: worktree still present after merge" >&2
    return 1
  fi
  # The local head branch is cleanup debt under pull_request delivery: reconcile drops
  # it with `git branch -d`, which refuses an unmerged head, and purge removes it on
  # the next reset. Assert only that it is no longer checked out anywhere.
  if git -C "${EVAL_ROOT}" worktree list --porcelain | grep -q "branch refs/heads/${PR_DELIVERY_BRANCH}$"; then
    echo "pr delivery oracle: ${PR_DELIVERY_BRANCH} is still checked out in a worktree" >&2
    return 1
  fi
  if [[ -n "$(homestate_pull_request_field "${trace_id}" url)" ]]; then
    echo "pr delivery oracle: homestate pull request identity not dropped" >&2
    return 1
  fi

  if [[ "${expect_no_local_merge}" == "true" ]]; then
    seed_sha="$(cat "${EVAL_META_DIR}/seed-sha" 2>/dev/null || true)"
    head_now="$(git -C "${EVAL_ROOT}" rev-parse HEAD)"
    if [[ -n "${seed_sha}" && "${head_now}" != "${seed_sha}" ]]; then
      echo "pr delivery oracle: colony HEAD moved to ${head_now}, want seed ${seed_sha} (pull_request must not merge locally)" >&2
      return 1
    fi
    if grep -q 'return a + b' "${EVAL_ROOT}/pkg/calc/calc.go" 2>/dev/null; then
      echo "pr delivery oracle: fix landed on the colony default branch (must stay on the pushed head)" >&2
      return 1
    fi
  fi

  echo "pr delivery oracle: published ${PR_DELIVERY_PR_URL}, gate reconciled, no local merge"
  return 0
}

# check_pr_head_tests clones the pushed head from the bare origin and runs the case
# oracle there: under pull_request delivery the deliverable is the branch, not the
# colony checkout (which is still the broken seed by design).
check_pr_head_tests() {
  local case_id="$1"
  local branch="$2"
  local cmd workdir tmp
  cmd="$(read_case_field "${case_id}" oracle_command)"
  workdir="$(read_case_field "${case_id}" oracle_workdir)"
  tmp="$(mktemp -d)"
  if ! git clone -q --branch "${branch}" "${FORGE_BARE_ORIGIN}" "${tmp}" >/dev/null 2>&1; then
    rm -rf "${tmp}"
    echo "pr head oracle: clone of pushed head ${branch} failed" >&2
    return 1
  fi
  if [[ "${workdir}" != "." ]]; then
    tmp="${tmp}/${workdir}"
  fi
  if ! (cd "${tmp}" && bash -lc "${cmd}"); then
    rm -rf "${tmp}"
    echo "pr head oracle: ${cmd} failed on pushed head ${branch}" >&2
    return 1
  fi
  rm -rf "${tmp}"
  echo "pr head oracle: ${cmd} passed on pushed head ${branch}"
  return 0
}

# run_worktree_branch_flow drives 018: first isolated dispatch creates the worktree on
# the default branch, the builder's INSIGHT/worktree.branch renames it in place, and a
# second task in the same trail reuses that worktree without reverting the name.
run_worktree_branch_flow() {
  local case_id="$1"
  local trace_id="$2"
  local task_body_file="$3"
  local timeout_secs="$4"
  local title="$5"
  local bee="$6"
  local intent="$7"
  local review="$8"
  local want_branch="$9"
  local second="${10}"
  local create_out first_task second_out second_task status observed

  WORKTREE_BRANCH_TASK_ID=""
  WORKTREE_BRANCH_SECOND_TASK_ID=""
  WORKTREE_BRANCH_DEFAULT="paseka/${trace_id}"
  WORKTREE_BRANCH_WANTED="${want_branch}"
  WORKTREE_BRANCH_REPLAY=""

  create_out="$(paseka task create --trace "${trace_id}" --title "${title}" \
    --file "${task_body_file}" --bee "${bee}" --intent "${intent}" --review "${review}" \
    --autorun -C "${EVAL_ROOT}" 2>&1)" || {
    echo "${create_out}" >&2
    WORKTREE_BRANCH_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  }
  echo "${create_out}"
  first_task="$(printf '%s\n' "${create_out}" | awk '/^  task:/{print $2; exit}')"
  if [[ -z "${first_task}" ]]; then
    echo "worktree branch oracle: initial task id missing" >&2
    WORKTREE_BRANCH_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  WORKTREE_BRANCH_TASK_ID="${first_task}"
  echo "first task=${first_task}"
  if ! wait_for_success_scoring "${case_id}" "${trace_id}" "${first_task}" completed "${timeout_secs}" >/dev/null; then
    echo "worktree branch oracle: first task did not complete" >&2
    WORKTREE_BRANCH_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi

  if ! status="$(wait_for_worktree_branch "${trace_id}" "${want_branch}" "${timeout_secs}")"; then
    echo "worktree branch oracle: branch=${status}, want ${want_branch}" >&2
    WORKTREE_BRANCH_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "worktree branch renamed to ${status}"

  if [[ "${second}" == "true" ]]; then
    second_out="$(paseka task create --trace "${trace_id}" --title "${title} (reuse)" \
      --file "${task_body_file}" --bee "${bee}" --intent "${intent}" --review "${review}" \
      --autorun -C "${EVAL_ROOT}" 2>&1)" || {
      echo "${second_out}" >&2
      WORKTREE_BRANCH_REPLAY="$(collect_replay_lines "${trace_id}")"
      return 1
    }
    echo "${second_out}"
    second_task="$(printf '%s\n' "${second_out}" | awk '/^  task:/{print $2; exit}')"
    if [[ -z "${second_task}" || "${second_task}" == "${first_task}" ]]; then
      echo "worktree branch oracle: second task id=${second_task@Q}" >&2
      WORKTREE_BRANCH_REPLAY="$(collect_replay_lines "${trace_id}")"
      return 1
    fi
    WORKTREE_BRANCH_SECOND_TASK_ID="${second_task}"
    echo "second task=${second_task}"
    if ! wait_for_success_scoring "${case_id}" "${trace_id}" "${second_task}" completed "${timeout_secs}" >/dev/null; then
      echo "worktree branch oracle: second task did not complete" >&2
      WORKTREE_BRANCH_REPLAY="$(collect_replay_lines "${trace_id}")"
      return 1
    fi
    observed="$(cat "${EVAL_META_DIR}/builder-branch-2" 2>/dev/null || true)"
    if [[ "${observed}" != "${want_branch}" ]]; then
      echo "worktree branch oracle: second dispatch saw branch=${observed:-missing}, want ${want_branch}" >&2
      WORKTREE_BRANCH_REPLAY="$(collect_replay_lines "${trace_id}")"
      return 1
    fi
    echo "second dispatch reused ${observed}"
  fi

  WORKTREE_BRANCH_REPLAY="$(collect_replay_lines "${trace_id}")"
  return 0
}

# check_worktree_branch_oracle scores the worktree-branch contract: default name at
# create, in-place rename by INSIGHT/worktree.branch, reuse by the next dispatch, one
# worktree per trail, and no push (this case stays on local_merge).
check_worktree_branch_oracle() {
  local trace_id="$1"
  local expect_reuse="$2"
  local expect_no_origin_push="$3"
  local dir head_branch default_branch entries seed_sha export_line
  local branches proposals successes observed_first observed_second

  dir="$(worktree_for_trace "${trace_id}")"
  default_branch="${WORKTREE_BRANCH_DEFAULT}"
  if [[ ! -d "${dir}" ]]; then
    echo "worktree branch oracle: worktree missing: ${dir}" >&2
    return 1
  fi
  head_branch="$(worktree_head_branch "${trace_id}" 2>/dev/null || true)"
  if [[ "${head_branch}" != "${WORKTREE_BRANCH_WANTED}" ]]; then
    echo "worktree branch oracle: worktree head branch=${head_branch@Q}, want ${WORKTREE_BRANCH_WANTED@Q}" >&2
    return 1
  fi
  if ! git -C "${EVAL_ROOT}" worktree list --porcelain | grep -q "^worktree ${dir}$"; then
    echo "worktree branch oracle: ${dir} missing from git worktree list" >&2
    return 1
  fi
  # The default ref must be gone: the branch was renamed, not replaced.
  if git -C "${EVAL_ROOT}" show-ref --verify --quiet "refs/heads/${default_branch}"; then
    echo "worktree branch oracle: default branch ${default_branch} still exists (rename expected)" >&2
    return 1
  fi
  entries="$(git -C "${EVAL_ROOT}" worktree list --porcelain | grep -c '^worktree ' || true)"
  if [[ "${entries}" != "2" ]]; then
    echo "worktree branch oracle: ${entries} worktrees registered, want 2 (colony root + this trail)" >&2
    return 1
  fi

  if [[ "$(homestate_worktree_count "${trace_id}")" != "1" ]]; then
    echo "worktree branch oracle: registry has $(homestate_worktree_count "${trace_id}") entries for ${trace_id}, want 1" >&2
    return 1
  fi
  if [[ "$(homestate_worktree_field "${trace_id}" branch)" != "${WORKTREE_BRANCH_WANTED}" ]]; then
    echo "worktree branch oracle: registry branch=$(homestate_worktree_field "${trace_id}" branch@Q), want ${WORKTREE_BRANCH_WANTED@Q}" >&2
    return 1
  fi
  if [[ "$(homestate_worktree_field "${trace_id}" path)" != "${dir}" ]]; then
    echo "worktree branch oracle: registry path=$(homestate_worktree_field "${trace_id}" path@Q), want ${dir@Q}" >&2
    return 1
  fi
  seed_sha="$(cat "${EVAL_META_DIR}/seed-sha" 2>/dev/null || true)"
  if [[ -n "${seed_sha}" && "$(homestate_worktree_field "${trace_id}" baseSha)" != "${seed_sha}" ]]; then
    echo "worktree branch oracle: registry baseSha=$(homestate_worktree_field "${trace_id}" baseSha), want seed ${seed_sha}" >&2
    return 1
  fi

  observed_first="$(cat "${EVAL_META_DIR}/builder-branch-1" 2>/dev/null || true)"
  if [[ "${observed_first}" != "${default_branch}" ]]; then
    echo "worktree branch oracle: first dispatch branch=${observed_first:-missing}, want default ${default_branch}" >&2
    return 1
  fi
  if [[ -f "${EVAL_META_DIR}/branch-reject" ]]; then
    if ! grep -q 'schema_validation_failed' "${EVAL_META_DIR}/branch-reject"; then
      echo "worktree branch oracle: invalid branch ref was not refused at emit" >&2
      cat "${EVAL_META_DIR}/branch-reject" >&2
      return 1
    fi
  fi

  if [[ "${expect_reuse}" == "true" ]]; then
    observed_second="$(cat "${EVAL_META_DIR}/builder-branch-2" 2>/dev/null || true)"
    if [[ "${observed_second}" != "${WORKTREE_BRANCH_WANTED}" ]]; then
      echo "worktree branch oracle: second dispatch branch=${observed_second:-missing}, want ${WORKTREE_BRANCH_WANTED}" >&2
      return 1
    fi
  fi

  export_line="$(export_branch_line "${trace_id}")"
  if [[ "${export_line}" != "${WORKTREE_BRANCH_WANTED}" ]]; then
    echo "worktree branch oracle: export branch=${export_line@Q}, want ${WORKTREE_BRANCH_WANTED@Q}" >&2
    return 1
  fi

  # Both dispatch changes must live on the worktree branch only.
  local worktree_calc="${dir}/pkg/calc/calc.go"
  if [[ -f "${worktree_calc}" ]]; then
    if ! grep -q 'return a + b' "${worktree_calc}"; then
      echo "worktree branch oracle: first change missing on the worktree branch" >&2
      return 1
    fi
    if ! grep -q 'func Product' "${worktree_calc}"; then
      echo "worktree branch oracle: reuse dispatch did not amend the same worktree file" >&2
      return 1
    fi
  fi
  if grep -q 'func Product' "${EVAL_ROOT}/pkg/calc/calc.go" 2>/dev/null; then
    echo "worktree branch oracle: worktree change leaked onto the colony default branch" >&2
    return 1
  fi

  branches="$(replay_event_count "${WORKTREE_BRANCH_REPLAY}" INSIGHT worktree.branch)"
  proposals="$(replay_event_count "${WORKTREE_BRANCH_REPLAY}" MUTATION code.proposal.isolated)"
  successes="$(replay_event_count "${WORKTREE_BRANCH_REPLAY}" VERIFICATION verification.success)"
  [[ "${branches}" == "1" ]] || { echo "worktree branch oracle: worktree.branch count=${branches}, want 1" >&2; return 1; }
  [[ "${proposals}" == "2" ]] || { echo "worktree branch oracle: isolated proposal count=${proposals}, want 2" >&2; return 1; }
  [[ "${successes}" == "2" ]] || { echo "worktree branch oracle: verification.success count=${successes}, want 2" >&2; return 1; }

  if [[ "${expect_no_origin_push}" == "true" ]]; then
    if git -C "${EVAL_ROOT}" ls-remote --heads origin >/dev/null 2>&1; then
      if origin_has_branch "${WORKTREE_BRANCH_WANTED}" || origin_has_branch "${default_branch}"; then
        echo "worktree branch oracle: worktree branch was pushed to origin" >&2
        return 1
      fi
      echo "worktree branch oracle: nothing pushed to origin"
    else
      echo "worktree branch oracle: origin unreachable, skipped no-push check"
    fi
  fi

  echo "worktree branch oracle: ${default_branch} → ${WORKTREE_BRANCH_WANTED}, reused on second dispatch, local only"
  return 0
}

homestate_runtime_field() {
  # Machine-local runtime registry row; empty output means the key is absent.
  python3 - "$(dirname "${HOME_CONFIG}")/state.json" "$1" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
field = sys.argv[2]
state = json.loads(path.read_text()) if path.exists() else {}
entry = state.get("runtime") or {}
value = entry.get(field, "")
print("" if value is None else value)
PY
}

inflight_run_dir() {
  # Newest run dir whose status.json still says running with a live pid.
  python3 - "${EVAL_ROOT}/.paseka/runs/${1}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
newest = None
if root.exists():
    for entry in sorted(root.iterdir()):
        status = entry / "status.json"
        if not entry.is_dir() or not status.exists():
            continue
        try:
            snap = json.loads(status.read_text())
        except ValueError:
            continue
        if snap.get("state") == "running" and snap.get("pid"):
            newest = entry
if newest is not None:
    print(newest)
PY
}

pid_alive() {
  local pid="$1"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" >/dev/null 2>&1
}

wait_for_pid_exit() {
  local pid="$1"
  local timeout_secs="$2"
  local start
  start=$(date +%s)
  while pid_alive "${pid}"; do
    if (( $(date +%s) - start >= timeout_secs )); then
      return 1
    fi
    sleep 1
  done
  return 0
}

wait_for_runtime_registered() {
  local timeout_secs="$1"
  local start pid
  start=$(date +%s)
  while true; do
    pid="$(homestate_runtime_field pid)"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && (( pid > 0 )); then
      echo "${pid}"
      return 0
    fi
    if (( $(date +%s) - start >= timeout_secs )); then
      return 1
    fi
    sleep 1
  done
}

runtime_status_line() {
  paseka status -C "${EVAL_ROOT}" 2>/dev/null | grep -E '^Runtime:' | head -1
}

runtime_status_attention() {
  paseka status -C "${EVAL_ROOT}" 2>/dev/null | sed -n '/^Attention:/,$p' | grep -E '^\s+runtime stale' | head -1
}

wait_for_inflight_run() {
  local trace_id="$1"
  local timeout_secs="$2"
  local start dir
  start=$(date +%s)
  while true; do
    dir="$(inflight_run_dir "${trace_id}")"
    if [[ -n "${dir}" ]]; then
      echo "${dir}"
      return 0
    fi
    if (( $(date +%s) - start >= timeout_secs )); then
      return 1
    fi
    sleep 1
  done
}

# run_clean_shutdown_flow drives 019 through three shutdown windows while one bee run
# is in flight: clean SIGTERM (exit 0, registry cleared, no drain), unclean SIGKILL
# (registry left running → `stale`), then restart (no recovery, no re-dispatch) and a
# final clean stop that heals the registry.
run_clean_shutdown_flow() {
  local case_id="$1"
  local trace_id="$2"
  local task_body_file="$3"
  local timeout_secs="$4"
  local title="$5"
  local bee="$6"
  local intent="$7"
  local review="$8"
  local create_out task_id run_dir bee_pid runtime_pid log_file status_line killed_pid

  SHUTDOWN_TASK_ID=""
  SHUTDOWN_RUN_DIR=""
  SHUTDOWN_BEE_PID=""
  SHUTDOWN_REPLAY=""
  log_file="${EVAL_META_DIR}/paseka-run.log"

  create_out="$(paseka task create --trace "${trace_id}" --title "${title}" \
    --file "${task_body_file}" --bee "${bee}" --intent "${intent}" --review "${review}" \
    --autorun -C "${EVAL_ROOT}" 2>&1)" || {
    echo "${create_out}" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  }
  echo "${create_out}"
  task_id="$(printf '%s\n' "${create_out}" | awk '/^  task:/{print $2; exit}')"
  if [[ -z "${task_id}" ]]; then
    echo "shutdown oracle: task id missing" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  SHUTDOWN_TASK_ID="${task_id}"
  echo "in-flight task=${task_id}"

  if ! run_dir="$(wait_for_inflight_run "${trace_id}" "$(( timeout_secs < 60 ? timeout_secs : 60 ))")"; then
    echo "shutdown oracle: no in-flight bee run appeared" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  SHUTDOWN_RUN_DIR="${run_dir}"
  bee_pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pid"])' "${run_dir}/status.json")"
  SHUTDOWN_BEE_PID="${bee_pid}"
  runtime_pid="$(homestate_runtime_field pid)"
  if ! [[ "${runtime_pid}" =~ ^[0-9]+$ ]] || ! pid_alive "${runtime_pid}"; then
    echo "shutdown oracle: runtime registry has no live pid (got ${runtime_pid@Q})" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "runtime pid=${runtime_pid} bee pid=${bee_pid} run_dir=${run_dir}"

  # Phase A: clean SIGTERM must exit 0, log a clean stop, and clear the registry.
  kill -TERM "${runtime_pid}"
  if ! wait_for_pid_exit "${runtime_pid}" 30; then
    echo "shutdown oracle: runtime pid ${runtime_pid} survived SIGTERM" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if ! grep -q 'hive runtime stopped' "${log_file}" 2>/dev/null; then
    echo "shutdown oracle: runtime log lacks 'hive runtime stopped'" >&2
    tail -5 "${log_file}" >&2 || true
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if [[ -n "$(homestate_runtime_field pid)" ]]; then
    echo "shutdown oracle: runtime registry not cleared after clean stop" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  status_line="$(runtime_status_line)"
  if [[ "${status_line}" == *"alive=true"* ]]; then
    echo "shutdown oracle: status still reports a live runtime: ${status_line}" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "phase A clean SIGTERM: exited, registry cleared (${status_line:-no runtime line})"

  # No drain: the in-flight adapter is not signalled, its run dir stays unfinished.
  if ! pid_alive "${bee_pid}"; then
    echo "shutdown oracle: bee pid ${bee_pid} died with the runtime (no drain expected)" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if [[ -f "${run_dir}/result.json" || -f "${run_dir}/summary.md" ]]; then
    echo "shutdown oracle: orphaned run dir looks finished (result.json/summary.md)" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "phase A no drain: bee pid ${bee_pid} alive, run dir unfinished"
  echo "${bee_pid}" > "${EVAL_META_DIR}/shutdown-no-drain"
  kill -KILL "${bee_pid}" >/dev/null 2>&1 || true
  wait_for_pid_exit "${bee_pid}" 10 || true

  # Phase B: SIGKILL leaves the registry claiming a running runtime with a dead pid.
  ensure_runtime
  if ! killed_pid="$(wait_for_runtime_registered 30)"; then
    echo "shutdown oracle: runtime did not re-register after restart" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  kill -KILL "${killed_pid}"
  if ! wait_for_pid_exit "${killed_pid}" 30; then
    echo "shutdown oracle: runtime pid ${killed_pid} survived SIGKILL" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if [[ "$(homestate_runtime_field status)" != "running" || "$(homestate_runtime_field pid)" != "${killed_pid}" ]]; then
    echo "shutdown oracle: registry after SIGKILL = status $(homestate_runtime_field status@Q) pid $(homestate_runtime_field pid@Q)" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  status_line="$(runtime_status_line)"
  if [[ "${status_line}" != *"stale"* || "${status_line}" != *"alive=false"* ]]; then
    echo "shutdown oracle: status line=${status_line@Q}, want stale + alive=false" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if [[ -z "$(runtime_status_attention)" ]]; then
    echo "shutdown oracle: status lacks 'runtime stale' attention" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if paseka status --check -C "${EVAL_ROOT}" >/dev/null 2>&1; then
    echo "shutdown oracle: status --check passed with a stale runtime" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "${killed_pid}" > "${EVAL_META_DIR}/shutdown-stale-registry"
  echo "phase B SIGKILL: registry kept running pid=${killed_pid}, status reports stale"

  # Phase C: restart performs no recovery; the task stays running and is not re-dispatched.
  ensure_runtime
  if ! wait_for_runtime_registered 30; then
    echo "shutdown oracle: runtime did not re-register for phase C" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  sleep 5
  if [[ "$(task_show_field "${trace_id}" "${task_id}" status)" != "running" ]]; then
    echo "shutdown oracle: task status=$(task_show_field "${trace_id}" "${task_id}" status@Q) after restart, want running" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if [[ "$(cat "${EVAL_META_DIR}/builder-runs")" != "1" ]]; then
    echo "shutdown oracle: builder-runs=$(cat "${EVAL_META_DIR}/builder-runs") after restart, want 1 (no re-dispatch)" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "phase C restart: task still running, no re-dispatch"
  echo "${task_id}" > "${EVAL_META_DIR}/shutdown-restart-no-recovery"

  runtime_pid="$(homestate_runtime_field pid)"
  kill -TERM "${runtime_pid}"
  if ! wait_for_pid_exit "${runtime_pid}" 30; then
    echo "shutdown oracle: runtime pid ${runtime_pid} survived the final SIGTERM" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  if [[ -n "$(homestate_runtime_field pid)" ]]; then
    echo "shutdown oracle: registry not cleared after the final clean stop" >&2
    SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
    return 1
  fi
  echo "phase C clean stop: registry cleared again"
  echo "clean-sigterm" > "${EVAL_META_DIR}/shutdown-clean-sigterm"

  SHUTDOWN_REPLAY="$(collect_replay_lines "${trace_id}")"
  return 0
}

# check_clean_shutdown_oracle scores the durable outcome: no runtime left behind, the
# unfinished run dir, the task stuck in `running`, and the event chain that proves no
# proposal was ever published for the orphaned run.
check_clean_shutdown_oracle() {
  local trace_id="$1"
  local expect_stale_after_kill="$2"
  local status_line attention plans ready consumes proposals completions
  local run_dir status_state

  for marker in shutdown-clean-sigterm shutdown-no-drain shutdown-restart-no-recovery; do
    if [[ ! -f "${EVAL_META_DIR}/${marker}" ]]; then
      echo "shutdown oracle: phase marker ${marker} missing (flow did not complete)" >&2
      return 1
    fi
  done
  if [[ "${expect_stale_after_kill}" == "true" && ! -f "${EVAL_META_DIR}/shutdown-stale-registry" ]]; then
    echo "shutdown oracle: SIGKILL phase marker missing" >&2
    return 1
  fi

  status_line="$(runtime_status_line)"
  if [[ "${status_line}" == *"alive=true"* ]]; then
    echo "shutdown oracle: a runtime is still alive after the case: ${status_line}" >&2
    return 1
  fi
  if [[ -n "$(runtime_status_attention)" ]]; then
    echo "shutdown oracle: stale runtime attention survived the final clean stop" >&2
    return 1
  fi
  if [[ -n "$(homestate_runtime_field pid)" ]]; then
    echo "shutdown oracle: runtime registry still holds a runtime row" >&2
    return 1
  fi

  run_dir="${SHUTDOWN_RUN_DIR}"
  status_state="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("state",""))' "${run_dir}/status.json" 2>/dev/null || true)"
  if [[ "${status_state}" != "running" ]]; then
    echo "shutdown oracle: orphaned run status=${status_state@Q}, want running" >&2
    return 1
  fi
  if [[ -f "${run_dir}/result.json" || -f "${run_dir}/summary.md" ]]; then
    echo "shutdown oracle: orphaned run gained result.json/summary.md" >&2
    return 1
  fi
  if [[ "$(task_show_field "${trace_id}" "${SHUTDOWN_TASK_ID}" status)" != "running" ]]; then
    echo "shutdown oracle: task is not stuck in running after shutdown" >&2
    return 1
  fi

  plans="$(replay_event_count "${SHUTDOWN_REPLAY}" INSIGHT task.plan)"
  ready="$(replay_event_count "${SHUTDOWN_REPLAY}" SIGNAL task.ready)"
  consumes="$(replay_event_count "${SHUTDOWN_REPLAY}" SIGNAL energy.consume)"
  proposals="$(replay_event_count "${SHUTDOWN_REPLAY}" MUTATION code.proposal.isolated)"
  completions="$(replay_event_count "${SHUTDOWN_REPLAY}" VERIFICATION task.completed)"
  [[ "${plans}" == "1" ]] || { echo "shutdown oracle: task.plan count=${plans}, want 1" >&2; return 1; }
  [[ "${ready}" == "1" ]] || { echo "shutdown oracle: task.ready count=${ready}, want 1" >&2; return 1; }
  [[ "${consumes}" == "1" ]] || { echo "shutdown oracle: energy.consume count=${consumes}, want 1" >&2; return 1; }
  [[ "${proposals}" == "0" ]] || { echo "shutdown oracle: isolated proposal count=${proposals}, want 0 (no runtime to publish)" >&2; return 1; }
  [[ "${completions}" == "0" ]] || { echo "shutdown oracle: task.completed count=${completions}, want 0" >&2; return 1; }

  echo "shutdown oracle: clean stop clears the registry, SIGKILL leaves it stale, no drain and no recovery"
  return 0
}

# kill_inflight_bees terminates bee processes the runtime still considers in flight for
# a trace. Shutdown deliberately orphans them (case 019 pins that), so the harness must
# not leak them into the next case.
kill_inflight_bees() {
  local trace_id="$1"
  local dir pid
  while IFS= read -r dir; do
    [[ -z "${dir}" ]] && continue
    pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("pid",""))' "${dir}/status.json" 2>/dev/null || true)"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && pid_alive "${pid}"; then
      kill -KILL "${pid}" >/dev/null 2>&1 || true
      echo "cleanup: killed in-flight bee pid ${pid} (${dir})"
    fi
  done < <(find "${EVAL_ROOT}/.paseka/runs/${trace_id}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
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
