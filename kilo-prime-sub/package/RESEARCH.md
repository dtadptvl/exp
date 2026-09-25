# Research report

Research date: 2026-09-25.

This report separates native Kilo facts, attached-reference analysis, external findings, derived requirements, and unresolved evidence gaps. The implementation is intentionally conservative where live benchmark evidence is unavailable.

## 1. Native Kilo facts

### Agent discovery and precedence

Official Kilo documentation says custom agents can be Markdown files. Global agents live under `~/.config/kilo/agents/`; project agents live under `.kilo/agents/`; the filename becomes the agent name. Project agent Markdown has higher precedence than global agent Markdown. Custom subagents can be `primary`, `subagent`, or `all` mode.

Sources:
- https://kilo.ai/docs/customize/custom-subagents
- `Kilo-Org/kilocode`, `packages/core/src/config/plugin/agent.ts`

### Subagent sessions are isolated by default

The Task tool creates a child session with `parentID` when `task_id` is absent. Kilo's Task prompt states that each agent invocation starts with fresh context unless `task_id` is supplied; providing `task_id` resumes the same child session with previous messages/tool outputs. A child result is returned to the parent. A failed child exposes a resumable task ID.

For this architecture, fresh context is native. The optimized policy deliberately does not resume `task_id` because the required Sub lifecycle is disposable/task-scoped and fresh replacement simplifies stale-context recovery.

Sources:
- `packages/opencode/src/tool/task.ts`
- `packages/opencode/src/tool/task.txt`
- https://kilo.ai/docs/customize/custom-subagents

### Depth control is native

`subagent_depth` is enforced by walking parent session ancestry. Kilo's config schema documents a default of 1. At depth 1, a child cannot create another task child. The optimized design still sets `subagent_depth: 1` explicitly because it is a required invariant, not because the default should be assumed forever.

Sources:
- `packages/opencode/src/tool/task.ts`
- `packages/core/src/v1/config/config.ts`

### Task permissions can enforce Prime -> Sub only

Kilo agent permissions support ordered allow/ask/deny rules. `permission.task` can deny all subagents and allow one named subagent. The implementation uses `"*": deny` followed by `sub: allow` in Prime. Sub has Task denied.

Sources:
- https://kilo.ai/docs/customize/agent-permissions
- https://kilo.ai/docs/customize/custom-subagents

### Tool restrictions and permission ceilings propagate

Current Kilo code derives child-session permissions from the selected subagent plus parent/session restrictions. Kilo intentionally preserves hard parent mutation/MCP denials while allowing the selected custom subagent's own Bash policy to govern normal commands. The child Task prompt also disables direct user questions and disables Task when depth does not allow further nesting.

Sources:
- `packages/opencode/src/kilocode/tool/task.ts`
- `packages/opencode/src/tool/task.ts`

### Model pinning has a stable-version compatibility trap

On stable `v7.7.9`, Task model selection is guarded by `experimental.task_model_selection=true`. The CLI also stores the last selected model per agent; in `v7.7.9` that saved state is considered before the agent's `model:` field. Therefore `model: 9router/sub` in `sub.md` alone is not a hard guarantee.

The architecture requires Prime to explicitly request `9router/sub` on every Task call. On stable `v7.7.9`, this additionally requires `experimental.task_model_selection: true`.

Current main/pre-release code removed the experimental gate and enables per-task model selection by default. Release notes for v7.7.12 pre-release explicitly include PR #14533 and document this change. The config guide therefore distinguishes the known stable v7.7.9 behavior from builds containing #14533 instead of assuming a semver threshold beyond the evidence.

Sources:
- tag `v7.7.9`: `packages/opencode/src/kilocode/tool/task.ts`, `packages/opencode/src/tool/task.ts`
- current main: same paths
- https://kilo.ai/docs/code-with-ai/agents/model-selection
- https://github.com/Kilo-Org/kilocode/releases

### Native repeated-failure detection exists

Kilo session processing contains `DOOM_LOOP_THRESHOLD = 3`. `doom_loop` permission controls whether an agent may continue after a repeated failure cycle. Setting Sub `doom_loop: deny` gives a deterministic fail-fast boundary for this failure class.

This does not detect every semantic no-progress loop, so the prompt separately defines progress as new observable evidence.

Sources:
- `packages/opencode/src/session/processor.ts`
- `packages/core/src/v1/config/permission.ts`

### Provider and command timeouts are native, but no universal healthy stream timeout should be assumed

Kilo supports request/first-byte timeout and optional SSE `chunkTimeout`. Current source explicitly reverted a universal stream-idle heuristic because silence could be healthy reasoning/buffering rather than a dead stream. Unconfigured `chunkTimeout` can therefore leave a silently stalled provider stream open indefinitely.

The architecture requires a finite positive `9router.options.chunkTimeout`, but does not claim one universal millisecond value is proven optimal. The config guide gives a conservative bootstrap example and requires tuning from observed provider behavior.

Shell commands have a native configurable timeout and terminate with an explicit timeout failure.

Sources:
- `packages/opencode/src/kilocode/session/llm.ts`
- `packages/opencode/src/provider/provider.ts`
- `packages/opencode/src/kilocode/provider/provider.ts`
- `.github/docs-sync/selftest.mjs` commentary for revert #12497
- https://kilo.ai/docs/code-with-ai/agents/custom-models
- `packages/opencode/src/tool/shell.ts`

### Task cancellation is native

The Task runtime makes child work interruptible and cancels foreground child work when the parent Task scope is interrupted. Background Task support also has native lifecycle handling. No custom cancellation daemon is needed for the initial design.

Source: `packages/opencode/src/kilocode/tool/task.ts`.

### Compaction/session persistence is native, but project orchestration semantics are not

Kilo persists sessions and supports compaction/resume behavior. That does not by itself encode the project's objective revision, task dependency graph, which assumptions became stale after human edits, or which evidence remains valid. Those are the narrow reasons for `.prime/state.json`.

Sources:
- Kilo config/session source and docs
- `packages/core/src/v1/config/config.ts`

## 2. Attached ZIP analysis

Reference: `prime-sub-minimal-adaptive-20260919-compact.zip`.

### Purpose

The ZIP implements a deliberately small native-first Prime/Sub policy with global `prime.md`, `sub.md`, one `.prime/state.json`, a Windows installer, config guide, and static tests.

### Useful concepts retained

- Prime-only ownership of global intent, acceptance, recovery, and Git integration.
- Sub owns bounded inspect/edit/test/fix work.
- Explicit Prime -> Sub Task permission boundary.
- Sub is denied first-party read/edit access to `.prime/state.json`; the task contract is its intended context boundary.
- `9router/sub` pinning and explicit Task model override.
- Compact project-local orchestration state rather than a custom database.
- `doom_loop: deny`, provider `chunkTimeout`, native tool timeouts, and read-only Git access for Sub.
- Deterministic evidence before Prime rereads implementation.
- No custom scheduler, session database, worktree manager, or background daemon.

### Invalid, outdated, or insufficiently proven parts

1. The ZIP treats a finite `steps` value as one of the main native stall fuses. The new master requirement forbids generic step counts as the primary stall control. The optimized version keeps a high `steps` ceiling only as an emergency circuit breaker and explicitly forbids using it as progress/retry/completion policy.
2. The ZIP's config guide assumes `experimental.task_model_selection` must always be enabled. That is true for stable `v7.7.9`, but newer Kilo code removed the flag and enables per-task selection by default.
3. The old state shape does not explicitly encode a small dependency graph, artifact references, active assumptions, and evidence validity needed for selective retroactive invalidation.
4. The old package allows background work when scopes appear safe. The new implementation stays sequential because a single shared working tree plus one write-capable custom Sub makes serialization the simplest supported way to avoid concurrent mutation and stale intermediate assumptions.
5. The old nine tests are static policy/content checks. They passed locally, but they do not establish near-Prime code quality, token reduction, recovery success, or latency. They are baseline validation, not benchmark evidence.
6. The old package has backup-on-install but no explicit uninstall/rollback command.

### Parts rejected

- Per-agent worktrees.
- A custom task scheduler/queue.
- A database or journal for live orchestration.
- Prime conversational polling of Sub.
- Full Prime code review after every Sub task.
- Full repository rescan after every prompt.
- Fixed total retry count.

## 3. External findings

### Bounded modular work reduces trajectory/context inflation

MASAI decomposes software engineering work into subagents with well-defined objectives and reports that modularity can avoid unnecessarily long trajectories and extraneous context. This supports bounded deliverables and explicit contracts, not copying MASAI's personas or harness.

Source: https://arxiv.org/abs/2406.11638

### Independent subagent context is a useful manager-worker primitive

Current multi-agent systems commonly give delegated subagents independent context and ask the main agent to coordinate results. OpenAI's current multi-agent guide explicitly recommends clear questions/expected results and warns that agents editing the same files must coordinate changes. That supports isolated fresh workers plus a single-writer rule in this shared-worktree design.

Source: https://developers.openai.com/api/docs/guides/agents-api/multi-agent

### Long-running agents benefit from a harness that manages context, tools, subagents, and intermediate state

OpenAI's Agents API launch describes reliable long-running agents as needing context management, efficient tool use, subagent coordination, and saved intermediate results. This supports keeping orchestration state outside the model when it must survive context loss. It does not imply Kilo needs another full harness because Kilo already provides most runtime primitives.

Source: https://openai.com/index/introducing-the-agents-api/

### Prompt changes should be trajectory/eval driven

GEPA optimizes prompts by examining trajectories, diagnosing failures, proposing prompt updates, and retaining changes that improve measured outcomes. This supports failure-driven `sub.md` optimization instead of adding plausible rules by intuition.

Source: https://arxiv.org/abs/2507.19457

### Deliverable-centered orchestration can be simpler than micromanaging sessions

OpenAI's Symphony write-up argues for organizing agent orchestration around tasks/deliverables rather than constant human session supervision. The relevant principle here is deliverable-centered contracts and autonomous execution. Symphony's own infrastructure is not copied.

Source: https://openai.com/index/open-source-codex-orchestration-symphony/

## 4. Requirements derived from evidence

1. Use native Kilo Task sessions for context isolation and result delivery.
2. Use exactly global `prime` and custom `sub`; preserve built-ins.
3. Set `default_agent: prime` and `subagent_depth: 1` in effective human-owned config.
4. Prime explicitly selects `9router/sub` on every Task. Stable `v7.7.9` additionally requires the model-selection experimental flag; newer builds do not.
5. Serialize all Sub invocations in the shared working tree.
6. Never resume Sub task sessions in this architecture; recovery uses fresh context and compact evidence.
7. Keep `.prime/state.json` minimal but sufficient for objective revision, task DAG, assumptions, evidence validity, reconciliation, and selective invalidation.
8. Use externally observable verification and risk-triggered Prime review rather than trusting `DONE` or always rereading full diffs.
9. Use native doom-loop detection, provider/shell timeouts, and evidence-based progress. A high `steps` value is an emergency circuit breaker only.
10. Preserve human/unrelated dirty work and make repository evidence override stale state.
11. Evaluate Prime-only, reference Prime/Sub, and optimized Prime/Sub on the same cases before claiming success.

## 5. Design decisions

### Sequential fresh Sub instead of background fan-out

Problem: one shared working tree and one write-capable Sub type make concurrent mutation risky.

Alternatives considered: background Sub with scope conventions; custom queue/lock; per-agent worktrees; sequential foreground Task.

Selected: sequential foreground Task. It is natively supported, has no new runtime component, and removes writer races and stale intermediate-state coordination. Parallel read-only work may be reconsidered only after measured benefit and an enforceable read-only surface justify it.

### Minimal JSON state instead of database/journal

Problem: Prime must survive compaction/restart and selectively invalidate stale downstream work.

Selected: one small `.prime/state.json` because Git already stores source/history. The state stores only semantic orchestration metadata Git cannot cheaply derive.

### Fresh replacement instead of task resume

Problem: recovery after a weak Sub trajectory risks carrying bad local assumptions and excess context.

Selected: new Task session with minimum recovery evidence. Kilo natively starts fresh when `task_id` is omitted.

### Native stall controls plus an emergency step ceiling

Problem: Kilo has repeated-failure detection, cancellation, provider/tool timeouts, but current evidence did not identify a supported per-Task absolute wall-clock deadline. A semantic loop with successful tool calls could still run too long.

Selected initial mechanism: `doom_loop: deny`, finite provider/tool timeouts, evidence-based fail-fast prompt behavior, and a high native `steps` ceiling only as a last-resort circuit breaker. No custom watchdog is admitted yet because the live failure frequency and required deadline distribution have not been measured.

Evaluation must decide whether the step ceiling can be removed or whether a true per-Task deadline mechanism is justified.

## 6. Unknowns and live-evaluation gaps

The current execution environment used to build this package does not contain a `kilo` executable and does not expose the user's `9router/sub` credentials. Therefore the following claims are deliberately not made:

- no measured quality gap versus Prime-only;
- no measured Prime-token reduction;
- no measured Sub-token or latency overhead;
- no empirical optimum for `steps` or `chunkTimeout`;
- no proof yet that the optimized prompt beats the attached reference baseline on the 20-case eval set.

The repository contains a runnable benchmark harness and records this state as `NOT_RUN`, rather than inventing numbers. Static package tests were run locally and are reported separately.
