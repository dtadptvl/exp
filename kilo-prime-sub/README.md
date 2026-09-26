# Kilo Prime/Sub minimal adaptive architecture

A global `prime` controller delegates bounded coding work to one disposable custom worker, `sub`, while Git remains code truth and `.prime/state.json` holds only the orchestration metadata Git cannot represent.

Installed runtime pieces are deliberately small:

- `agents/prime.md`: persistent system-level controller.
- `agents/sub.md`: stateless task-local worker pinned to `9router/sub`.
- `plugin/prime-sub-watchdog.js`: lifecycle watchdog using wall-clock + no-progress deadlines and native session abort. No step-count limit.
- `prime-sub/prime-state.ps1`: deterministic state/Git reconciliation and selective DAG invalidation helper installed globally.
- `.prime/state.json`: created/maintained by Prime per project from `protocol/STATE.md`.

Kilo continues to own sessions, context isolation, permissions, model execution, built-in agents, compaction, Task lifecycle, and cancellation. No database, daemon, event bus, scheduler framework, worktree manager, reviewer-role taxonomy, or duplicate session store is added.

## Install

Prerequisite: current Kilo CLI already installed and your existing provider setup exposes `9router/sub`.

1. Extract this folder.
2. Double-click `install.bat`.
3. If validation reports Human-owned config changes, apply only `AI-CONFIG-MERGE-GUIDE.md`, then rerun `install.bat`.
4. Start Kilo normally. With `default_agent: "prime"`, Prime is the default controller.

The installer never edits `kilo.json`/`kilo.jsonc`. It copies only its owned global agent/plugin/state-helper files, backs up different pre-existing files at those exact paths, carries the original rollback target across idempotent reruns, writes an ownership manifest, and validates effective Kilo settings.

## Anti-stall

The global plugin tracks only sessions whose agent is exactly `sub`. Observable progress is a completed tool call or session diff; streamed reasoning text does not reset the inactivity clock. Defaults:

- inactivity deadline: 15 minutes;
- absolute wall deadline: 60 minutes.

Override only when justified with environment variables `PRIME_SUB_STALL_MS` and `PRIME_SUB_WALL_MS`. On timeout it appends a compact record to `.prime/stall-events.jsonl` and calls Kilo's native session abort with tree scope. Prime reconciles and may perform at most one fresh-worker retry for the same stable failure signature before changing strategy/responsibility.

## Persistence and change handling

Prime re-anchors from `.prime/state.json` + current Git delta after every Human prompt, Sub boundary, restart/compaction/model switch, or material discovery. State stores objective/current phase/task DAG edges/decisions/assumptions/acceptance/evidence refs/Git reconciliation marker. It does not store raw chat, hidden reasoning, copied logs, or duplicate Git history.

Retroactive changes invalidate only direct and transitive semantic dependents (`depends_on`, `produces`, `consumes`, `verified_by`, `assumes`). Unaffected nodes and evidence remain valid.

## Verification

Run local package checks:

```text
python tests/run_all.py
```

`eval/` contains deterministic control simulations plus 28 Prime and 24 Sub behavioral-eval cases and a scoring rubric. `eval/run_live.py` is intentionally gated on a real Kilo installation/provider credentials; it does not fabricate live model results.

See `docs/NATIVE-KILO-FINDINGS.md`, `docs/ATTACHMENT-AUDIT.md`, and `eval/BASELINE-VS-OPTIMIZED.md` for evidence and remaining live-test gates.
