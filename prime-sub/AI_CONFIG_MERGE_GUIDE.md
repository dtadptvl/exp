# Human/AI configuration merge (installer does not edit configuration)

Inspect existing `kilo.json` / `kilo.jsonc` and `kilo debug config` **locally**. Never print secrets. Preserve comments in JSONC, existing providers, credentials, MCP, plugins, built-ins and unrelated fields. Back up the file yourself before a minimal edit; do not regenerate the JSONC document. Ensure only these top-level values (if the installed Kilo accepts them):

```jsonc
"default_agent": "prime",
"subagent_depth": 1
```

For the existing `9router` provider only, if its SDK supports stream chunk deadlines, merge `"chunkTimeout": 1800000` into its existing `options`; 1,800,000 ms = 30 minutes **per silent streaming chunk**, not per Sub task. Keep the native `options.timeout` default (300,000 ms for request/first-byte) unless an observed provider request genuinely needs longer; do not set it to `false`. Never replace the whole provider/options object or reveal credentials. Verify effective non-secret values via `kilo debug config` locally. If your Kilo/provider does not support `chunkTimeout`, this setting is not a reliable kill switch; cancel a stalled Task manually. Neither option limits tool execution or a loop of successful requests. No config change is needed if the effective provider already has `chunkTimeout: 1800000`.

`subagent_depth` is requested policy but **not a known schema field in upstream Kilo source at research time**; check with your installed version (`kilo debug config`) whether it is supported. An unknown field cannot enforce the nesting boundary. Native `sub` denies Task; Prime's Task permissions allow only `sub`. `sub.md` owns `model: 9router/sub`; configure that provider/model externally without copying secrets into this package. Do not add `maxSteps`, `steps`, duplicated permission/mode/model fields or blanket changes to built-ins. Some builds may save a selected per-agent model separately; inspect effective `kilo debug agent sub` and actual child Task metadata. Use `kilo run --agent prime --auto` only in trusted repositories: auto-approval is powerful. If config is incompatible, stop rather than replacing it.
