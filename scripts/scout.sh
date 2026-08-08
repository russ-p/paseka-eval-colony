#!/usr/bin/env bash
# Scripted eval scout: classify feature.requested via direct dispatch (SIGNAL direct path).
set -euo pipefail

root="${PASEKA_COLONY_ROOT:?missing PASEKA_COLONY_ROOT}"
eval_dir="${root}/.eval"
runs_file="${eval_dir}/scout-runs"

runs=0
[[ -f "${runs_file}" ]] && runs="$(cat "${runs_file}")"
runs=$((runs + 1))
echo "${runs}" > "${runs_file}"

echo "eval scout: direct intake run ${runs}"

paseka event emit --stdin -C "${PASEKA_COLONY_ROOT}" <<EOF
{"traceId":"${PASEKA_TRACE_ID}","agentId":"${PASEKA_AGENT_ID}","type":"SIGNAL","payload":{"kind":"feature.classified","decision":"plan","rationale":"eval scout classified feature.requested"}}
EOF
