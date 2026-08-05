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

Phase 2 — Tier B cases `01`–`07` (scripted loop, energy block, first-pass, inject-mutation, kill, human reject, cue hotfix), script bees, reset + run-case runner.

## Quick start

```bash
# NATS (from paseka repo)
docker compose -f ../paseka/docker-compose.yml up -d nats

# from this repo root
paseka init          # idempotent
./runner/run-case.sh 01-add-function
./runner/run-all.sh
```

Tier A evals live in the Paseka platform repo (`internal/runtime` tests).

## Cases

| Case | Trace | Fault mode | Oracle |
| ---- | ----- | ---------- | ------ |
| `01-add-function` | `eval-01-add-function` | `scripted` | rework loop → tests pass |
| `02-energy-exhausted` | `eval-02-energy-exhausted` | `always_broken` | energy → `blocked` |
| `03-first-pass` | `eval-03-first-pass` | `first_pass` | no rework → tests pass |
| `04-inject-mutation` | `eval-04-inject-mutation` | `inject-mutation` | runner signal → guard→builder |
| `05-kill-cancel` | `eval-05-kill-cancel` | `always_broken` + kill | `cancelled`, honey remains |
| `06-human-reject` | `eval-06-human-reject` | `first_pass` + HITL | reject → rework → approve |
| `07-cue-hotfix` | `eval-07-cue-hotfix` | `first_pass` + cue ingress | `cue run hotfix` → bee/intent/budget → tests pass |

Reset model: `runner/reset.sh` purges ephemeral state (with `--reseed-energy` for task ingress; without for cue ingress), copies `cases/<id>/seed/` to repo root, commits `seedSha`, uses fixed `--trace` from `case.yaml`.
