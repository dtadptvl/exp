# Rejected machinery

- Database/SQLite: Git + one JSON state file is sufficient; no observed need for queries/transactions.
- Daemon/service: global Kilo plugin timers already live with the Kilo runtime.
- Custom scheduler/queue/event bus: Kilo Task owns child lifecycle/background delivery; Prime serializes overlapping writes by policy.
- Worktree manager: explicitly not required; shared tree plus scope scheduler rule is enough.
- Role taxonomy (Architect/Reviewer/etc.): decomposition is by concrete deliverable; fresh verification is conditional on risk/evidence.
- Custom session/task store: Kilo already owns sessions; `.prime/state.json` stores only orchestration metadata.
- `steps/maxSteps` fuse: violates the requested anti-stall invariant and can terminate productive long trajectories while failing to measure actual progress.
- Provider-specific `chunkTimeout` requirement: unnecessary once the external watchdog can abort stalled Sub sessions; provider settings are left untouched.
- Obsolete `experimental.task_model_selection`: current Kilo has per-task selection without that flag.
- Generic plugin framework: one plugin file implements the only native gap found.
