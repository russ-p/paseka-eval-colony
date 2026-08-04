#!/usr/bin/env bash
# Scripted eval builder: apply broken/expect trees per fault mode.
# Modes: scripted (broken then expect), always_broken, first_pass (expect on run 1).
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

if [[ "${fault_mode}" == "always_broken" ]]; then
  apply_broken
elif [[ "${fault_mode}" == "first_pass" ]]; then
  apply_expect
elif [[ "${runs}" -eq 1 ]]; then
  apply_broken
else
  apply_expect
fi

# Runtime auto-publishes MUTATION/code.proposal.isolated from git diff when declared in bee YAML.
