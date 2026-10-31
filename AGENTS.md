## Eval colony for Paseka hive choreography

Side git repo with oracle-checkable cases, seeded baselines, and script bees (builder, guard, receiver). Exercises real `paseka run` + NATS paths without coupling to the platform release cycle.

Platform repo: [paseka](https://github.com/russ-p/paseka). Design spec: [docs/specs/003-hive-evals.md](https://github.com/russ-p/paseka/blob/main/docs/specs/003-hive-evals.md). Gotchas: [docs/999-backlog.md § Eval colony gotchas](https://github.com/russ-p/paseka/blob/main/docs/999-backlog.md).

## Layout

```text
.paseka/     colony config, eval-tuned bees (adapter: script)
cases/       case.yaml + seed/, broken/, expect/ per task
scripts/     builder.sh, guard.sh, receiver.sh, scout.sh, reviewer.sh
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
- **PR delivery rewrites machine-local config** — a case with `defaults.delivery: pull_request` makes `reset.sh` patch `.paseka/colony.yaml`, point home `~/.config/paseka/paseka-eval-colony/config.yaml` at `scripts/forge-fixture.sh`, and swap `origin` for `.eval/forge-origin.git`. `restore_colony_config` (reset start + `run-case.sh` exit trap) reverts all three; do not hand-edit those files while a PR case runs.
- **Renamed worktree branches outlive purge** — `worktree.branch` cases (018) move the worktree to a case name that `paseka/eval-*` does not match, so `purge_custom_worktree_branch` drops it from `.eval/worktree-branch`; a survivor makes the next `worktree.Ensure` fail closed with `branch already exists` and the reactor redelivers that insight forever. `delete_local_branch` detaches a leftover colony worktree still holding the ref, then deletes the branch and fails loudly if it cannot (it never touches checkouts outside `.paseka/worktrees/`).
- **Trace-scoped purge only clears one trail** — `purge --trace` (spec 042) leaves other cases' worktrees and branches alone, so `purge_colony` deletes this trace's default branch explicitly and sweeps `paseka/eval-*` branches no worktree holds. Oracles must scope worktree/branch counts to the case trace instead of asserting a colony-wide total.
- **Shutdown cases own the runtime** — case 019 signals `paseka run` itself (SIGTERM, SIGKILL, restart) and leaves a bee in flight on purpose; `run-case.sh` calls `kill_inflight_bees` on exit. Its task is expected to stay `running`, so `must_pass_tests` is false and no worktree oracle runs.
- **Closing policy is a per-case patch** — a case with `closing.enabled` makes `reset.sh` append a `closing:` policy and `merge:` gate copy to `.paseka/colony.yaml` (`set_colony_closing`), reads `merge/*_file` fixtures, and writes `.eval/closing-hold-secs`; `restore_colony_config` reverts the whole file, so a leftover block would make every following trail pay for an extra closing round. `scripts/reviewer.sh` must never edit files (exactly one `code.proposal.isolated` on the trail) and completes the runtime-seeded `closing-1` through `verification.success` → receiver, never by publishing `task.completed` itself.
- **Do not commit** `.eval/`, `reports/`, `.paseka/runs/`, `.paseka/worktrees/`, or machine-local apiary state.

## Adding a case

1. `cases/<id>/case.yaml` — trace, fault mode, oracle, expected event chain.
2. `cases/<id>/seed/` — tiny baseline tree (usually `go.mod` + one package).
3. `cases/<id>/broken/` — intentional bad fix for scripted fault injection.
4. `cases/<id>/expect/` — correct tree for builder rework pass.
5. `cases/<id>/expect2/` — optional: tree for a second dispatch in the same trail (worktree reuse). Required whenever a follow-up task must publish a proposal, because the runtime only attributes the files a run actually changed.
6. `cases/<id>/task.body` — task text for `paseka task create --file`, or cue text for `paseka cue run` when `ingress.mode: cue`. Signal cues (`emit: signal`) create no ledger task at ingress; score on scout dispatch (`expect_scout_run`) unless the case later emits `task.plan` (set `task.id` for hive scoring).
7. `cases/<id>/pr-body.md` — only for `defaults.delivery: pull_request`: the builder emits it as `INSIGHT pr.body` so publish resolves a body without a `--pr-body` overlay.
8. `cases/<id>/gate-title.txt` + `gate-body.md` — only for `closing.enabled` cases: the merge-gate copy `set_colony_closing` writes into `.paseka/colony.yaml`. The body is a `text/template` over the trail inventory (`{{range .Tasks}}{{.TaskID}} {{.Phase}} {{.Status}}{{end}}`), so the oracle can assert the rendered rows.

Run: `./runner/run-case.sh <id>`.

## Platform docs (when changing bees or contracts)

- [003-architecture.md](https://github.com/russ-p/paseka/blob/main/docs/003-architecture.md) — colony layout, worktrees, script adapter env
- [008-bee-routing.md](https://github.com/russ-p/paseka/blob/main/docs/008-bee-routing.md) — builder/guard/receiver loop
- [010-bee-config.md](https://github.com/russ-p/paseka/blob/main/docs/010-bee-config.md) — `adapter: script`, `command`, `completion_contract`
