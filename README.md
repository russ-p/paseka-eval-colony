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

Phase 2 — Tier B cases (`01-add-function`, `02-energy-exhausted`, `03-first-pass`), script bees, reset + run-case runner.

## Quick start

```bash
# NATS (from paseka repo)
docker compose -f ../paseka/docker-compose.yml up -d nats

# from this repo root
paseka init          # idempotent
./runner/run-case.sh 01-add-function
./runner/run-case.sh 03-first-pass
```

Tier A evals live in the Paseka platform repo (`internal/runtime` tests).

## Cases

| Case | Trace | Fault mode | Oracle |
| ---- | ----- | ---------- | ------ |
| `01-add-function` | `eval-01-add-function` | `scripted` | `go test ./...` |
| `02-energy-exhausted` | `eval-02-energy-exhausted` | `always_broken` | energy → blocked |
| `03-first-pass` | `eval-03-first-pass` | `first_pass` | `go test ./pkg/...` |

Reset model: `runner/reset.sh` purges ephemeral state with `--reseed-energy`, copies `cases/<id>/seed/` to repo root, commits `seedSha`, uses fixed `--trace` from `case.yaml`.
