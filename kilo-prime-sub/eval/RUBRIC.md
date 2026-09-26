# Eval scoring rubric

## Prime

Per case record: `task_success`, `regression`, `unnecessary_files`, `unauthorised_scope`, `unnecessary_delegation`, `unnecessary_abstraction_refactor`, `premature_completion`, `post_success_changes`, `objective_retention`, `repair_of_repair`, `Prime_tokens`, `Prime_tools`, `elapsed_time`.

Failure taxonomy: `goal_drift`, `instruction_drift`, `scope_creep`, `overthinking`, `premature_completion`, `bad_delegation`, `bad_context_selection`, `bad_verification`, `stale_state`, `dependency_impact_failure`.

A prompt/harness change is retained only when repeated evals show a stable win without material coding-success regression. Do not add a new prompt rule from one anecdotal failure.

## Sub

Per case record: `correctness`, `relevant_files_inspected`, `unsupported_assumptions`, `root_cause`, `verification`, `diff_reviewed`, `premature_completion`, `unnecessary_changes`, `regression`, `retries`, `tokens`, `tools`, `elapsed_time`.

Target direction: premature completion/unsupported assumptions/regression/unnecessary edits down; root-cause/verification/diff review up; coding success not materially worse; cost reasonable.

## Repetition

Run nondeterministic model cases multiple times with the same repo fixture/model/config and record each trajectory. Compare distributions, not a single cherry-picked run.
