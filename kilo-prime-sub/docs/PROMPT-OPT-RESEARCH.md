# Prompt/eval research applied

Research was used as design pressure, not copied as machinery.

- Gemini CLI behavioral evals distinguish model behavior tests from ordinary integration tests. Applied here by keeping explicit Prime/Sub behavioral case sets and trajectory/failure metrics rather than treating package unit tests as proof of agent quality.
- GEPA's trajectory-reflection approach supports changing prompts from observed failure traces and evaluating the mutation. Applied as `baseline -> trajectories -> failure class -> smallest prompt/harness change -> rerun`; no automated evolutionary framework was added because the brief favors minimal machinery.
- mini-swe-agent demonstrates that a small agent loop can remain competitive. Applied by keeping Sub's loop explicit and short, with repository tools providing facts and deterministic verification providing feedback.
- Budget-aware test-time scaling shows that simply granting more tool budget does not guarantee better results. Applied by refusing to use token/tool/step budgets as success or anti-hang controls; budgets remain telemetry while progress and verification determine continuation.
- Recent trajectory-aware regression-test selection research reinforces using representative trajectory evidence to reduce eval cost. The supplied case sets are structured for subset selection later, but no embedding/clustering dependency is added until real trajectories justify it.

Sources checked 2026-09-26: Google Gemini CLI behavioral-evals README; GEPA paper/repository; SWE-agent mini-swe-agent; Google ADK evaluation/development materials; Budget-Aware Tool-Use/BATS research; trajectory-aware SWE-agent regression-testing research.
