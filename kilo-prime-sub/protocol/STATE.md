# Minimal persistent state

`.prime/state.json` is the only live orchestration state outside chat. Git remains source of truth for code/history/diffs. Do not store raw chats, chain-of-thought, copied logs, duplicate Git history, or full repo summaries.

Initial state:

```json
{
  "schema": 1,
  "objective": {"rev": 0, "text": ""},
  "phase": "capture-objective",
  "active_task": null,
  "tasks": {},
  "decisions": {},
  "assumptions": {},
  "acceptance": [],
  "evidence": {},
  "invalidated": [],
  "git": null,
  "next": "capture objective"
}
```

A task stores only what Git cannot answer:

```json
{
  "status": "queued|running|verifying|done|failed|stalled|blocked|invalidated",
  "contract": {"task_id": "T1", "objective": "..."},
  "depends_on": ["T0"],
  "produces": ["path#symbol"],
  "consumes": ["path#symbol"],
  "verified_by": ["E1"],
  "assumes": ["A1"],
  "retry_signature": null
}
```

`git` stores only a reconciliation marker: branch, HEAD, dirty paths, last-reconciled timestamp, and optional Human-change marker. Evidence stores compact references and validity scope, never copied command logs.

Impact rule: a changed artifact/task directly invalidates consumers/dependents and evidence/assumptions tied to the changed semantic surface; continue transitively only through those invalid edges. Unrelated nodes remain valid.
