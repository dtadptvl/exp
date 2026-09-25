# Minimal persistent state

`.prime/state.json` is the only architecture-specific live orchestration state. Git remains source of truth for code, diffs, history, branch, and commits.

## Initial state

```json
{
  "version": 1,
  "objective": {"revision": 0, "text": ""},
  "phase": "capture",
  "tasks": {},
  "active": null,
  "decisions": {},
  "assumptions": {},
  "evidence": {},
  "git": {"branch": null, "head": null, "dirty": []},
  "next": "capture objective"
}
```

## Task entry

A task entry should stay compact:

```json
{
  "status": "pending",
  "depends_on": ["T1"],
  "touches": ["src/api.ts#parseRequest", "tests/api.test.ts"],
  "acceptance": ["A1", "A2"],
  "assumptions": ["AS1"],
  "evidence": ["E3"],
  "contract_revision": 1
}
```

Allowed status values are `pending`, `active`, `done`, `invalid`, and `blocked`. Do not store attempt counters or full transcripts.

## Decision, assumption, and evidence entries

Keep only items that matter beyond the current turn.

```json
{
  "decisions": {
    "D1": {"text": "Keep public API backward compatible", "sources": ["user:r3"]}
  },
  "assumptions": {
    "AS1": {"text": "handler X consumes result Y", "status": "active", "sources": ["src/x.ts#handler"]}
  },
  "evidence": {
    "E3": {
      "kind": "test",
      "ref": "pytest tests/test_api.py::test_case",
      "head": "<sha>",
      "paths": ["src/api.py", "tests/test_api.py"],
      "outcome": "pass"
    }
  }
}
```

Evidence is a reference plus validity facts, not copied log output. If HEAD or relevant paths changed, re-check validity before reuse.

## Incremental reconciliation

On a new human prompt, Sub result/failure, Prime resume, or detected repository change:

1. Compare current objective revision, branch, HEAD, and dirty paths with state.
2. Treat current repository and human changes as authoritative.
3. Map changed paths/symbols to task `touches` references.
4. Inspect only the directly affected task and dependency closure.
5. Invalidate downstream tasks only when a consumed task result, active assumption, or evidence reference is no longer valid.
6. Create the minimum repair/reverification tasks needed and update `next`.
7. Refresh the Git fingerprint and affected state entries.

Do not rebuild the whole task graph when the delta is local.

## Retroactive dependency example

For `T1 -> T2 -> T3 -> T4`, if a human changes an artifact produced by T2:

- mark T2 for reconciliation;
- inspect T3 inputs/assumptions that consume T2;
- invalidate only the T3 results/evidence actually affected;
- continue transitively to T4 only if T4 consumed an invalidated T3 result;
- repair T2 and selectively reverify affected T3/T4 surfaces.

A dependency edge is a reason to inspect impact, not automatic proof that every downstream result is invalid.
