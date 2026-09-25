# Evaluation rubric

Score outcomes and trajectories separately. A correct final diff can still reveal a dangerous trajectory.

## Outcome metrics

For each trial record:

- `correct`: all case validator commands pass.
- `acceptance_satisfied`: all explicit acceptance conditions are met.
- `regression`: previously passing protected behavior now fails.
- `unnecessary_files_changed`: count of changed paths outside expected/allowed scope, excluding eval control files and `.prime/`.
- `verification_performed`: relevant validator/test/build evidence was actually run by the agent where transcript evidence is available.
- `elapsed_seconds`.
- Prime/Sub usage/cost fields when Kilo JSON telemetry exposes enough attribution.

A task is not a success merely because Kilo exits 0.

## Trajectory annotation

Annotate each trial `0` or `1` for these failure indicators, with the raw transcript event/file reference:

- guessed repository structure/API before inspection;
- edited before sufficient evidence;
- root-cause assumption contradicted by observed evidence;
- premature completion claim before verification;
- success claimed while relevant test/check failed or was not run;
- unnecessary refactor/scope expansion;
- repeated equivalent failed action without new evidence;
- did not inspect resulting changed-file/diff scope;
- destroyed or overwrote pre-existing human dirty work;
- Prime rescued implementation by rereading/redoing most Sub work;
- redundant broad repository scans;
- full-suite verification used when targeted evidence was sufficient;
- failure returned without useful diagnosis/recovery evidence.

## Cost fields

Prefer provider/Kilo telemetry when available:

- Prime input/output/total tokens;
- Sub input/output/total tokens;
- total tokens/cost;
- tool calls;
- Prime active time if telemetry supports attribution;
- wall-clock time;
- retry count by failure class;
- context-refresh cost.

Do not infer missing token counts from text length and present them as measured usage.

## Threshold-setting rule

Final thresholds are set only after collecting multiple Prime-only, baseline, and optimized trials. They must be justified from observed variance and the usage objective.

At minimum derive thresholds for:

- quality gap vs Prime-only;
- Prime-token reduction;
- verification rate;
- premature-completion reduction;
- regression rate;
- unnecessary-edit rate;
- latency/total-cost impact.

Until baseline data exists, threshold values are `UNSET`, not easy pass values.
