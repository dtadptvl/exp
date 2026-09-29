# Kilo Prime/Sub minimal adaptive architecture

A global `prime` controller delegates bounded coding work to one disposable custom worker, `sub`, while Git remains code truth and `.prime/state.json` holds only the orchestration metadata Git cannot represent.

Installed runtime pieces are deliberately small:

- `agents/prime.md`: persistent system-level controller.
- `agents/sub.md`: stateless task-local worker pinned to `9router/sub`.
- `plugin/prime-sub-watchdog.js`: Sub lifecycle watchdog, Prime Task-contract guard, and Prime-only idle-boundary context compaction. No step-count limit.
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

## Prime contract and context bound

Prime delegation is enforced at the native Task boundary. A Prime Task must target custom `sub` and its prompt must be one raw JSON object with the exact fields in `protocol/TASK-CONTRACT.md`. Invalid prose/wrappers/extra fields are rejected; valid contracts are trimmed, deduplicated, canonicalized, and routed to `9router/sub`. The contract target is <= 6,000 characters with a 16,000-character hard ceiling, so Sub receives only the actionable slice rather than Prime history.

Prime context is bounded independently from Sub. The plugin observes only prompt-side usage (`input + cache.read + cache.write`; output/reasoning are excluded) and, after Prime becomes idle, calls native Kilo compaction when the last Prime request reaches 120,000 prompt-side tokens. Override with `PRIME_CONTEXT_SOFT_TOKENS`. Compaction uses `auto: false`, so it never creates a synthetic continuation turn. A Prime-specific compaction prompt anchors on the active slice of `.prime/state.json` and drops completed Sub transcripts, old tool outputs, duplicated code/history, and superseded plans.

This makes project age and chat length non-authoritative: after compaction Prime re-anchors from state + Git. Sub remains disposable and is not compacted by this plugin.

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
