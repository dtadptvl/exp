# Benchmark results

Status: **NOT_RUN** as of 2026-09-25.

## Why no live numbers are reported

The environment used to research/build this package has no `kilo` executable on PATH and no access to the user's `9router/sub` provider credentials or actual Prime model configuration. Running the required model baselines is therefore impossible here without inventing infrastructure or credentials.

No quality, token, cost, or latency values are fabricated.

## Completed validation

- Supplied reference ZIP extracted and audited.
- Its nine static artifact tests were executed and passed.
- Current package static validation is implemented in `tests/test_artifact.py` and is run during package creation.
- GitHub branch for implementation: `prime-sub-research-20260925` in `dtadptvl/exp`.

## Required live runs

Run:

```bash
python evaluation/run_eval.py --mode all --trials 3
```

Then aggregate by configuration and case. Do not set final success thresholds until the three baselines and important-case variance are available.

## Success fields pending evidence

| Requirement | Status |
|---|---|
| Quality gap vs Prime-only within justified threshold | UNMEASURED |
| Prime token reduction | UNMEASURED |
| Verification-rate improvement | UNMEASURED |
| Premature-completion reduction | UNMEASURED |
| Regression rate | UNMEASURED |
| Unnecessary-edit rate | UNMEASURED |
| Latency/tool-cost impact | UNMEASURED |
| Remaining `9router/sub` failure patterns | UNMEASURED |

The architecture must not be called successful until these are measured.
