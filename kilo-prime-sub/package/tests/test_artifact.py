#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def fm(path: str) -> str:
    text = read(path)
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    assert match, f"{path}: missing frontmatter"
    return match.group(1)


def test_exact_runtime_topology() -> None:
    prime = fm("agents/prime.md")
    sub = fm("agents/Sub.md")
    install = read("install.ps1")
    assert "mode: primary" in prime
    assert '"*": deny' in prime and "Sub: allow" in prime
    assert "mode: subagent" in sub
    assert "model: 9router/sub" in sub
    assert re.search(r"^steps:\s*[1-9]\d*\s*$", sub, re.M)
    assert re.search(r"^\s*task:\s*deny\s*$", sub, re.M)
    assert "Permission-Action $prime.permission 'task' 'Sub'" in install
    assert "Permission-Action $sub.permission 'read' '.prime/state.json'" in install
    assert re.search(r"^\s*doom_loop:\s*deny\s*$", sub, re.M)
    assert sorted(p.name for p in (ROOT / "agents").glob("*.md")) == ["Sub.md", "prime.md"]


def test_prime_enforces_fresh_sequential_explicit_sub_model() -> None:
    prime = read("agents/prime.md")
    for needle in (
        "subagent_type: Sub",
        "model: 9router/sub",
        "Do not resume `task_id`",
        "Run at most one Sub at a time",
        "No background/concurrent Sub work",
    ):
        assert needle in prime
    assert "whole conversation" in prime
    assert "Do not rescan the whole repository" in prime


def test_step_count_is_only_emergency_not_primary_control() -> None:
    prime = read("agents/prime.md").lower()
    sub = read("agents/Sub.md").lower()
    readme = read("README.md").lower()
    for text in (prime, sub, readme):
        assert "emergency" in text
        assert "primary" in text
    assert "progress means new relevant evidence" in prime
    assert "retry budget" in sub


def test_sub_git_and_state_ownership_boundary() -> None:
    sub = fm("agents/Sub.md")
    assert '"git *": deny' in sub
    for safe in ("git status *", "git diff *", "git show *", "git log *", "git rev-parse *", "git ls-files *"):
        assert f'"{safe}": allow' in sub
    assert re.search(r'^\s*read:\s*$', sub, re.M)
    assert '".prime/state.json": deny' in sub
    body = read("agents/Sub.md")
    assert "Never read or edit `.prime/state.json`" in body
    for verb in ("commit", "branch", "push", "merge", "rebase", "reset", "checkout", "stash", "add", "worktree"):
        assert verb in body


def test_state_schema_supports_minimal_dependency_invalidation() -> None:
    state = read("protocol/state-schema.md")
    for key in ('"version"', '"objective"', '"phase"', '"tasks"', '"decisions"', '"assumptions"', '"evidence"', '"git"', '"next"'):
        assert key in state
    for key in ('"depends_on"', '"touches"', '"contract_revision"'):
        assert key in state
    assert "Do not store attempt counters" in state
    assert "not automatic proof that every downstream result is invalid" in state


def test_contract_is_minimum_sufficient_context() -> None:
    contract = read("protocol/task-contract.md")
    for field in ("CONTRACT", "OBJECTIVE_REV", "OBJECTIVE:", "SCOPE:", "ACCEPT:", "FACTS:", "CONSTRAINTS:", "ENTRY:", "BASE:", "VERIFY:"):
        assert field in contract
    assert "whole conversation" in contract
    assert "Prime speculation" in contract
    assert "new Task session" in contract


def test_config_guide_has_fixed_invariants_and_version_compatibility() -> None:
    guide = read("CONFIG-MERGE-GUIDE.md")
    assert '"default_agent": "prime"' in guide
    assert '"subagent_depth": 1' in guide
    assert '"chunkTimeout": 1800000' in guide
    assert "v7.7.9" in guide and "v7.7.12 pre-release" in guide
    assert "task_model_selection" in guide
    assert "Do not set `subagent_model`" in guide
    assert "Do not set `provider.9router.options.timeout` to `false`" in guide
    assert "Do not disable or replace built-in agents" in guide


def test_installer_never_mutates_kilo_json_and_validates_invariants() -> None:
    ps = read("install.ps1")
    lower = ps.lower()
    assert "kilo debug paths" in lower
    assert "kilo debug config" in lower
    assert "kilo debug agent" in lower
    assert "default_agent" in ps and "subagent_depth" in ps
    assert "task_model_selection" in ps and "7.7.12" in ps
    assert "chunkTimeout" in ps and "9router" in ps
    assert "prime-sub-install.json" in ps
    assert "Copy-Item" in ps
    # The installer may Set-Content only to its receipt, never to a Kilo config file.
    for line in ps.splitlines():
        if "Set-Content" in line:
            assert "receiptPath" in line
    for line in ps.splitlines():
        ll = line.lower()
        if any(v in ll for v in ("set-content", "add-content", "out-file", "copy-item", "remove-item")):
            assert "kilo.json" not in ll and "kilo.jsonc" not in ll


def test_uninstall_has_safe_rollback_receipt_and_modification_guard() -> None:
    ps = read("uninstall.ps1")
    assert "prime-sub-install.json" in ps
    assert "prime_sha256" in ps and "sub_sha256" in ps
    assert "-Force" in ps
    assert "changed after installation" in ps
    assert "Copy-Item" in ps and "Remove-Item" in ps
    for line in ps.splitlines():
        ll = line.lower()
        if any(v in ll for v in ("set-content", "add-content", "out-file", "copy-item", "remove-item")):
            assert "kilo.json" not in ll and "kilo.jsonc" not in ll


def load_cases():
    spec = importlib.util.spec_from_file_location("eval_cases", ROOT / "evaluation" / "cases.py")
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod.CASES


def test_eval_set_has_twenty_diverse_cases_and_required_baselines() -> None:
    cases = load_cases()
    assert len(cases) == 20
    ids = [c.id for c in cases]
    assert ids == [f"C{i:02d}" for i in range(1, 21)]
    categories = {c.category for c in cases}
    for required in ("bug-fix", "multi-file-change", "regression", "ambiguous-requirement", "config-build", "no-unnecessary-edit", "misleading-hypothesis", "dirty-working-tree", "dependency-change"):
        assert required in categories
    assert (ROOT / "evaluation" / "prime-only" / "prime.md").exists()
    assert (ROOT / "evaluation" / "baseline" / "prime.md").exists()
    assert (ROOT / "evaluation" / "baseline" / "sub.md").exists()
    harness = read("evaluation/run_eval.py")
    for mode in ("prime-only", "baseline", "optimized"):
        assert mode in harness
    assert "--trials" in harness and "--timeout" in harness
    assert "--transcript-dir" in harness
    assert "transcript_jsonl" in harness and "git_diff_numstat" in harness
    assert "Do not commit, branch, checkout, reset, stash, stage, merge, rebase, or push" in harness



def test_e2e_plan_covers_required_architecture_scenarios() -> None:
    text = read("evaluation/e2e-scenarios.md")
    for item in (
        "E01 Happy path",
        "E02 Incorrect implementation detected",
        "E03 Premature completion",
        "E04 Sub technical failure",
        "E05 Stall / hang recovery",
        "E06 Fresh replacement Sub",
        "E07 Prime context refresh",
        "E08 Dirty working tree preservation",
        "E09 Human modification during workflow",
        "E10 Retroactive dependency change",
        "E11 Failure/recovery continuity",
    ):
        assert item in text
    assert "NOT_RUN" in text
    assert "Do not convert `NOT_RUN` to PASS" in text

def test_live_results_are_not_fabricated() -> None:
    results = read("evaluation/RESULTS.md")
    assert "NOT_RUN" in results
    assert "no `kilo` executable" in results
    assert "No quality, token, cost, or latency values are fabricated" in results
    for state in ("UNMEASURED", "Prime-only", "9router/sub"):
        assert state in results


def test_reference_zip_is_analysis_not_runtime_dependency() -> None:
    research = read("RESEARCH.md")
    readme = read("README.md")
    assert "reference ZIP" in readme
    assert "not as a specification or runtime dependency" in readme
    assert "Attached ZIP analysis" in research
    for path in ROOT.rglob("*"):
        if not path.is_file():
            continue
        assert "prime-sub-minimal-adaptive-20260919-compact.zip" not in path.name


def test_rejected_machinery_and_native_first_boundary() -> None:
    rejected = read("REJECTED-MACHINERY.md")
    for needle in ("Per-Sub Git worktrees", "Custom scheduler", "Custom session store", "Database/journal", "Full Prime review", "Fixed total recovery attempts"):
        assert needle in rejected
    research = read("RESEARCH.md")
    assert "No custom watchdog is admitted yet" in research
    assert "sequential foreground Task" in research


def test_docs_avoid_em_dash_style() -> None:
    for path in ROOT.rglob("*.md"):
        assert chr(0x2014) not in path.read_text(encoding="utf-8"), f"em dash in {path.relative_to(ROOT)}"


def main() -> int:
    tests = [value for name, value in sorted(globals().items()) if name.startswith("test_") and callable(value)]
    for test in tests:
        test()
        print(f"PASS {test.__name__}")
    print(f"PASS {len(tests)} tests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
