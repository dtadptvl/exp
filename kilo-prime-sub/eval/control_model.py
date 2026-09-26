from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable

TERMINAL = {"done", "failed", "stalled", "blocked", "invalidated"}


def transitive_impact(tasks: dict[str, dict], changed: Iterable[str]) -> list[str]:
    """Return changed tasks plus only tasks transitively depending on them."""
    impacted = set(changed)
    advanced = True
    while advanced:
        advanced = False
        for task_id, task in tasks.items():
            if task_id in impacted:
                continue
            if impacted.intersection(task.get("depends_on", [])):
                impacted.add(task_id)
                advanced = True
    return sorted(impacted)


def artifact_impact(tasks: dict[str, dict], changed_artifacts: Iterable[str]) -> list[str]:
    changed = set(changed_artifacts)
    direct = {
        task_id
        for task_id, task in tasks.items()
        if changed.intersection(task.get("consumes", [])) or changed.intersection(task.get("produces", []))
    }
    return transitive_impact(tasks, direct)


def minimal_refresh(state: dict, current_git: dict, delta: list[str]) -> dict:
    active = state.get("active_task")
    tasks = state.get("tasks", {})
    task = tasks.get(active, {}) if active else {}
    deps = {d: tasks[d] for d in task.get("depends_on", []) if d in tasks}
    return {
        "objective": state.get("objective"),
        "phase": state.get("phase"),
        "active_task": active,
        "active_contract": task.get("contract"),
        "decisions": state.get("decisions", {}),
        "assumptions": {k: v for k, v in state.get("assumptions", {}).items() if k in task.get("assumes", [])},
        "dependency_slice": deps,
        "relevant_refs": task.get("consumes", []) + task.get("produces", []),
        "last_git": state.get("git"),
        "current_git": current_git,
        "delta": delta,
        "verification": task.get("contract", {}).get("verification", []),
    }


@dataclass
class Watch:
    wall_ms: int
    stall_ms: int
    started: int = 0
    progress: int = 0
    killed: bool = False
    reason: str | None = None

    def tool_progress(self, now: int) -> None:
        if not self.killed:
            self.progress = now

    def reasoning_text(self, now: int) -> None:
        # Deliberately no-op: reasoning text is not observable task progress.
        _ = now

    def tick(self, now: int) -> str | None:
        if self.killed:
            return self.reason
        if now - self.started >= self.wall_ms:
            self.killed, self.reason = True, "wall"
        elif now - self.progress >= self.stall_ms:
            self.killed, self.reason = True, "inactivity"
        return self.reason


@dataclass
class RunState:
    status: str = "queued"
    retries_by_signature: dict[str, int] = field(default_factory=dict)

    def start(self) -> None:
        self.status = "running"

    def fail(self, signature: str) -> str:
        self.status = "failed"
        used = self.retries_by_signature.get(signature, 0)
        if used < 1:
            self.retries_by_signature[signature] = used + 1
            return "fresh-sub"
        return "replan-or-prime"

    def accept(self) -> None:
        self.status = "done"
