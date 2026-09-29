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

Phase 2 — Tier B cases `01`–`19` (scripted loop, energy block, first-pass, inject-mutation, kill, human reject, cue hotfix, deferred emit, kill no-redispatch, signal direct, ready-before-plan, artifacts, standing trail ticks, final request-changes rework, pull-request delivery, worktree branch, clean runtime shutdown), script bees, reset + run-case runner.

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
| `08-deferred-emit` | `eval-08-deferred-emit` | `deferred_emit` (015) | `--defer` flush before `run.summary`; fail → `flush --discard` |
| `09-kill-no-redispatch` | `eval-09-kill-no-redispatch` | `always_broken` + kill + energy add | `cancelled`, honey tops up, no redispatch (US4) |
| `10-signal-direct` | `eval-10-signal-direct` | cue `feature` + scout direct | `feature.requested` → `feature.classified` (no ledger task) |
| `11-ready-before-plan` | `eval-11-ready-before-plan` | `ready_before_plan` + cue `feature` | live `task.ready` then deferred `task.plan` → builder completes |
| `12-artifact-scan-flush` | `eval-12-artifact-scan-flush` | `write_comb` | comb scan → `artifact.written` → tests pass |
| `13-artifact-deferred-skip` | `eval-13-artifact-deferred-skip` | `deferred_artifact` | deferred artifact + scan flush → one `artifact.written` |
| `14-artifact-handoff` | `eval-14-artifact-handoff` | cue `feature` + `write_comb` | scout comb → builder handoff → verification |
| `15-standing-trail-ticks` | `eval-15-standing-trail` | standing cue | two ticks reuse checkpoint, replace stipend, refuse overlap |
| `16-final-request-changes` | `eval-16-final-request-changes` | final review comments | comments file → rework task → final gate held → approve |
| `17-pr-delivery` | `eval-17-pr-delivery` | `pull_request` delivery | push head + forge upsert → gate held open → host merge → reconcile, no local merge |
| `18-worktree-branch` | `eval-18-worktree-branch` | `worktree.branch` rename | default `paseka/<trace>` → in-place rename → second task reuses the worktree, nothing pushed |
| `19-clean-shutdown` | `eval-19-clean-shutdown` | runtime shutdown windows | SIGTERM exits clean and clears the registry · SIGKILL leaves it stale · no drain, no recovery |

Reset model: `runner/reset.sh` purges ephemeral state (with `--reseed-energy` for task ingress; without for cue ingress), copies `cases/<id>/seed/` to repo root, commits `seedSha`, uses fixed `--trace` from `case.yaml`. Standing-trail cases run their cue twice, verify checkpoint reuse and stipend replacement, and reject an overlapping tick.

## Worktree branch (case 18)

The runtime creates `.paseka/worktrees/<traceId>/` on `paseka/<traceId>` and renames it in place when a bee emits `INSIGHT/worktree.branch` ([spec 020](https://github.com/russ-p/paseka/blob/main/docs/specs/020-worktree-branch.md)). The case pins: default name at create, rename (the default ref must disappear), `state.json` registry `branch`/`baseSha`/`path`, the `- **Branch:**` row of `paseka export`, reuse by a second task in the same trail, and a rejected `event emit` for a reserved ref.

Reuse needs a real second change: the runtime publishes only each run's **attributable** diff (per-file baseline hashes), so a follow-up task that rewrites identical content produces no proposal. `cases/<id>/expect2/` holds the tree for such a follow-up dispatch. A renamed worktree branch also escapes the `paseka/eval-*` sweep in `purge_colony`, so reset drops the branch named in `.eval/worktree-branch` explicitly — otherwise `worktree.Ensure` fails closed with `branch already exists`.

## Clean shutdown (case 19)

`paseka run` traps SIGINT/SIGTERM only, and the case pins what a "clean stop" currently is — and what it is not:

- **clean SIGTERM** — the process exits 0, logs `hive runtime stopped`, and `UnregisterSelf` drops the `runtime` row from `~/.config/paseka/<slug>/state.json`; `paseka status` then reports `Runtime: stopped (alive=false)`.
- **unclean SIGKILL** — the registry keeps `status: running` with a dead pid, so `paseka status` prints `Runtime: stale pid=N (alive=false)`, lists `runtime stale` under `Attention:`, and `paseka status --check` exits non-zero. A later clean stop heals the row.
- **no drain** — dispatch contexts are not children of the reactor context, so an in-flight bee is neither signalled nor killed: the process stays alive, its run dir keeps `status.json state=running` with no `result.json`/`summary.md`, and the task stays `running` forever. There is no startup recovery pass, so the restarted runtime neither recovers nor re-dispatches it.

The case expects `expect_task_status: running` and `must_pass_tests: false` because no code ever lands. `run-case.sh` calls `kill_inflight_bees` on exit so the orphan cannot leak into the next case.

## Pull-request delivery (case 17)

Paseka never creates a PR itself: with `defaults.delivery: pull_request` the runtime pushes the isolated head to `origin` and execs the apiary-local `forge.command` ([spec 024](https://github.com/russ-p/paseka/blob/main/docs/specs/024-pull-request-delivery.md)). The colony keeps that hermetic:

- `scripts/forge-fixture.sh` is a deterministic forge driver (v1 IPC: `capabilities`/`upsert`/`get`, no network). The runner points home `~/.config/paseka/paseka-eval-colony/config.yaml` at it and restores the file afterwards.
- `origin` is swapped for a local bare repo (`.eval/forge-origin.git`) for the case window, so the real head push never reaches GitHub.
- The final gate stays `waiting_review` after publish; the runner marks the PR merged (`.eval/forge/<trace>.merged`) and `paseka run` reconcile (30 s ticker) closes the trail with `task.completed` from `agent=runtime`.
- The deliverable is the pushed head, so the oracle clones the branch from the bare origin and runs `go test ./pkg/...` there; the colony checkout must stay on the broken seed. The leftover local head branch is removed by the next `purge`.
