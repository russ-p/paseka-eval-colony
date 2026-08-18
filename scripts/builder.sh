#!/usr/bin/env bash
# Scripted eval builder: apply broken/expect trees per fault mode.
# Modes: scripted (broken then expect), always_broken, first_pass (expect on run 1),
# inject-mutation (expect on first builder run — runner injected the broken proposal),
# deferred_emit (015: --defer context.note then expect; exit 0 → flush before run.summary),
# deferred_fail (015: --defer then exit 1 → pending stays for flush --discard),
# ready_before_plan (live task.ready then deferred plan; first builder pass applies expect/),
# write_comb (014: write trail comb then expect; scan-flush on success),
# write_comb_fail (014: write comb then exit 1 — no artifact.written),
# deferred_artifact (014+015: --defer artifact.written; scan flush skipped when deferred pending).
set -euo pipefail

root="${PASEKA_COLONY_ROOT:?missing PASEKA_COLONY_ROOT}"
workspace="${PASEKA_WORKSPACE:?missing PASEKA_WORKSPACE}"
eval_dir="${root}/.eval"
case_dir_file="${eval_dir}/case-dir"
runs_file="${eval_dir}/builder-runs"
fault_mode_file="${eval_dir}/fault-mode"

if [[ ! -f "${case_dir_file}" ]]; then
  echo "eval builder: missing ${case_dir_file} (run runner/reset.sh first)" >&2
  exit 1
fi

case_dir="$(cat "${case_dir_file}")"
fault_mode="scripted"
[[ -f "${fault_mode_file}" ]] && fault_mode="$(cat "${fault_mode_file}")"

runs=0
[[ -f "${runs_file}" ]] && runs="$(cat "${runs_file}")"
runs=$((runs + 1))
echo "${runs}" > "${runs_file}"

# Optional kill-window hold: increment builder-runs first so the harness can see
# activity, then sleep so paseka kill lands while the adapter is still in-flight.
hold=0
hold_file="${eval_dir}/builder-hold-secs"
[[ -f "${hold_file}" ]] && hold="$(cat "${hold_file}")"
if [[ "${hold}" =~ ^[0-9]+$ ]] && (( hold > 0 )); then
  echo "eval builder: holding ${hold}s for operator kill window (run ${runs})"
  sleep "${hold}"
fi

cd "${workspace}"

apply_broken() {
  if [[ -d "${case_dir}/broken/pkg" ]]; then
    rsync -a "${case_dir}/broken/pkg/" "${workspace}/pkg/"
    echo "eval builder: applied broken/ tree (run ${runs})"
  elif [[ -f "${case_dir}/broken/bad.patch" ]]; then
    patch -p1 < "${case_dir}/broken/bad.patch"
    echo "eval builder: applied broken patch (run ${runs})"
  else
    echo "eval builder: no broken fixture for run ${runs}" >&2
    exit 1
  fi
}

apply_expect() {
  if [[ -d "${case_dir}/expect" ]]; then
    rsync -a "${case_dir}/expect/" "${workspace}/"
    echo "eval builder: applied expect/ tree (run ${runs})"
  else
    echo "eval builder: no expect/ directory for run ${runs}" >&2
    exit 1
  fi
}

emit_deferred_note() {
  local summary="$1"
  local emit_out
  emit_out="$(paseka event emit --defer --stdin -C "${root}" <<EOF
{"traceId":"${PASEKA_TRACE_ID}","agentId":"${PASEKA_AGENT_ID}","type":"INSIGHT","payload":{"kind":"context.note","summary":"${summary}"}}
EOF
)"
  echo "eval builder: deferred emit → ${emit_out}"
  if ! echo "${emit_out}" | grep -q '"deferred":true'; then
    echo "eval builder: expected deferred:true in emit response" >&2
    exit 1
  fi
}

write_eval_comb() {
  local comb_dir="${root}/.paseka/runs/${PASEKA_TRACE_ID}/artifacts"
  mkdir -p "${comb_dir}"
  cat > "${comb_dir}/research.md" <<'EOF'
# Research brief

Eval comb handoff notes for artifact protocol case.
EOF
  echo "hidden skip" > "${comb_dir}/.hidden"
  echo "tmp skip" > "${comb_dir}/scratch.tmp"
  echo "eval builder: wrote comb under ${comb_dir}"
}

emit_deferred_artifact() {
  local comb_dir ref emit_out
  comb_dir="${root}/.paseka/runs/${PASEKA_TRACE_ID}/artifacts"
  ref=".paseka/runs/${PASEKA_TRACE_ID}/artifacts/deferred.md"
  mkdir -p "${comb_dir}"
  echo "deferred comb note" > "${comb_dir}/deferred.md"
  echo "scan would announce this if flush ran" > "${comb_dir}/scan-extra.md"
  emit_out="$(paseka event emit --defer --stdin -C "${root}" <<EOF
{"traceId":"${PASEKA_TRACE_ID}","agentId":"${PASEKA_AGENT_ID}","type":"SIGNAL","payload":{"kind":"artifact.written","ref":"${ref}","artifactKind":"deferred","title":"Deferred"}}
EOF
)"
  echo "eval builder: deferred artifact.written → ${emit_out}"
  if ! echo "${emit_out}" | grep -q '"deferred":true'; then
    echo "eval builder: expected deferred:true in artifact emit response" >&2
    exit 1
  fi
}

if [[ "${fault_mode}" == "write_comb_fail" ]]; then
  write_eval_comb
  echo "eval builder: write_comb_fail exiting 1 (no artifact.written flush)" >&2
  exit 1
fi

if [[ "${fault_mode}" == "deferred_fail" ]]; then
  emit_deferred_note "eval-08 deferred fail probe"
  echo "eval builder: deferred_fail exiting 1 (pending must stay unpublished)" >&2
  exit 1
fi

if [[ "${fault_mode}" == "deferred_artifact" ]]; then
  emit_deferred_artifact
  apply_expect
elif [[ "${fault_mode}" == "deferred_emit" ]]; then
  emit_deferred_note "eval-08 deferred success note"
  apply_expect
elif [[ "${fault_mode}" == "write_comb" ]]; then
  if [[ -f "${eval_dir}/artifact-handoff" ]]; then
    apply_expect
  else
    write_eval_comb
    apply_expect
  fi
elif [[ "${fault_mode}" == "always_broken" ]]; then
  apply_broken
elif [[ "${fault_mode}" == "first_pass" || "${fault_mode}" == "inject-mutation" || "${fault_mode}" == "ready_before_plan" ]]; then
  # first_pass / ready_before_plan: correct on run 1. inject-mutation: builder never ran for v1;
  # verification.failed is the first dispatch, so apply expect/ (not broken/).
  apply_expect
  # After HITL reject, identical expect/ is a no-op — nudge a comment so the
  # runtime re-emits code.proposal.isolated for the second AFK pass.
  if [[ "${fault_mode}" == "first_pass" && "${runs}" -gt 1 && -f "${workspace}/pkg/calc/calc.go" ]]; then
    if ! grep -q 'revised after human.feedback' "${workspace}/pkg/calc/calc.go"; then
      sed -i 's|// Sum returns a + b\.|// Sum returns a + b (revised after human.feedback).|' \
        "${workspace}/pkg/calc/calc.go"
      echo "eval builder: nudged expect comment for rework proposal (run ${runs})"
    fi
  fi
elif [[ "${runs}" -eq 1 ]]; then
  apply_broken
else
  apply_expect
fi

# Runtime auto-publishes MUTATION/code.proposal.isolated from git diff when declared in bee YAML.
