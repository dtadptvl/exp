# Sub Result

Return one compact object, no essay or raw reasoning:

```json
{
  "task_id": "T1",
  "status": "success|failed|blocked",
  "summary": "one short outcome",
  "files_changed": ["path"],
  "verification": [{"check": "command/check", "result": "pass|fail|not_run"}],
  "evidence": ["test/diff/runtime refs"],
  "risks": ["remaining in-scope uncertainty only"],
  "out_of_scope_findings": ["report only"],
  "next_required_action": "none|specific action"
}
```
