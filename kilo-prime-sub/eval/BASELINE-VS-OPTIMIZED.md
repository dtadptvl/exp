# Baseline vs optimized record

Baseline is the fully audited attached package `prime-sub-minimal-adaptive-20260919-compact(3).zip`. Optimized is this folder.

## Deterministic architecture/control comparison

| Check | Baseline | Optimized |
|---|---|---|
| custom coding workers installed | one `sub` | one `sub` |
| Sub model | `9router/sub` | `9router/sub` |
| Prime delegates only Sub | yes | yes |
| `default_agent=prime` validated | no | yes |
| `subagent_depth=1` validated | no | yes |
| step-count anti-hang | `steps: 64` present | absent |
| external wall deadline | absent | watchdog 60 min default |
| evidence-based inactivity deadline | absent | watchdog 15 min default; reasoning text ignored |
| native tree cancellation | no supervisor | watchdog calls native session abort, tree scope |
| obsolete `experimental.task_model_selection` requirement | required | removed |
| provider `chunkTimeout` config requirement | required | removed; provider config untouched |
| semantic DAG edges | not explicit enough for selective arbitrary invalidation | `depends_on/produces/consumes/verified_by/assumes` |
| bounded retry policy | no fixed total attempt count, but no deterministic failure-signature bound | one fresh retry per stable signature then mandatory replan/Prime takeover |
| uninstall/rollback | backup only | ownership manifest + preserve modified files + restore backup |
| Prime behavioral cases | none | 28 |
| Sub behavioral cases | none | 24 |
| mandatory A-H deterministic simulations | none | 10 tests covering A-H |

Prompt size did not grow to encode the new control plane: baseline `prime.md` was 66 lines / 5921 bytes and `sub.md` 46 lines / 2753 bytes; optimized prompts are 77 lines / 5473 bytes and 45 lines / 2090 bytes. The only new runtime mechanism is the 117-line watchdog plugin. Eval/docs/tests are development artifacts, not runtime machinery.

## Executed results in this environment

- `python tests/run_all.py`: PASS, 19/19 deterministic tests.
- `node --check plugin/prime-sub-watchdog.js`: PASS.
- Mandatory A-H control simulations: PASS.
- `python eval/run_live.py`: BLOCKED because the current execution environment has no `kilo` executable/provider credentials.
- Attempt to fetch the official CLI binary for smoke testing from the container was blocked by container DNS/network isolation. Official Kilo docs/repository/release metadata were still verified externally before implementation.

Therefore no live Prime/Sub coding-success, token, tool, or elapsed-time numbers are claimed here. Running `eval/run_live.py` on a machine with current Kilo and `9router/sub` is the explicit remaining gate for model-dependent baseline-vs-optimized results.
