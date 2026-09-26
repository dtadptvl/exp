from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def frontmatter(rel: str) -> str:
    m = re.match(r"---\n(.*?)\n---\n", read(rel), re.S)
    assert m, rel
    return m.group(1)


def test_topology_and_model() -> None:
    p = frontmatter("agents/prime.md")
    s = frontmatter("agents/sub.md")
    assert "mode: primary" in p
    assert '"*": deny' in p and "sub: allow" in p
    assert "mode: subagent" in s and "model: 9router/sub" in s
    assert re.search(r"^\s*task:\s*deny\s*$", s, re.M)
    assert re.search(r"^\s*doom_loop:\s*deny\s*$", s, re.M)


def test_no_step_count_antihang_anywhere_runtime() -> None:
    sub = frontmatter("agents/sub.md")
    assert not re.search(r"^(steps|maxSteps):", sub, re.M)
    plugin = read("plugin/prime-sub-watchdog.js")
    assert "WALL_MS" in plugin and "STALL_MS" in plugin
    assert 'scope: "tree"' in plugin
    assert "tool.execute.after" in plugin
    assert "reasoning" in plugin.lower() and "not" in plugin.lower()


def test_prime_contract_drift_refresh_and_retry_rules() -> None:
    p = read("agents/prime.md")
    for needle in [
        "required | necessary-support | optional | unrelated",
        "minimum sufficient context",
        "same stable failure signature may receive at most one fresh-Sub retry",
        "direct then transitive dependency impact",
        "Stop immediately",
        "Never natural-language poll",
    ]:
        assert needle in p


def test_state_is_minimal_and_semantic_edges_present() -> None:
    s = read("protocol/STATE.md")
    for key in ["depends_on", "produces", "consumes", "verified_by", "assumes"]:
        assert key in s
    for banned in ["raw chats", "chain-of-thought", "duplicate Git history"]:
        assert banned in s


def test_task_contract_has_required_fields_only() -> None:
    text = read("protocol/TASK-CONTRACT.md")
    for field in ["task_id", "objective", "in_scope", "out_of_scope", "acceptance", "hard_constraints", "relevant_files_symbols", "dependencies", "verification", "stop_condition"]:
        assert f'"{field}"' in text


def test_installer_never_edits_kilo_config_and_has_rollback() -> None:
    ps = read("install.ps1")
    lower = ps.lower()
    for forbidden in ["kilo.json", "kilo.jsonc", "add-content", "invoke-restmethod", "invoke-webrequest"]:
        assert forbidden not in lower
    assert "default_agent" in ps and "subagent_depth" in ps
    assert "prime-sub-install.json" in ps
    assert "prime-sub-watchdog.js" in ps
    un = read("uninstall.ps1")
    assert "Preserved modified owned file" in un
    assert "backup_dir" in un


def test_config_guide_minimal_current_settings() -> None:
    g = read("AI-CONFIG-MERGE-GUIDE.md")
    assert '"default_agent": "prime"' in g
    assert '"subagent_depth": 1' in g
    assert "9router/sub" in g
    assert "experimental.task_model_selection" in g and "obsolete" in g.lower()
    assert "steps" in g and "maxSteps" in g


def test_only_one_custom_worker_agent() -> None:
    agents = sorted(p.name for p in (ROOT / "agents").glob("*.md"))
    assert agents == ["prime.md", "sub.md"]
    assert frontmatter("agents/sub.md").count("mode: subagent") == 1


def test_eval_case_counts() -> None:
    prime = [json.loads(x) for x in read("eval/cases/prime.jsonl").splitlines() if x.strip()]
    sub = [json.loads(x) for x in read("eval/cases/sub.jsonl").splitlines() if x.strip()]
    assert 20 <= len(prime) <= 50
    assert len(sub) >= 20
    assert len({x["id"] for x in prime}) == len(prime)
    assert len({x["id"] for x in sub}) == len(sub)
