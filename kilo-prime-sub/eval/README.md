# Eval suite

- `cases/prime.jsonl`: 28 realistic controller cases.
- `cases/sub.jsonl`: 24 worker cases.
- `RUBRIC.md`: required metrics and failure taxonomy.
- `control_model.py` + `tests/test_control.py`: deterministic A-H lifecycle/state simulations.
- `run_live.py`: live Kilo gate/runner scaffold. It refuses to invent results if Kilo/provider prerequisites are missing.
- `BASELINE-VS-OPTIMIZED.md`: recorded structural/control results and live-eval status.

Optimization method follows trajectory/evidence-driven iteration: baseline -> collect trajectory/result -> classify failure -> smallest prompt/harness change -> rerun -> retain only stable wins. The suite emphasizes behavioral choices rather than only whether file I/O works, matching the distinction used by Gemini CLI behavioral evals.
