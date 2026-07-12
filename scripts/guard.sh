#!/usr/bin/env bash
# Script guard: run oracle tests in workspace, emit verification outcome.
set -euo pipefail

cd "${PASEKA_WORKSPACE:?missing PASEKA_WORKSPACE}"

summary="tests passed"
kind="verification.success"
if ! go test ./pkg/...; then
  summary="tests failed"
  kind="verification.failed"
fi

paseka event emit --stdin -C "${PASEKA_COLONY_ROOT}" <<EOF
{"traceId":"${PASEKA_TRACE_ID}","agentId":"${PASEKA_AGENT_ID}","type":"VERIFICATION","payload":{"kind":"${kind}","summary":"${summary}"}}
EOF
