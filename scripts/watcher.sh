#!/usr/bin/env bash
set -euo pipefail

root="${PASEKA_COLONY_ROOT:?missing PASEKA_COLONY_ROOT}"
eval_dir="${root}/.eval"
runs_file="${eval_dir}/watcher-runs"
hold_file="${eval_dir}/watcher-hold-secs"
checkpoint_dir="${root}/.paseka/runs/${PASEKA_TRACE_ID}/artifacts"
checkpoint_file="${checkpoint_dir}/checkpoint.json"

runs=0
[[ -f "${runs_file}" ]] && runs="$(cat "${runs_file}")"
runs=$((runs + 1))
echo "${runs}" > "${runs_file}"

hold=0
if [[ -f "${hold_file}" ]]; then
  hold="$(cat "${hold_file}")"
  if [[ "${hold}" =~ ^[0-9]+$ ]] && (( hold > 0 && runs == 1 )); then
    sleep "${hold}"
  fi
fi

mkdir -p "${checkpoint_dir}"
CHECKPOINT_FILE="${checkpoint_file}" TICK="${runs}" python3 - <<'PY'
import json
import os
from pathlib import Path

path = Path(os.environ["CHECKPOINT_FILE"])
tick = int(os.environ["TICK"])
previous = None
if path.exists():
    try:
        previous = json.loads(path.read_text()).get("ticks")
    except (OSError, ValueError, AttributeError):
        previous = None
payload = {"ticks": tick, "previous": previous}
tmp = path.with_suffix(".tmp")
tmp.write_text(json.dumps(payload, sort_keys=True) + "\n")
tmp.replace(path)
PY
