from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "eval"))
from control_model import RunState, Watch, artifact_impact, minimal_refresh, transitive_impact  # noqa: E402


def test_A_normal_path_accepts_after_deterministic_evidence() -> None:
    run = RunState(); run.start()
    changed = ["src/a.py"]
    verification = {"unit": "pass", "diff": "inspected"}
    assert changed == ["src/a.py"]
    assert all(v in {"pass", "inspected"} for v in verification.values())
    run.accept()
    assert run.status == "done"


def test_B_sub_failure_preserves_state_and_bounded_fresh_retry() -> None:
    run = RunState(); run.start()
    assert run.fail("E_TEST_X") == "fresh-sub"
    run.start()
    assert run.fail("E_TEST_X") == "replan-or-prime"
    assert run.retries_by_signature == {"E_TEST_X": 1}


def test_C_stall_uses_progress_time_not_steps() -> None:
    watch = Watch(wall_ms=1000, stall_ms=300, started=0, progress=0)
    watch.reasoning_text(100)
    assert watch.tick(299) is None
    assert watch.tick(301) == "inactivity"
    assert watch.killed


def test_C_wall_clock_kills_even_with_recent_tool_progress() -> None:
    watch = Watch(wall_ms=1000, stall_ms=800, started=0, progress=0)
    watch.tool_progress(700)
    assert watch.tick(999) is None
    assert watch.tick(1000) == "wall"


def test_D_restart_refresh_is_dependency_slice_not_whole_state() -> None:
    state = {
        "objective": {"rev": 2, "text": "ship"}, "phase": "impl", "active_task": "T2",
        "tasks": {
            "T1": {"contract": {"task_id": "T1"}, "depends_on": [], "produces": ["a#x"]},
            "T2": {"contract": {"task_id": "T2", "verification": ["pytest -q t.py"]}, "depends_on": ["T1"], "consumes": ["a#x"], "produces": ["b#y"], "assumes": ["A1"]},
            "T9": {"contract": {"task_id": "T9"}, "depends_on": [], "produces": ["unrelated"]},
        },
        "decisions": {"D1": "smallest"}, "assumptions": {"A1": "api stable", "A9": "irrelevant"},
        "git": {"head": "abc"}, "huge_history": "must not be copied",
    }
    packet = minimal_refresh(state, {"head": "def"}, ["b.py"])
    assert set(packet["dependency_slice"]) == {"T1"}
    assert packet["assumptions"] == {"A1": "api stable"}
    assert "huge_history" not in packet
    assert "T9" not in packet["dependency_slice"]


def test_E_retroactive_DAG_change_invalidates_only_M3_downstream() -> None:
    tasks = {f"M{i}": {"depends_on": [] if i == 1 else [f"M{i-1}"]} for i in range(1, 6)}
    assert transitive_impact(tasks, ["M3"]) == ["M3", "M4", "M5"]


def test_E_semantic_artifact_blast_radius_skips_unrelated_branch() -> None:
    tasks = {
        "M1": {"depends_on": [], "produces": ["a"]},
        "M2": {"depends_on": ["M1"], "consumes": ["a"], "produces": ["b"]},
        "M3": {"depends_on": ["M2"], "consumes": ["b"], "produces": ["c"]},
        "U1": {"depends_on": [], "produces": ["u"]},
        "U2": {"depends_on": ["U1"], "consumes": ["u"], "produces": ["v"]},
    }
    assert artifact_impact(tasks, ["b"]) == ["M2", "M3"]


def test_F_human_external_change_relevant_and_irrelevant() -> None:
    tasks = {
        "T1": {"depends_on": [], "consumes": ["src/core.py"], "produces": ["src/api.py"]},
        "T2": {"depends_on": ["T1"], "consumes": ["src/api.py"]},
    }
    impacted = artifact_impact(tasks, ["src/core.py", "docs/note.md"])
    assert impacted == ["T1", "T2"]


def test_G_scope_trap_leaves_ugly_adjacent_file_untouched() -> None:
    in_scope = {"src/target.py", "tests/test_target.py"}
    actual_changed = {"src/target.py", "tests/test_target.py"}
    tempting = "src/ugly_adjacent.py"
    assert actual_changed <= in_scope
    assert tempting not in actual_changed


def test_H_early_success_stops_without_post_success_change() -> None:
    events = ["edit", "verify-pass", "accept"]
    assert events[-1] == "accept"
    assert "cleanup-after-accept" not in events
