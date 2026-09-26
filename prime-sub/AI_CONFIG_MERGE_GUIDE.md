# Human/AI configuration merge (installer does not edit configuration)

Inspect existing `kilo.json` / `kilo.jsonc` and `kilo debug config` **locally**. Never print secrets. Preserve comments in JSONC, existing providers, credentials, MCP, plugins, built-ins and unrelated fields. Back up the file yourself before a minimal edit; do not regenerate the JSONC document. Ensure only these top-level values (if the installed Kilo accepts them):

```jsonc
"default_agent": "prime",
"subagent_depth": 1
```

`subagent_depth` is requested policy but **not a known schema field in upstream Kilo source at research time**; check with your installed version (`kilo debug config`) whether it is supported. An unknown field cannot enforce the nesting boundary. Native `sub` denies Task; Prime's Task permissions allow only `sub`. `sub.md` owns `model: 9router/sub`; configure that provider/model externally without copying secrets into this package. Do not add `maxSteps`, `steps`, duplicated permission/mode/model fields or blanket changes to built-ins. Some builds may save a selected per-agent model separately; inspect effective `kilo debug agent sub` and actual child Task metadata. Use `kilo run --agent prime --auto` only in trusted repositories: auto-approval is powerful. If config is incompatible, stop rather than replacing it.
