# AI config merge guide

The installer never edits `kilo.json` or `kilo.jsonc`. A chatbot/AI applying configuration must first inspect the user's existing effective config and preserve unrelated fields, comments, secrets, credentials, provider definitions, MCP servers, plugins, built-ins, permissions, and custom agents. Never print secrets. Preserve JSONC comments and make the smallest delta only.

Required effective settings:

```jsonc
{
  "default_agent": "prime",
  "subagent_depth": 1
}
```

Also verify that existing provider configuration exposes `9router/sub`. Do not duplicate Prime/Sub prompt, mode, model, or permission settings into config; the installed global agent Markdown owns those fields. Do not add `steps`, `maxSteps`, or any step-count anti-hang setting. Do not add the removed/obsolete `experimental.task_model_selection` requirement: current Kilo exposes per-task model selection directly, and Prime explicitly requests `9router/sub` for every delegation.

If a project contains `.kilo/agents/prime.md` or `.kilo/agents/sub.md`, project agent Markdown has higher precedence than the global installation. Reconcile that override deliberately rather than overwriting it silently.

Safe procedure:

1. Inspect all relevant existing Kilo config files and effective config.
2. Confirm `9router/sub` exists and is usable with the user's existing credentials/provider definition.
3. Merge only `default_agent: "prime"` and `subagent_depth: 1` where needed.
4. Preserve comments/secrets/unrelated settings exactly.
5. Run `kilo debug config`, `kilo debug agent prime`, and `kilo debug agent sub`.
6. Confirm Prime is primary, Sub is subagent on `9router/sub`, Prime can Task only `sub`, Sub cannot Task, and no `steps/maxSteps` anti-stall field is active for Sub.
