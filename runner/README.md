# Runner

Tier B harness for the eval colony.

## Scripts

| Script | Purpose |
| ------ | ------- |
| `reset.sh <case-id>` | Purge ephemeral colony state (`--bus`, optionally `--reseed-energy`), materialize `cases/<id>/seed/` to repo root, commit seed SHA |
| `run-case.sh <case-id>` | Full case: reset → `paseka task create --autorun` or `paseka cue run` → wait → oracle → JSON report |
| `run-all.sh` | Run every case under `cases/` in order; exit 1 if any fail |

Requires `paseka` on `PATH`, NATS (`paseka doctor`), and Go for oracle commands.

```bash
# from eval colony root
./runner/reset.sh 01-add-function
./runner/run-case.sh 01-add-function
./runner/run-all.sh
```

`run-case.sh` writes reports to `reports/` and prints `paseka replay` output. Pass `--keep-runtime` as a second arg to leave `paseka run` running.

Cue ingress (`ingress.mode: cue` in `case.yaml`): reset skips `--reseed-energy` so the cue's `energy_budget` seeds honey instead of colony defaults. Signal cues (`emit: signal`) do not print a `Task:` line — cases score scout direct dispatch, or set `task.id` when scout later emits `task.plan` so the harness can wait on the ledger task.

## State

`.eval/` (gitignored) tracks active case, trace, builder run counter, and optional `paseka run` pid.
