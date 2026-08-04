#!/usr/bin/env bash
# Eval receiver: complete task after guard success.
# For review: required|final, human approve/reject owns completion — do not
# auto-emit task.completed (would race HITL and skip human.feedback).
set -euo pipefail

root="${PASEKA_COLONY_ROOT:?missing PASEKA_COLONY_ROOT}"
review_file="${root}/.eval/task-review"
review="none"
[[ -f "${review_file}" ]] && review="$(tr -d '[:space:]' < "${review_file}")"

case "${review}" in
  required|final)
    echo "eval receiver: skipping auto-complete (review=${review}; await HITL)"
    exit 0
    ;;
esac

task_id="${PASEKA_TASK_ID:-}"
if [[ -z "${task_id}" ]]; then
  task_id="eval-task"
fi

paseka event emit --stdin -C "${PASEKA_COLONY_ROOT}" <<EOF
{"traceId":"${PASEKA_TRACE_ID}","agentId":"${PASEKA_AGENT_ID}","type":"VERIFICATION","payload":{"kind":"task.completed","taskId":"${task_id}","status":"completed","summary":"eval receiver"}}
EOF
