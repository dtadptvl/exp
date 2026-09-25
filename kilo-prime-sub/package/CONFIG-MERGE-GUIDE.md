# AI chatbot config merge guide

The installer never edits `kilo.json` or `kilo.jsonc`. Merge only the fields your existing configuration needs. Preserve comments, providers, credentials, MCP, plugins, unrelated permissions, and unrelated settings.

## Required effective settings

```jsonc
{
  "default_agent": "prime",
  "subagent_depth": 1,

  "provider": {
    "9router": {
      // Keep your existing provider definition and credentials.
      "options": {
        // Must be positive and finite. This is a conservative bootstrap example,
        // not a measured universal optimum. Tune from observed healthy stream gaps.
        "chunkTimeout": 1800000
      }
    }
  }
}
```

`provider.9router` must expose model ID `sub`, so `9router/sub` is resolvable.

Do not set `provider.9router.options.timeout` to `false`. If you already set a numeric request/first-byte timeout, keep it positive and finite. If omitted, retain Kilo/provider defaults rather than inventing another override.

Do not set `subagent_model` for this architecture. Prime explicitly requests `9router/sub` on every Task because a saved per-agent CLI model can outrank the agent's static model default in stable Kilo.

## Per-task model-selection compatibility

### Stable Kilo v7.7.9 and older builds with the gate

Add/merge:

```jsonc
{
  "experimental": {
    "task_model_selection": true
  }
}
```

This is required so Prime can explicitly force `9router/sub` for each Task.

### Builds containing PR #14533 (including v7.7.12 pre-release)

Do not add `experimental.task_model_selection` only for this architecture. Those builds enable per-task model selection by default and remove the experimental flag.

If your installed version is between these known behaviors, check its generated schema or `kilo debug config` and follow that build's documented support. The installer performs a version-aware validation for the known stable/new behavior.

## Fields that should not be changed

- Do not disable or replace built-in agents.
- Do not duplicate Prime/Sub prompts inside JSON config.
- Do not globally deny tools that unrelated Kilo agents need.
- Do not remove provider credentials, MCP servers, plugins, or comments.
- Do not enable multi-worktree orchestration for Prime/Sub.

## Validation commands

After merging config and installing the agents:

```powershell
kilo --version
kilo debug config
kilo debug agent prime
kilo debug agent sub
kilo agent list
```

Expected invariants:

- default primary agent resolves to `prime`;
- `subagent_depth` resolves to `1`;
- Prime can Task only `sub`;
- Sub mode is `subagent` and configured model is `9router/sub`;
- Sub cannot invoke Task;
- Sub `doom_loop` resolves to deny;
- Sub Git mutation commands are denied while read-only inspection commands are allowed;
- `9router` has a finite positive `chunkTimeout`;
- stable gated Kilo has `experimental.task_model_selection=true`.
