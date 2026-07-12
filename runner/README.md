# Runner

Tier B harness for the eval colony.

## Scripts

| Script | Purpose |
| ------ | ------- |
| `reset.sh <case-id>` | Purge ephemeral colony state, materialize `cases/<id>/seed/` to repo root, commit seed SHA |
| `run-case.sh <case-id>` | Full case: reset → `paseka task create --autorun` → wait → oracle → JSON report |

Requires `paseka` on `PATH`, NATS (`paseka doctor`), and Go for oracle commands.

```bash
# from eval colony root
./runner/reset.sh 01-add-function
./runner/run-case.sh 01-add-function
```

`run-case.sh` writes reports to `reports/` and prints `paseka replay` output. Pass `--keep-runtime` as a second arg to leave `paseka run` running.

## State

`.eval/` (gitignored) tracks active case, trace, builder run counter, and optional `paseka run` pid.
