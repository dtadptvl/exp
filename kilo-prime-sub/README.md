# Kilo Prime/Sub researched package

This branch stores the researched, statically validated standalone Prime/Sub package as an exact ZIP snapshot.

- Artifact: `kilo-prime-sub-researched.zip`
- SHA-256: `f14c11d9e13216d6ee32807a2c32bf786103aa1681bf478fbfe50698a6ff5506`
- Package static validation: 15/15 tests passed.
- Python compile check: passed for the evaluation harness and artifact tests.
- Evaluation fixture sanity: all 20 cases start in their intended state (19 initially failing, 1 deliberate no-edit case passing).
- Reference ZIP static validation: 9/9 tests passed.
- Eval harness smoke: passed with a dummy CLI; raw JSONL/stderr transcript retention is implemented.
- Live Prime-only / current Prime/Sub / optimized Prime/Sub model evaluation: `NOT_RUN` in the authoring environment because no `kilo` executable or user provider credentials were available.
- Mandatory live E2E architecture scenarios: `NOT_RUN` for the same reason and are documented in `evaluation/e2e-scenarios.md` inside the archive.

The archive contains the standalone folder with global `prime.md` and `Sub.md`, installer/uninstaller, config merge guide, minimal state and task-contract protocols, smoke test, 20-case evaluation set, trajectory rubric, live eval harness, research report, E2E scenario plan, and rejected-machinery review.

The package deliberately does not claim near-Prime quality, token reduction, latency improvement, or pass/fail success thresholds until the live three-way benchmark is run with the intended Prime model and `9router/sub`.
