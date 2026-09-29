# Task Contract

Prime must send exactly one raw JSON object with these fields and no others:

```json
{
  "task_id": "T1",
  "objective": "one concrete deliverable",
  "in_scope": ["paths/symbols/behaviors allowed to change"],
  "out_of_scope": ["explicit exclusions"],
  "acceptance": ["observable pass conditions"],
  "hard_constraints": ["must/must-not invariants"],
  "relevant_files_symbols": ["minimum starting refs"],
  "dependencies": ["only live task/artifact/decision/assumption/evidence refs needed now"],
  "verification": ["exact focused commands/checks"],
  "stop_condition": "stop once acceptance passes and no in-scope blocker remains"
}
```

Runtime enforcement:
- raw JSON only; no prose wrapper or code fence;
- exact top-level fields only;
- `in_scope`, `acceptance`, `relevant_files_symbols`, and `verification` must be non-empty;
- at most 12 items per array, each single-line and <= 1,200 characters;
- hard maximum 16,000 prompt characters; target <= 6,000;
- runtime canonicalizes/deduplicates the JSON and pins routing to custom `sub` on `9router/sub`.

Quality rule: encode the minimum facts needed to act. Use paths/symbols, IDs, acceptance conditions, constraints, and exact commands instead of copied code, logs, old Sub transcripts, or roadmap/history. A suspected root cause must remain something Sub verifies unless deterministic evidence already established it.

Re-anchor the contract after compaction/restart, every Sub return, material discovery, before scope expansion, and before final acceptance. Durable conclusions belong in state/evidence once; later contracts should refer to their IDs rather than restating them.
