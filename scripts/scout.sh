#!/usr/bin/env bash
# Scripted eval scout: classify feature.requested via direct dispatch (SIGNAL direct path).
# ready_before_plan: live task.ready then deferred task.plan (FIFO flush on success).
set -euo pipefail

root="${PASEKA_COLONY_ROOT:?missing PASEKA_COLONY_ROOT}"
eval_dir="${root}/.eval"
runs_file="${eval_dir}/scout-runs"
fault_mode_file="${eval_dir}/fault-mode"

runs=0
[[ -f "${runs_file}" ]] && runs="$(cat "${runs_file}")"
runs=$((runs + 1))
echo "${runs}" > "${runs_file}"

fault_mode=""
[[ -f "${fault_mode_file}" ]] && fault_mode="$(cat "${fault_mode_file}")"

echo "eval scout: direct intake run ${runs} fault=${fault_mode:-none}"

write_eval_comb() {
  local comb_dir="${root}/.paseka/runs/${PASEKA_TRACE_ID}/artifacts"
  mkdir -p "${comb_dir}"
  cat > "${comb_dir}/research.md" <<'EOF'
# Research brief

Eval comb handoff notes for artifact protocol case.
EOF
  echo "hidden skip" > "${comb_dir}/.hidden"
  echo "tmp skip" > "${comb_dir}/scratch.tmp"
  echo "eval scout: wrote comb under ${comb_dir}"
}

if [[ "${fault_mode}" == "write_comb" ]]; then
  write_eval_comb
fi

paseka event emit --stdin -C "${PASEKA_COLONY_ROOT}" <<EOF
{"traceId":"${PASEKA_TRACE_ID}","agentId":"${PASEKA_AGENT_ID}","type":"SIGNAL","payload":{"kind":"feature.classified","decision":"plan","rationale":"eval scout classified feature.requested"}}
EOF

if [[ "${fault_mode}" != "ready_before_plan" ]]; then
  exit 0
fi

task_id="001-add-sum"

echo "eval scout: live task.ready (slim) before deferred task.plan"
ready_out="$(paseka event emit --stdin -C "${PASEKA_COLONY_ROOT}" <<EOF
{"traceId":"${PASEKA_TRACE_ID}","agentId":"${PASEKA_AGENT_ID}","type":"SIGNAL","payload":{"kind":"task.ready","taskId":"${task_id}"}}
EOF
)"
echo "eval scout: live ready → ${ready_out}"

plan_json="$(PASEKA_TRACE_ID="${PASEKA_TRACE_ID}" PASEKA_AGENT_ID="${PASEKA_AGENT_ID}" python3 - <<'PY'
import json
import os

print(json.dumps({
    "traceId": os.environ["PASEKA_TRACE_ID"],
    "agentId": os.environ["PASEKA_AGENT_ID"],
    "type": "INSIGHT",
    "payload": {
        "kind": "task.plan",
        "tasks": [{
            "taskId": "001-add-sum",
            "title": "Add Sum(a, b)",
            "body": "Implement Sum in the seeded calc package so tests pass.",
            "bee": "builder",
            "intent": "feature",
            "review": "none",
            "dependsOn": [],
        }],
    },
}))
PY
)"
plan_out="$(echo "${plan_json}" | paseka event emit --defer --stdin -C "${PASEKA_COLONY_ROOT}")"
echo "eval scout: deferred plan → ${plan_out}"
if ! echo "${plan_out}" | grep -q '"deferred":true'; then
  echo "eval scout: expected deferred:true in task.plan emit response" >&2
  exit 1
fi
