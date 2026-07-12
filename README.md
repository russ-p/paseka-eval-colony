# paseka-eval-colony

Side evaluation colony for [Paseka](https://github.com/russ-p/paseka) hive choreography. Keeps oracle-checkable tasks, seeded baselines, and eval-tuned bees out of the platform repo.

Design: [paseka/docs/specs/003-hive-evals.md](https://github.com/russ-p/paseka/blob/main/docs/specs/003-hive-evals.md).

## Layout

```text
.paseka/          colony config, eval-tuned script bees (builder, guard, receiver)
cases/            oracle tasks with seed/, broken/, expect/
scripts/          script-adapter hooks for Tier B bees
runner/           reset + run-case harness (Tier B)
```

## Status

Phase 2 — one case (`01-add-function`), scripted builder/guard loop, reset + run-case runner.

## Quick start

```bash
# NATS (from paseka repo)
docker compose -f ../paseka/docker-compose.yml up -d nats

# from this repo root
paseka init          # idempotent
./runner/run-case.sh 01-add-function
```

Tier A evals live in the Paseka platform repo (`internal/runtime` tests).

## Cases

| Case | Trace | Fault mode | Oracle |
| ---- | ----- | ---------- | ------ |
| `01-add-function` | `eval-01-add-function` | `scripted` | `go test ./...` |

Reset model: `runner/reset.sh` purges ephemeral state, copies `cases/<id>/seed/` to repo root, commits `seedSha`, uses fixed `--trace` from `case.yaml`.
