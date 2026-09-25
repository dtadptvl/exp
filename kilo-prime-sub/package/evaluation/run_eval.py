#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from cases import CASES, Case, get  # noqa: E402

MODES = ("prime-only", "baseline", "optimized")


def write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def run(cmd: list[str], cwd: Path, timeout: int | None = None, env: dict[str, str] | None = None) -> dict[str, Any]:
    start = time.monotonic()
    try:
        p = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True, timeout=timeout, env=env)
        return {
            "cmd": cmd,
            "returncode": p.returncode,
            "stdout": p.stdout,
            "stderr": p.stderr,
            "elapsed_seconds": round(time.monotonic() - start, 3),
            "timed_out": False,
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "cmd": cmd,
            "returncode": 124,
            "stdout": exc.stdout or "",
            "stderr": exc.stderr or "",
            "elapsed_seconds": round(time.monotonic() - start, 3),
            "timed_out": True,
        }


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def snapshot(root: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for p in root.rglob("*"):
        if not p.is_file():
            continue
        rel = p.relative_to(root).as_posix()
        if rel.startswith(".git/") or rel.startswith(".prime/"):
            continue
        out[rel] = sha(p)
    return out


def install_eval_agents(root: Path, mode: str) -> None:
    agent_dir = root / ".kilo" / "agents"
    if mode == "prime-only":
        write(agent_dir / "prime.md", (HERE / "prime-only" / "prime.md").read_text(encoding="utf-8"))
        return
    src = HERE / ("baseline" if mode == "baseline" else ".." / Path("agents"))
    if mode == "baseline":
        prime = HERE / "baseline" / "prime.md"
        sub = HERE / "baseline" / "sub.md"
    else:
        prime = ROOT / "agents" / "prime.md"
        sub = ROOT / "agents" / "sub.md"
    write(agent_dir / "prime.md", prime.read_text(encoding="utf-8"))
    write(agent_dir / "sub.md", sub.read_text(encoding="utf-8"))


def prepare(case: Case, mode: str, dest: Path) -> dict[str, str]:
    dest.mkdir(parents=True, exist_ok=True)
    for rel, text in case.files.items():
        write(dest / rel, text)
    install_eval_agents(dest, mode)
    for pkg in (dest / "src", dest / "tests"):
        if pkg.exists() and pkg.is_dir() and not (pkg / "__init__.py").exists():
            write(pkg / "__init__.py", "")
    run(["git", "init", "-b", "eval"], dest)
    run(["git", "config", "user.email", "eval@example.invalid"], dest)
    run(["git", "config", "user.name", "Prime Sub Eval"], dest)
    run(["git", "add", "."], dest)
    commit = run(["git", "commit", "-m", "fixture baseline"], dest)
    if commit["returncode"] != 0:
        raise RuntimeError(commit["stderr"])
    for rel, text in case.dirty.items():
        write(dest / rel, text)
    return snapshot(dest)


def parse_json_lines(text: str) -> list[Any]:
    events = []
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return events


def collect_usage_like(value: Any, path: str = "$") -> list[dict[str, Any]]:
    found: list[dict[str, Any]] = []
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}"
            if key.lower() in {"usage", "tokens", "cost", "cost_usd"}:
                found.append({"path": child_path, "value": child})
            found.extend(collect_usage_like(child, child_path))
    elif isinstance(value, list):
        for i, child in enumerate(value):
            found.extend(collect_usage_like(child, f"{path}[{i}]"))
    return found


def tool_event_count(events: list[Any]) -> int:
    total = 0
    for event in events:
        if not isinstance(event, dict):
            continue
        t = str(event.get("type", "")).lower()
        if "tool" in t:
            total += 1
    return total


def check_case(case: Case, repo: Path) -> list[dict[str, Any]]:
    return [run(list(cmd), repo, timeout=120) for cmd in case.checks]


def diff_paths(repo: Path) -> list[str]:
    p = run(["git", "status", "--porcelain=v1"], repo)
    paths = []
    for line in p["stdout"].splitlines():
        if not line.strip():
            continue
        raw = line[3:]
        if " -> " in raw:
            raw = raw.split(" -> ", 1)[1]
        paths.append(raw.replace("\\", "/"))
    return sorted(set(paths))


def diff_numstat(repo: Path) -> list[dict[str, Any]]:
    p = run(["git", "diff", "--numstat", "--", "."], repo)
    rows: list[dict[str, Any]] = []
    for line in p["stdout"].splitlines():
        parts = line.split("\t", 2)
        if len(parts) != 3:
            continue
        add, delete, path = parts
        rows.append({
            "path": path.replace("\\", "/"),
            "additions": None if add == "-" else int(add),
            "deletions": None if delete == "-" else int(delete),
        })
    return rows


def run_trial(case: Case, mode: str, trial: int, args: argparse.Namespace, work: Path) -> dict[str, Any]:
    repo = work / f"{case.id}-{mode}-t{trial}"
    before = prepare(case, mode, repo)

    prompt = (
        f"EVAL CASE {case.id} ({case.category}).\n"
        f"{case.task}\n"
        "Work only in this repository. Preserve unrelated pre-existing changes. "
        "Do not modify .kilo/agents or evaluation control files. "
        "Do not commit, branch, checkout, reset, stash, stage, merge, rebase, or push during this eval. "
        "Leave implementation edits in the working tree and verify your result before finishing."
    )
    command = [args.kilo, "run", "--auto", "--format", "json", "--agent", "prime", prompt]
    kilo = run(command, repo, timeout=args.timeout, env=os.environ.copy())
    after = snapshot(repo)

    all_paths = set(before) | set(after)
    agent_changed = sorted(p for p in all_paths if before.get(p) != after.get(p))
    allowed = set(case.allowed_changes)
    unnecessary = sorted(p for p in agent_changed if p not in allowed and not p.startswith(".prime/"))

    dirty_preserved = True
    dirty_mismatches: list[str] = []
    for rel, expected in case.dirty.items():
        p = repo / rel
        actual = p.read_text(encoding="utf-8") if p.exists() else None
        if actual != expected:
            dirty_preserved = False
            dirty_mismatches.append(rel)

    checks = check_case(case, repo)
    validators_pass = all(c["returncode"] == 0 for c in checks)
    events = parse_json_lines(kilo["stdout"])
    transcript = args.transcript_dir / f"{case.id}-{mode}-t{trial}.jsonl"
    transcript.parent.mkdir(parents=True, exist_ok=True)
    transcript.write_text(kilo["stdout"], encoding="utf-8")
    stderr_file = args.transcript_dir / f"{case.id}-{mode}-t{trial}.stderr.txt"
    stderr_file.write_text(kilo["stderr"], encoding="utf-8")
    usage_like = []
    for idx, event in enumerate(events):
        for item in collect_usage_like(event):
            item["event_index"] = idx
            usage_like.append(item)

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "case": case.id,
        "category": case.category,
        "mode": mode,
        "trial": trial,
        "task": case.task,
        "kilo": {
            "returncode": kilo["returncode"],
            "timed_out": kilo["timed_out"],
            "elapsed_seconds": kilo["elapsed_seconds"],
            "stderr_tail": kilo["stderr"][-4000:],
            "json_event_count": len(events),
            "tool_event_count": tool_event_count(events),
            "usage_like": usage_like,
            "transcript_jsonl": str(transcript),
            "stderr_file": str(stderr_file),
        },
        "validation": {
            "pass": validators_pass and dirty_preserved and not unnecessary,
            "checks": [
                {
                    "cmd": c["cmd"],
                    "returncode": c["returncode"],
                    "stdout_tail": c["stdout"][-2000:],
                    "stderr_tail": c["stderr"][-2000:],
                }
                for c in checks
            ],
            "dirty_preserved": dirty_preserved,
            "dirty_mismatches": dirty_mismatches,
        },
        "scope": {
            "agent_changed_paths": agent_changed,
            "allowed_changes": list(case.allowed_changes),
            "unnecessary_paths": unnecessary,
            "git_status_paths": diff_paths(repo),
            "git_diff_numstat": diff_numstat(repo),
        },
        "workdir": str(repo),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=(*MODES, "all"), default="all")
    parser.add_argument("--case", action="append", help="Run one or more case IDs, e.g. --case C01")
    parser.add_argument("--trials", type=int, default=1)
    parser.add_argument("--timeout", type=int, default=1800, help="Harness wall-clock timeout per Kilo process, seconds")
    parser.add_argument("--kilo", default="kilo")
    parser.add_argument("--work-root", type=Path)
    parser.add_argument("--output", type=Path, default=HERE / "results.local.jsonl")
    parser.add_argument("--transcript-dir", type=Path, help="Directory for raw Kilo JSONL/stdout and stderr per trial")
    parser.add_argument("--keep-work", action="store_true")
    args = parser.parse_args()
    args.transcript_dir = args.transcript_dir or (args.output.parent / "transcripts.local")

    if shutil.which(args.kilo) is None:
        print(f"ERROR: {args.kilo!r} was not found on PATH. Live benchmark cannot run.", file=sys.stderr)
        return 2
    if args.trials < 1:
        parser.error("--trials must be >= 1")

    cases = [get(x) for x in args.case] if args.case else list(CASES)
    modes = list(MODES) if args.mode == "all" else [args.mode]

    owned_tmp = args.work_root is None
    work = args.work_root or Path(tempfile.mkdtemp(prefix="prime-sub-eval-"))
    work.mkdir(parents=True, exist_ok=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)

    print(f"work root: {work}")
    print(f"results:   {args.output}")
    failed = 0
    with args.output.open("w", encoding="utf-8") as fh:
        for case in cases:
            for mode in modes:
                for trial in range(1, args.trials + 1):
                    print(f"[{case.id}] {mode} trial {trial}")
                    result = run_trial(case, mode, trial, args, work)
                    fh.write(json.dumps(result, ensure_ascii=False) + "\n")
                    fh.flush()
                    if not result["validation"]["pass"]:
                        failed += 1
                        print("  FAIL")
                    else:
                        print("  PASS")

    if owned_tmp and not args.keep_work:
        shutil.rmtree(work, ignore_errors=True)
    elif owned_tmp:
        print(f"kept work root: {work}")

    print(f"completed {len(cases) * len(modes) * args.trials} trials; validation failures={failed}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
