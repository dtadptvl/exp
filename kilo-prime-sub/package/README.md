# Kilo Prime/Sub researched architecture

A native-first global Kilo Code CLI setup for using a strong Prime controller with one cheaper disposable `Sub` model (`9router/sub`) while minimizing Prime rereading and orchestration overhead.

This package was derived from current Kilo source/docs plus the supplied reference ZIP. The ZIP was treated as a baseline/reference, not as a specification or runtime dependency.

## What is installed

Only two global agent definitions are installed:

- `prime`: persistent primary controller;
- `Sub`: the only custom subagent, pinned to `9router/sub`.

At runtime Prime lazily creates one project-local orchestration file:

- `.prime/state.json`.

There is no custom scheduler, daemon, task runner, session database, agent registry, worktree manager, message bus, or background poller.

## Fixed invariants

- `default_agent = "prime"`.
- `subagent_depth = 1`.
- Prime delegates only to custom `Sub`.
- Each Sub contract is a fresh Task session; this architecture does not resume `task_id`.
- Exactly one Sub runs at a time in the shared working tree.
- Sub model is always explicitly requested as `9router/sub` by Prime.
- Sub cannot spawn agents and cannot perform Git mutation/integration operations.
- Generic step count is not the primary stall/completion/retry mechanism. A high native step ceiling remains only as an emergency circuit breaker pending live evaluation.

## Agent ID casing

The canonical runtime agent ID is lowercase `sub`, backed by `~/.config/kilo/agents/sub.md`. Kilo agent lookup is exact-key/case-sensitive. Older package builds incorrectly installed `Sub.md`; rerunning this package's `setup.cmd` safely migrates that case-variant after backing it up.

## Install on Windows

Prerequisites:

1. Native Kilo Code CLI is installed and configured.
2. Provider/model `9router/sub` is available to Kilo.
3. Apply the minimal human-owned config merge in `CONFIG-MERGE-GUIDE.md`.

Then double-click:

```text
setup.cmd
```

The installer:

- resolves Kilo's global config directory through `kilo debug paths`;
- backs up existing global `prime.md` / `sub.md` when they differ;
- installs the two agent files;
- writes a small install receipt for safe rollback;
- validates effective Prime/Sub topology, model, depth, permissions, timeouts, and version-specific model-selection requirements;
- never edits `kilo.json` or `kilo.jsonc`.

To remove the package and restore the immediately previous global Prime/Sub files:

```text
uninstall.cmd
```

Uninstall refuses to overwrite locally modified installed agents unless run manually with `uninstall.ps1 -Force`.

## Run

Inside a target Git repository:

```powershell
kilo run --auto --agent prime "<your objective>"
```

Prime creates `.prime/state.json` only when needed and keeps it local. In a Git repo it may add `.prime/` to `.git/info/exclude` rather than editing the project's `.gitignore`.

## Runtime flow

1. Prime reconciles current objective + Git/working-tree delta with minimal state.
2. Prime chooses the smallest bounded deliverable that can be delegated.
3. Prime persists/sends a minimum-sufficient contract and launches a fresh foreground `Sub` Task with explicit model `9router/sub`.
4. Sub inspects, establishes evidence, implements, verifies proportionally, reviews changed scope, and returns structured evidence.
5. Prime accepts from current evidence when sufficient. It performs targeted diff review only when deterministic evidence cannot establish correctness/design risk.
6. On failure, Prime records compact recovery evidence, changes strategy/decomposition, and launches a fresh Sub. Human/external changes override stale assumptions.
7. Retroactive changes invalidate only evidence/tasks that actually depend on the changed result, then trigger minimum repair + selective reverification.

See `protocol/task-contract.md` and `protocol/state-schema.md`.

## Stall/hang policy

Primary controls are native and evidence-based:

- Kilo `doom_loop` detection is denied for Sub continuation;
- provider request/first-byte timeout remains finite;
- `9router.options.chunkTimeout` is finite to bound silent stream stalls;
- shell/process commands use native Kilo timeout;
- repeated equivalent failures are not counted as progress;
- Sub returns `FAILED_TECHNICAL` when stronger reasoning or a different strategy is needed.

`steps: 96` is retained only as a final emergency circuit breaker because current research did not find a supported per-Task absolute wall-clock deadline. It must not be used as a difficulty score, retry counter, progress signal, or completion gate. Live evaluation should determine whether it can be removed or replaced by a better supported deadline.

## Evaluation

`evaluation/run_eval.py` prepares and runs three configurations on the same 20-case set:

- Prime-only reference;
- supplied-reference Prime/Sub baseline, copied into this standalone package as an eval asset;
- optimized Prime/Sub.

It supports repeated trials, isolated Git fixture repos, JSON run logs, validator commands, changed-file accounting, elapsed time, and raw usage-event capture when Kilo emits usage fields.

Current benchmark status is in `evaluation/RESULTS.md`. The environment used to build this package did not have a `kilo` executable or `9router/sub` credentials, so live model results are intentionally `NOT_RUN`. No quality/token numbers are fabricated.

Run package validation now with:

```bash
python tests/test_artifact.py
```

Run live eval later from a machine with Kilo/provider access:

```bash
python evaluation/run_eval.py --mode all --trials 3
```

Read `evaluation/README.md` first.

## Research and design evidence

- `RESEARCH.md`: native Kilo facts, attached ZIP analysis, external research, derived requirements, unknowns.
- `protocol/`: minimum contract and persistent-state design.
- `REJECTED-MACHINERY.md`: mechanisms considered but not admitted.
- `evaluation/rubric.md`: outcome + trajectory + cost/latency scoring.
- `evaluation/e2e-scenarios.md`: the 11 mandatory live architecture scenarios and required evidence.
- `CONFIG-MERGE-GUIDE.md`: minimal safe config merge for an AI chatbot or human.

## Success claim

This repository does not claim the architecture has already reached the requested near-Prime quality/token frontier. Static implementation validation passes locally, but the mandatory live baselines require Kilo plus the user's actual Prime model/provider and `9router/sub`. `evaluation/RESULTS.md` records this evidence gap explicitly and the harness is ready to produce the required measurements.
