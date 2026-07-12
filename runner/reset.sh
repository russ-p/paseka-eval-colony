#!/usr/bin/env bash
# Reset eval colony to a case seed: purge ephemeral state, materialize seed/, record seedSha.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "${SCRIPT_DIR}/lib.sh"

case_id="${1:-}"
if [[ -z "${case_id}" ]]; then
  echo "usage: $0 <case-id>" >&2
  echo "example: $0 01-add-function" >&2
  exit 1
fi

reset_case "${case_id}"
