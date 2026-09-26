# Attachment audit

Source audited: `prime-sub-minimal-adaptive-20260919-compact(3).zip` (all seven files).

| Source | Purpose | Keep | Replace/drop |
|---|---|---|---|
| `agents/prime.md` | controller policy | bounded contracts, adaptive Prime/Sub split, Git reconciliation, evidence-based acceptance | removed `steps0-based recovery assumptions; tightened mandatory Task Contract fields, drift control, selective invalidation, low-token refresh, finite retry-by-signature |
| `agents/sub.md` | worker prompt/model/permissions | `9router/sub`, no nested Task, Git mutation boundary, inspect/edit/verify/diff discipline | dropped `steps: 64`; simplified result to requested structured schema; external watchdog now owns stall termination |
| `install.ps1` | global install + validation | native `kilo debug paths/config/agent`, global agents, backup | removed obsolete `experimental.task_model_selection` and provider `chunkTimeout` requirements; now installs thin global plugin, validates `default_agent` + `subagent_depth`, owns manifest/rollback |
| `setup.cmd` | one-click entry | one-click Windows flow | replaced by required `install.bat` plus matching uninstall |
| `CONFIG-GUIDE.md` | Human config edits | preserve unrelated config/secrets/comments | replaced with AI merge guide requiring only `default_agent=prime`, `subagent_depth=1`, and existing `9router/sub`; no installer config mutation |
| `README.md` | architecture/usage | native-Kilo-first principle, minimal state | updated for lifecycle watchdog, new state/dependency contract, current Kilo behavior |
| `tests/test_artifact.py` | structural conformance | static package checks | expanded to mandatory A-H control simulations, eval datasets/rubric, no-step checks, installer ownership/rollback checks |

Native replacement decisions: use Kilo Task isolated child sessions/result ingestion; built-in permission system; per-task model selection; native session abort; global plugin auto-discovery; config deep merge/agent Markdown precedence; native compaction/session machinery. No custom task runner/session DB/scheduler/worktree layer.
