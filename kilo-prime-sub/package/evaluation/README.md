# Evaluation harness

The goal is to compare the quality/cost frontier rather than judge only the optimized configuration.

## Configurations

1. `prime-only`: one strong primary agent with Task denied; it must implement directly.
2. `baseline`: the supplied-reference Prime/Sub policy represented as standalone eval assets under `evaluation/baseline/`.
3. `optimized`: the package's `agents/prime.md` + `agents/Sub.md`.

Each mode uses the same project-level agent name `prime`, so a user's per-agent Prime model selection is as comparable as Kilo allows. Sub remains `9router/sub`.

## Cases

`cases.py` defines 20 small but realistic repository tasks spanning bug fixes, multi-file behavior, regression preservation, ambiguity, existing failures, config/build issues, unnecessary-edit traps, misleading hypotheses, targeted verification, premature completion, dirty working trees, JSONC preservation, async behavior, CLI compatibility, path handling, data transformation, and upstream/downstream dependency changes.

The fixtures are intentionally dependency-light so the harness can validate them with Python/Node standard tooling. They are synthetic initial evals, not a substitute for later sampling from the user's real repositories.

## Prerequisites

- Kilo CLI on PATH.
- The same strong Prime model/provider configured for the `prime` agent across modes.
- `9router/sub` available.
- Effective config satisfies `CONFIG-MERGE-GUIDE.md`.
- Python 3.10+ and Node for the few JavaScript cases.

## Run

```bash
python evaluation/run_eval.py --mode all --trials 3
```

Optional:

```bash
python evaluation/run_eval.py --mode optimized --case C01 --trials 5 --timeout 1800
```

Each trial gets a fresh temporary Git repository. The harness installs project-local eval agents, commits the baseline fixture, applies any specified pre-existing human dirty change, runs Kilo with `--auto --format json`, runs validator commands, records changed files/numstat, writes JSONL results, and saves the raw Kilo JSON event stream plus stderr for trajectory annotation. Eval prompts forbid Git integration actions so all implementation deltas remain inspectable in the working tree.

The harness-level `--timeout` only prevents the benchmark process itself from hanging. It is not part of the runtime Prime/Sub architecture.

## Measurements

Automated fields include:

- validator pass/fail;
- Kilo exit code / harness timeout;
- elapsed wall time;
- changed paths and numstat;
- forbidden/unnecessary paths changed;
- raw JSON events containing usage/cost-like fields, when present.

Trajectory dimensions such as unsupported assumptions, premature completion, useful inspection, diff review, and failure diagnosis require either richer Kilo telemetry or manual annotation from `transcripts.local/*.jsonl`. Use `rubric.md`.

## Required interpretation

Do not declare success from one trial. For important cases, use multiple trials because model behavior is non-deterministic. Establish Prime-only and baseline variance before setting final thresholds. Thresholds in `rubric.md` are placeholders until measurements exist.

## Architecture-level E2E scenarios

The 20 coding cases measure coding quality/trajectory. Separately, `e2e-scenarios.md` defines the mandatory live orchestration scenarios for failure recovery, fresh-context replacement, context refresh, dirty/human changes, and retroactive dependency invalidation. They remain `NOT_RUN` until executed with the real Kilo/provider setup.
