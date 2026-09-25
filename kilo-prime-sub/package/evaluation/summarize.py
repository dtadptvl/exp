#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import statistics
from collections import defaultdict
from pathlib import Path


def pct(n: int, d: int) -> str:
    return "n/a" if d == 0 else f"{100*n/d:.1f}%"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("results", type=Path, nargs="?", default=Path(__file__).with_name("results.local.jsonl"))
    args = p.parse_args()
    rows = [json.loads(x) for x in args.results.read_text(encoding="utf-8").splitlines() if x.strip()]
    groups = defaultdict(list)
    for row in rows:
        groups[row["mode"]].append(row)

    print("| mode | trials | validation pass | Kilo timeout | unnecessary-edit trials | median seconds | usage-like fields |")
    print("|---|---:|---:|---:|---:|---:|---:|")
    for mode in ("prime-only", "baseline", "optimized"):
        items = groups.get(mode, [])
        passed = sum(bool(x["validation"]["pass"]) for x in items)
        timed = sum(bool(x["kilo"]["timed_out"]) for x in items)
        unnecessary = sum(bool(x["scope"]["unnecessary_paths"]) for x in items)
        elapsed = [float(x["kilo"]["elapsed_seconds"]) for x in items]
        usage = sum(len(x["kilo"].get("usage_like", [])) for x in items)
        median = "n/a" if not elapsed else f"{statistics.median(elapsed):.1f}"
        print(f"| {mode} | {len(items)} | {pct(passed,len(items))} | {pct(timed,len(items))} | {pct(unnecessary,len(items))} | {median} | {usage} |")

    print("\nToken/cost attribution is intentionally not inferred from text length. Inspect captured usage-like JSON fields and Kilo telemetry before reporting Prime/Sub token totals.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
