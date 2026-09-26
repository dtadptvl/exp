# Native Kilo findings (verified 2026-09-26)

Verified against current official Kilo documentation and `Kilo-Org/kilocode` source/release state before implementation.

- Global custom agent Markdown is discovered under `~/.config/kilo/agents/`; project `.kilo/agents/` has higher precedence. Filename becomes agent ID, so this package uses lowercase `prime.md` and `sub.md` and delegates `sub` exactly.
- `mode: primary|subagent|all`, agent `model`, permissions, `hidden`, and optional `steps` are native. This architecture deliberately omits `steps/maxSteps` because lifecycle timeouts are the required anti-stall control.
- `subagent_depth` is a top-level config value; default 1 prevents a child from launching a child. The architecture requires effective value exactly 1.
- Task creates an isolated child session, validates subagent mode, blocks nesting at the configured depth, and can explicitly resolve per-task model/provider/variant. Current Kilo no longer requires the old `experimental.task_model_selection` flag.
- Explicit per-task model selection has precedence needed to force `9router/sub`; Prime requests it on every delegation rather than relying only on remembered per-agent selection or global `subagent_model`.
- Plugins placed in the global `~/.config/kilo/plugin/` directory auto-register without adding a plugin config entry. Hooks include session events and `tool.execute.after`.
- Kilo exposes native session abort with a tree scope that stops a session and descendants. The watchdog uses this rather than inventing process/session machinery.
- Config is deep-merged across supported global/project files; project settings/agent Markdown can override global definitions. Installer therefore never rewrites config and validation detects effective mismatches.
- Built-in agents remain untouched. Prime's own Task permission denies every agent except custom `sub`; unrelated built-ins remain usable when the Human selects them directly.
- Kilo owns conversation/session persistence and compaction. The package uses a separate tiny project state only for orchestration facts that Git/session history do not deterministically provide after context loss.

No official native feature found that provides the brief's exact evidence-based no-progress watchdog for only `sub`, so the single global plugin is the minimal custom layer retained.
