#!/usr/bin/env bash
# Scripted eval builder: apply broken tree on first run, expect/ fix on rework.
set -euo pipefail

root="${PASEKA_COLONY_ROOT:?missing PASEKA_COLONY_ROOT}"
workspace="${PASEKA_WORKSPACE:?missing PASEKA_WORKSPACE}"
eval_dir="${root}/.eval"
case_dir_file="${eval_dir}/case-dir"
runs_file="${eval_dir}/builder-runs"

if [[ ! -f "${case_dir_file}" ]]; then
  echo "eval builder: missing ${case_dir_file} (run runner/reset.sh first)" >&2
  exit 1
fi

case_dir="$(cat "${case_dir_file}")"
runs=0
[[ -f "${runs_file}" ]] && runs="$(cat "${runs_file}")"
runs=$((runs + 1))
echo "${runs}" > "${runs_file}"

cd "${workspace}"

if [[ "${runs}" -eq 1 ]]; then
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
else
  if [[ -d "${case_dir}/expect" ]]; then
    rsync -a "${case_dir}/expect/" "${workspace}/"
    echo "eval builder: applied expect/ tree (run ${runs})"
  else
    echo "eval builder: no expect/ directory for rework run ${runs}" >&2
    exit 1
  fi
fi

# Runtime auto-publishes MUTATION/code.proposal from git diff when declared in bee YAML.
