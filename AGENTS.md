## Eval colony for Paseka hive choreography

Side git repo with oracle-checkable cases, seeded baselines, and script bees (builder, guard, receiver). Exercises real `paseka run` + NATS paths without coupling to the platform release cycle.

Platform repo: [paseka](https://github.com/russ-p/paseka). Design spec: [docs/specs/003-hive-evals.md](https://github.com/russ-p/paseka/blob/main/docs/specs/003-hive-evals.md). Gotchas: [docs/999-backlog.md § Eval colony gotchas](https://github.com/russ-p/paseka/blob/main/docs/999-backlog.md).

## Layout

```text
.paseka/     colony config, eval-tuned bees (adapter: script)
cases/       case.yaml + seed/, broken/, expect/ per task
scripts/     builder.sh, guard.sh, receiver.sh, scout.sh
runner/      reset.sh, run-case.sh (Tier B harness)
```

Tier A (in-process) evals live in the platform repo (`internal/runtime` tests). Tier B/C run here.

## Run

```bash
# NATS (sibling paseka checkout)
docker compose -f ../paseka/docker-compose.yml up -d nats

# from this repo root; paseka binary on PATH
paseka init                              # idempotent
./runner/run-case.sh 01-add-function
```

## Invariants (read before editing)

- **Commit script and seed changes** — worktrees are created from `HEAD`; uncommitted `scripts/` or root `go.mod`/`pkg/` are invisible to bees.
- **Runner must use `-C`** — all `paseka` calls from `runner/` pass `-C "${EVAL_ROOT}"` so purge/task/replay target this colony, not a parent repo.
- **Bus reset via purge** — `runner/reset.sh` stops `paseka run`, applies case `energy.budget` to colony defaults when set, then `paseka purge --runs --worktrees --state --bus --trace <trace> --reseed-energy` clears JetStream state and reseeds honey (no NATS container restart). Cue ingress cases (`ingress.mode: cue`) skip `--reseed-energy` so `paseka cue run` can seed honey from the cue's `energy_budget`.
- **Script bees emit with colony root** — `paseka event emit --stdin -C "${PASEKA_COLONY_ROOT}"` (worktree cwd breaks home-config resolution).
- **Materialized seed is committed** — `runner/reset.sh` copies `cases/<id>/seed/` to repo root and commits `seedSha` before worktree creation.
- **Score the oracle, not task status alone** — with `review: none`, runtime may mark the task `completed` before guard→builder rework finishes; `run-case.sh` polls worktree tests.
- **Do not commit** `.eval/`, `reports/`, `.paseka/runs/`, `.paseka/worktrees/`, or machine-local apiary state.

## Adding a case

1. `cases/<id>/case.yaml` — trace, fault mode, oracle, expected event chain.
2. `cases/<id>/seed/` — tiny baseline tree (usually `go.mod` + one package).
3. `cases/<id>/broken/` — intentional bad fix for scripted fault injection.
4. `cases/<id>/expect/` — correct tree for builder rework pass.
5. `cases/<id>/task.body` — task text for `paseka task create --file`, or cue text for `paseka cue run` when `ingress.mode: cue`. Signal cues (`emit: signal`) create no ledger task at ingress; score on scout dispatch (`expect_scout_run`) unless the case later emits `task.plan` (set `task.id` for hive scoring).

Run: `./runner/run-case.sh <id>`.

## Platform docs (when changing bees or contracts)

- [003-architecture.md](https://github.com/russ-p/paseka/blob/main/docs/003-architecture.md) — colony layout, worktrees, script adapter env
- [008-bee-routing.md](https://github.com/russ-p/paseka/blob/main/docs/008-bee-routing.md) — builder/guard/receiver loop
- [010-bee-config.md](https://github.com/russ-p/paseka/blob/main/docs/010-bee-config.md) — `adapter: script`, `command`, `completion_contract`
