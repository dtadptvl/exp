# Rejected or removed machinery

| Mechanism | Problem it could solve | Native/simpler alternative | Decision |
|---|---|---|---|
| Per-Sub Git worktrees | Concurrent writer isolation | Single sequential Sub in one required working tree | Rejected by invariant and unnecessary |
| Custom scheduler / queue daemon | Serialize tasks | Foreground Task + Prime state `next` | Rejected |
| Custom session store | Persist Sub conversations | Native Kilo child sessions; architecture uses fresh Sub anyway | Rejected |
| Custom agent registry | Discover Prime/Sub | Native global agent Markdown | Rejected |
| Polling/heartbeat service | Detect every stall | Native cancellation, doom-loop, provider/tool timeout, emergency step ceiling | Rejected pending demonstrated gap |
| Universal short stream-idle watchdog | Detect dead SSE | Explicit provider `chunkTimeout` | Rejected because Kilo itself reverted an ambiguous universal heuristic |
| Database/journal | Persist roadmap/evidence | Git + one small `.prime/state.json` | Rejected |
| Full transcript summaries in state | Resume context | Compact refs + current Git evidence | Rejected |
| Full Prime review after every Sub | Quality assurance | Deterministic evidence + risk-triggered targeted review | Rejected |
| Automatic full test/lint/build on every task | Verification | Proportional targeted verification | Rejected |
| Fixed total recovery attempts | Bound retries | Failure-class evidence + changed strategy + native guards | Rejected |
| Resume failed Sub `task_id` by default | Preserve local context | Fresh replacement with compact recovery evidence | Rejected for disposable-worker invariant |
| Background Sub fan-out | Lower wall time | Sequential foreground Sub | Rejected initially because one write-capable Sub type + shared tree makes coordination cost/risk larger than demonstrated benefit |
| Rich task-file database | Dependency tracking | Small task DAG/touches/assumption refs in state | Rejected |

## Provisional mechanism retained only as a circuit breaker

`steps: 96` remains in `sub.md` solely to prevent an otherwise unbounded semantic loop when successful tool calls evade `doom_loop` and no per-Task absolute deadline is exposed. It is not accepted as the primary stall policy and is not empirically tuned. Live eval must decide whether to remove it, change it, or justify a true task-level deadline mechanism.
