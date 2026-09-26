# Task Contract

Use exactly these fields unless a concrete eval-proven need requires one more field:

```json
{
  "task_id": "T1",
  "objective": "one concrete deliverable",
  "in_scope": ["paths/symbols/behaviors allowed to change"],
  "out_of_scope": ["explicit exclusions"],
  "acceptance": ["observable pass conditions"],
  "hard_constraints": ["must/must-not invariants"],
  "relevant_files_symbols": ["minimum starting refs"],
  "dependencies": ["task/artifact/decision/assumption IDs needed now"],
  "verification": ["exact focused commands/checks"],
  "stop_condition": "stop once acceptance passes and no in-scope blocker remains"
}
```

Re-anchor the contract after compaction/restart, every Sub return, material discovery, before scope expansion, and before final acceptance. Send minimum sufficient context only: contract + relevant refs/direct deps/live decision or assumption IDs/state facts/commands/Git-diff refs.
