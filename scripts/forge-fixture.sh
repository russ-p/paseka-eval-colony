#!/usr/bin/env bash
# Deterministic forge driver for eval case 17 (17-pr-delivery).
# Speaks the v1 forge IPC contract (capabilities/upsert/get: JSON stdin, one JSON
# object on stdout) with no network and no gh/tea login. The runner points home
# `forge.command` here, so `paseka proposal approve` really pushes the isolated head
# and upserts a "pull request"; the runner then creates <trace>.merged to play the
# host-side merge and lets `paseka run` reconcile the final gate.
#
# State dir: $PASEKA_FORGE_COLONY_ROOT/.eval/forge (runner-managed, gitignored).
#   <trace>.json     current PR identity (also the "created" record)
#   <trace>.merged   marker file: while absent, `get` reports the PR as open
#   ops.log          one JSON line per request, for the case oracle
set -euo pipefail

exec python3 -c '
import json
import os
import pathlib
import sys

op = sys.argv[1]
req = json.load(sys.stdin)

root = os.environ.get("PASEKA_FORGE_COLONY_ROOT", "").strip()
if not root:
    sys.stderr.write("PASEKA_FORGE_COLONY_ROOT is required\n")
    raise SystemExit(1)

trace = (req.get("traceId") or os.environ.get("PASEKA_FORGE_TRACE_ID", "")).strip()

state_dir = pathlib.Path(root) / ".eval" / "forge"
state_dir.mkdir(parents=True, exist_ok=True)
log_path = state_dir / "ops.log"


def emit(obj):
    json.dump(obj, sys.stdout)
    sys.stdout.write("\n")


if op == "capabilities":
    emit({"protocolVersion": 1, "ops": ["upsert", "get"]})
    raise SystemExit(0)

if not trace:
    sys.stderr.write("traceId is required\n")
    raise SystemExit(1)

pr_path = state_dir / (trace + ".json")
merged_path = state_dir / (trace + ".merged")

head = (req.get("head") or "").strip()
if not head:
    sys.stderr.write("head is required\n")
    raise SystemExit(1)
base = (req.get("base") or "main").strip()

with log_path.open("a") as fh:
    fh.write(json.dumps({
        "op": op,
        "traceId": trace,
        "head": head,
        "base": base,
        "title": req.get("title") or "",
        "body": req.get("body") or "",
        "draft": bool(req.get("draft")),
    }) + "\n")

if op == "upsert":
    entry = {
        "protocolVersion": 1,
        "found": True,
        "number": 42,
        "url": "https://eval-forge.invalid/" + os.path.basename(root) + "/pulls/42",
        "head": head,
        "base": base,
        "state": "open",
        "draft": bool(req.get("draft")),
    }
    pr_path.write_text(json.dumps(entry) + "\n")
    emit(entry)
    raise SystemExit(0)

if op != "get":
    sys.stderr.write("unsupported op: " + op + "\n")
    raise SystemExit(1)

if not pr_path.exists():
    emit({"protocolVersion": 1, "found": False})
    raise SystemExit(0)

entry = json.loads(pr_path.read_text())
entry["state"] = "merged" if merged_path.exists() else "open"
pr_path.write_text(json.dumps(entry) + "\n")
emit(entry)
' "${1:-}"
