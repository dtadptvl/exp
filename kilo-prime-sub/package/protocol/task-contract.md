# Minimum-sufficient Task contract

Prime sends one bounded contract to a fresh Sub. The contract should usually fit in a few hundred tokens plus exact path/symbol/test references.

```text
CONTRACT C7/r2  OBJECTIVE_REV 4
OBJECTIVE: Fix duplicate retry scheduling when a job is already queued.
SCOPE: own src/queue.py#schedule_retry and tests/test_queue.py; do not refactor queue storage.
ACCEPT:
- existing queued job is not scheduled twice
- new job still schedules once
- unrelated dirty docs/notes.md is preserved
FACTS:
- failing test: tests/test_queue.py::test_existing_job_not_duplicated
- observed HEAD: abc123
- docs/notes.md was dirty before this contract
CONSTRAINTS: preserve public Queue API
BASE: branch feature/x; HEAD abc123; pre-existing dirty docs/notes.md
ENTRY: src/queue.py#schedule_retry; tests/test_queue.py
VERIFY: run the targeted queue test, then the queue test file if the fix changes shared queue behavior
RETURN: Sub compact status/evidence format
```

## Contract rules

- Include verified facts, not Prime speculation. Mark uncertainty explicitly.
- Prefer paths, symbols, test names, task IDs, SHAs, and evidence IDs to copied context.
- Do not include the full roadmap, whole conversation, full repository summaries, or unrelated decisions.
- `SCOPE` names both ownership and important exclusions.
- `ACCEPT` must be observable.
- `VERIFY` is proportional to changed surface and risk.
- Recovery contracts include only useful prior evidence: stable failure signature, disproven hypotheses, preserved partial work, and the next diagnostic boundary.
- A replacement Sub gets a new Task session with a new contract invocation and no `task_id` resume.
