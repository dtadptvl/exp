# Required end-to-end architecture scenarios

Status: **NOT_RUN** in the authoring environment because `kilo` and the user's configured Prime/`9router/sub` providers are unavailable. These are live architecture tests, not substitutes for the 20 coding-task eval cases.

Run them on the dedicated experiment branch or disposable fixture repositories after `setup.cmd` passes. Preserve the raw Kilo JSONL transcript, Git before/after state, `.prime/state.json` before/after state, and validation commands for every scenario.

## E01 Happy path

Give Prime one bounded failing coding task with a deterministic regression test.

Expected evidence:
- Prime launches exactly one fresh `Sub` using `9router/sub`;
- Sub implements and runs targeted verification;
- Prime accepts without rereading the whole repository/full implementation;
- final validator passes and unrelated files are unchanged.

## E02 Incorrect implementation detected

Use a task where a plausible shallow patch satisfies one symptom but violates a second deterministic acceptance check.

Expected evidence:
- initial wrong change is not accepted merely because Sub returns `DONE`;
- failed independent check is recorded;
- Prime reconciles and launches a materially different repair/reverification action;
- final acceptance occurs only after the full bounded acceptance set passes.

## E03 Premature completion

Use a task that tempts the model to stop after editing before running the relevant test.

Expected evidence:
- transcript records whether Sub attempted premature `DONE`;
- Prime does not mark the task accepted without verification evidence;
- any missing evidence creates a repair/verification action rather than false PASS.

## E04 Sub technical failure

Give Sub a bounded task with an intentionally misleading initial hypothesis or a failure requiring stronger reasoning.

Expected evidence:
- Sub returns `FAILED_TECHNICAL` with stable failure signature, disproven hypotheses, useful partial work, and next diagnostic;
- Prime preserves valid work/evidence and replans instead of asking the human to solve an ordinary technical problem.

## E05 Stall / hang recovery

Exercise three distinct liveness classes separately:
1. repeated equivalent tool failure that should hit native `doom_loop` denial;
2. long/stuck shell command that should hit the native command timeout;
3. provider stream silence beyond the configured finite `chunkTimeout`.

Expected evidence:
- each failure is bounded by its native mechanism;
- Prime receives an error/failure state and recovers through reconciliation plus a materially different action;
- generic step count is not used as the primary detector for any of the three cases.

A fourth semantic no-progress case may intentionally reach the high `steps` ceiling to prove it behaves only as the last emergency circuit breaker. Treat that as a failure event, never as successful completion.

## E06 Fresh replacement Sub

After E04 or another failed child, launch the recovery contract without `task_id`.

Expected evidence:
- a new child session ID is created;
- recovery prompt contains only minimum sufficient facts/evidence from the failed contract;
- the replacement succeeds without prior child transcript/history being inherited.

## E07 Prime context refresh

Start a multi-task objective, persist `.prime/state.json`, then end the Prime session. Start a new Prime session in the same repository with a concise continuation request.

Expected evidence:
- Prime reconstructs current phase/active dependencies from state plus current Git evidence;
- fresh repository evidence overrides any stale state item;
- no full conversation replay or full repository scan is required before the next bounded action.

## E08 Dirty working tree preservation

Create an unrelated uncommitted human edit before the delegated task.

Expected evidence:
- contract names the pre-existing dirty path;
- Sub does not reset/revert/overwrite it;
- exact human bytes remain unchanged after task completion;
- Prime acceptance explicitly verifies preservation.

## E09 Human modification during workflow

Complete one task, then manually change a relevant source file or requirement before the next task.

Expected evidence:
- Prime detects current Git/working-tree delta at reconciliation;
- human/external change overrides stale agent assumptions;
- only affected task/evidence entries are invalidated or rechecked.

## E10 Retroactive dependency change

Build at least a three-node dependency chain, e.g. `T1 -> T2 -> T3`. After T2/T3 are accepted, modify an artifact produced by T1/T2.

Expected evidence:
- changed artifact maps to the owning task;
- direct/transitive dependents are inspected selectively;
- downstream items are invalidated only when their consumed assumption/result/evidence is actually stale;
- minimum repair tasks run, followed by selective reverification rather than full pipeline replay.

## E11 Failure/recovery continuity

Interrupt or fail a task after it has produced useful partial changes/evidence, then start a new Prime session.

Expected evidence:
- current Git plus compact state, not stale conversation memory, determine continuation;
- valid partial work is preserved;
- invalid assumptions are not resurrected;
- workflow resumes from the smallest correct next action.

## Result record

For each scenario record:

```text
SCENARIO: E0x
STATUS: PASS | FAIL | NOT_RUN
KILO_VERSION:
PRIME_MODEL:
SUB_MODEL: 9router/sub
BASE_HEAD:
FINAL_HEAD:
TRANSCRIPT:
STATE_BEFORE:
STATE_AFTER:
VALIDATION:
FAILURE_CLASS/RECOVERY (if applicable):
NOTES:
```

Do not convert `NOT_RUN` to PASS based on static inspection or prompt content alone.
