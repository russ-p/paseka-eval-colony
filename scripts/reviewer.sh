#!/usr/bin/env bash
# Scripted eval reviewer: one closing round per dispatch (spec 045).
# Writes the authoritative pr.body + trace.summary, then completes the round via
# the guard/receiver success path. It must not edit files: a closing task that
# opens a proposal hijacks review rework attribution.
set -euo pipefail

root="${PASEKA_COLONY_ROOT:?missing PASEKA_COLONY_ROOT}"
eval_dir="${root}/.eval"
task_id="${PASEKA_TASK_ID:?missing PASEKA_TASK_ID}"

runs_file="${eval_dir}/reviewer-runs"
runs=0
[[ -f "${runs_file}" ]] && runs="$(cat "${runs_file}")"
runs=$((runs + 1))
echo "${runs}" > "${runs_file}"

echo "eval reviewer: closing run ${runs} task=${task_id} prompt=${PASEKA_PROMPT_FILE:-none}"

# The runner observes the merge gate staying closed while this round is in
# flight and commits the trail worktree before the gate opens. The hold keeps
# that window deterministic without changing what the round reports.
hold=5
hold_file="${eval_dir}/closing-hold-secs"
[[ -f "${hold_file}" ]] && hold="$(cat "${hold_file}")"
if [[ "${hold}" =~ ^[0-9]+$ ]] && (( hold > 0 )); then
  echo "eval reviewer: holding ${hold}s so the gate-closed window is observable"
  sleep "${hold}"
fi

python3 - <<'PY' | paseka event emit --stdin -C "${root}"
import json
import os

print(json.dumps({
    "traceId": os.environ["PASEKA_TRACE_ID"],
    "agentId": os.environ["PASEKA_AGENT_ID"],
    "type": "INSIGHT",
    "payload": {
        "kind": "pr.body",
        "body": (
            "Eval closing round body\n\n"
            "- reviewed the whole trail before the merge gate\n"
            "- this description comes from the closing task, not the last work task"
        ),
    },
}))
PY

python3 - <<'PY' | paseka event emit --stdin -C "${root}"
import json
import os

print(json.dumps({
    "traceId": os.environ["PASEKA_TRACE_ID"],
    "agentId": os.environ["PASEKA_AGENT_ID"],
    "type": "INSIGHT",
    "payload": {
        "kind": "trace.summary",
        "summary": "eval closing round reviewed the whole trail",
    },
}))
PY

python3 - <<'PY' | paseka event emit --stdin -C "${root}"
import json
import os

print(json.dumps({
    "traceId": os.environ["PASEKA_TRACE_ID"],
    "agentId": os.environ["PASEKA_AGENT_ID"],
    "type": "VERIFICATION",
    "payload": {
        "kind": "verification.success",
        "summary": "closing round reviewed the trail",
        "taskId": os.environ["PASEKA_TASK_ID"],
    },
}))
PY
