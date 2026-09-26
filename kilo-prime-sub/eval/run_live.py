from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    kilo = shutil.which("kilo")
    if not kilo:
        print(json.dumps({"status":"blocked","reason":"kilo executable not found","results":[]}, indent=2))
        return 2
    proc = subprocess.run([kilo, "debug", "agent", "sub"], text=True, capture_output=True)
    if proc.returncode != 0:
        print(json.dumps({"status":"blocked","reason":"kilo debug agent sub failed","stderr":proc.stderr[-2000:],"results":[]}, indent=2))
        return 2
    try:
        agent=json.loads(proc.stdout)
    except json.JSONDecodeError:
        print(json.dumps({"status":"blocked","reason":"kilo debug agent sub was not JSON","results":[]}, indent=2))
        return 2
    model=f"{agent.get('model',{}).get('providerID')}/{agent.get('model',{}).get('modelID')}"
    if model != "9router/sub":
        print(json.dumps({"status":"blocked","reason":f"effective Sub model is {model}, expected 9router/sub","results":[]}, indent=2))
        return 2
    print(json.dumps({
        "status":"ready",
        "note":"Prerequisites validate. Execute the JSONL cases against controlled repo fixtures and record rubric metrics; this scaffold intentionally does not fabricate model trajectories.",
        "prime_cases": sum(1 for _ in (ROOT/'eval/cases/prime.jsonl').open(encoding='utf-8')),
        "sub_cases": sum(1 for _ in (ROOT/'eval/cases/sub.jsonl').open(encoding='utf-8')),
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
