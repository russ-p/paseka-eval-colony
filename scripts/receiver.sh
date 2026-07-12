#!/usr/bin/env bash
# Eval receiver: complete task after guard success.
set -euo pipefail

task_id="${PASEKA_TASK_ID:-}"
if [[ -z "${task_id}" ]]; then
  task_id="eval-task"
fi

paseka event emit --stdin -C "${PASEKA_COLONY_ROOT}" <<EOF
{"traceId":"${PASEKA_TRACE_ID}","agentId":"${PASEKA_AGENT_ID}","type":"VERIFICATION","payload":{"kind":"task.completed","taskId":"${task_id}","status":"completed","summary":"eval receiver"}}
EOF
