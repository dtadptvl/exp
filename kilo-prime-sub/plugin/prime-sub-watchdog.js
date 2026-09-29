import { appendFile, mkdir, readFile } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"

const positive = (name, fallback) => {
  const raw = process.env[name]
  if (!raw) return fallback
  const value = Number(raw)
  return Number.isFinite(value) && value > 0 ? value : fallback
}

// Sub lifecycle limits. These are wall/inactivity limits, never model step/token budgets.
const WALL_MS = positive("PRIME_SUB_WALL_MS", 60 * 60 * 1000)
const STALL_MS = positive("PRIME_SUB_STALL_MS", 15 * 60 * 1000)
const TICK_MS = Math.max(5_000, Math.min(30_000, Math.floor(STALL_MS / 6)))

// Prime context is compacted only at an idle boundary. Prompt-side usage deliberately
// ignores output/reasoning because provider accounting can misclassify those buckets.
const PRIME_CONTEXT_SOFT_TOKENS = positive("PRIME_CONTEXT_SOFT_TOKENS", 120_000)
const PRIME_COMPACT_COOLDOWN_MS = positive("PRIME_COMPACT_COOLDOWN_MS", 60_000)

const CONTRACT_FIELDS = [
  "task_id",
  "objective",
  "in_scope",
  "out_of_scope",
  "acceptance",
  "hard_constraints",
  "relevant_files_symbols",
  "dependencies",
  "verification",
  "stop_condition",
]
const CONTRACT_ARRAYS = [
  "in_scope",
  "out_of_scope",
  "acceptance",
  "hard_constraints",
  "relevant_files_symbols",
  "dependencies",
  "verification",
]
const CONTRACT_REQUIRED_ARRAYS = ["in_scope", "acceptance", "relevant_files_symbols", "verification"]
const CONTRACT_MAX_CHARS = 16_000
const CONTRACT_MAX_ITEMS = 12
const CONTRACT_MAX_ITEM_CHARS = 1_200

const plain = (value) => value && typeof value === "object" && !Array.isArray(value)

function contractError(message) {
  throw new Error(
    `PRIME_CONTRACT_INVALID: ${message}. Send one raw JSON object with exactly: ${CONTRACT_FIELDS.join(", ")}`,
  )
}

function cleanString(value, field, max = CONTRACT_MAX_ITEM_CHARS) {
  if (typeof value !== "string") contractError(`${field} must be a string`)
  const text = value.trim()
  if (!text) contractError(`${field} must not be empty`)
  if (text.length > max) contractError(`${field} exceeds ${max} chars`)
  if (/[\r\n]/.test(text)) contractError(`${field} must be single-line; reference files instead of pasting content`)
  return text
}

function parseContract(raw) {
  if (typeof raw !== "string") contractError("prompt must be JSON text")
  if (raw.length > CONTRACT_MAX_CHARS) contractError(`prompt exceeds ${CONTRACT_MAX_CHARS} chars`)
  let value
  try {
    value = JSON.parse(raw)
  } catch {
    contractError("prompt is not valid JSON or has a prose/code-fence wrapper")
  }
  if (!plain(value)) contractError("prompt must decode to an object")

  const keys = Object.keys(value).sort()
  const expected = [...CONTRACT_FIELDS].sort()
  if (keys.length !== expected.length || keys.some((key, i) => key !== expected[i])) {
    contractError("top-level fields do not match the contract schema")
  }

  const result = {
    task_id: cleanString(value.task_id, "task_id", 120),
    objective: cleanString(value.objective, "objective", 1_000),
    stop_condition: cleanString(value.stop_condition, "stop_condition", 500),
  }

  for (const field of CONTRACT_ARRAYS) {
    const items = value[field]
    if (!Array.isArray(items)) contractError(`${field} must be an array`)
    if (items.length > CONTRACT_MAX_ITEMS) contractError(`${field} has more than ${CONTRACT_MAX_ITEMS} items`)
    const normalized = [...new Set(items.map((item, index) => cleanString(item, `${field}[${index}]`)))]
    if (CONTRACT_REQUIRED_ARRAYS.includes(field) && normalized.length === 0) contractError(`${field} must not be empty`)
    result[field] = normalized
  }

  // Canonical key order keeps Sub input compact and makes transcripts easy to diff.
  return Object.fromEntries(CONTRACT_FIELDS.map((field) => [field, result[field]]))
}

function promptTokens(info) {
  const tokens = info?.tokens ?? {}
  const cache = tokens.cache ?? {}
  return Math.max(0, Number(tokens.input) || 0) + Math.max(0, Number(cache.read) || 0) + Math.max(0, Number(cache.write) || 0)
}

function compactAnchor(state) {
  if (!plain(state)) return undefined
  const activeID = typeof state.active_task === "string" ? state.active_task : undefined
  const tasks = plain(state.tasks) ? state.tasks : {}
  const active = activeID && plain(tasks[activeID]) ? tasks[activeID] : undefined
  const depIDs = active && Array.isArray(active.depends_on) ? active.depends_on.filter((x) => typeof x === "string") : []
  const deps = Object.fromEntries(
    depIDs
      .filter((id) => plain(tasks[id]))
      .map((id) => [
        id,
        {
          status: tasks[id].status,
          objective: tasks[id].contract?.objective,
          produces: tasks[id].produces,
          verified_by: tasks[id].verified_by,
        },
      ]),
  )
  const assumptionIDs = active && Array.isArray(active.assumes) ? active.assumes.filter((x) => typeof x === "string") : []
  const assumptions = plain(state.assumptions)
    ? Object.fromEntries(assumptionIDs.filter((id) => Object.hasOwn(state.assumptions, id)).map((id) => [id, state.assumptions[id]]))
    : {}

  return {
    objective: state.objective,
    phase: state.phase,
    active_task: activeID,
    active,
    direct_dependencies: deps,
    assumptions,
    acceptance: state.acceptance,
    invalidated: state.invalidated,
    next: state.next,
    git: state.git,
  }
}

const server = async ({ client, directory }) => {
  const live = new Map()
  const sessions = new Map()
  const helper = fileURLToPath(new URL("../prime-sub/prime-state.ps1", import.meta.url))

  const remember = (sessionID, patch = {}) => {
    if (!sessionID) return undefined
    const item = sessions.get(sessionID) ?? {
      sessionID,
      agent: undefined,
      directory,
      model: undefined,
      promptTokens: 0,
      compacting: false,
      lastCompact: 0,
    }
    Object.assign(item, patch)
    sessions.set(sessionID, item)
    return item
  }

  const mark = (sessionID) => {
    if (!sessionID) return
    const item = live.get(sessionID)
    if (item && !item.aborting) item.progress = Date.now()
  }

  const forget = (sessionID) => {
    if (sessionID) live.delete(sessionID)
  }

  const record = async (item, reason) => {
    const dir = path.join(item.directory, ".prime")
    await mkdir(dir, { recursive: true })
    const line = JSON.stringify({
      at: new Date().toISOString(),
      session_id: item.sessionID,
      parent_id: item.parentID,
      state: "STALLED",
      reason,
      wall_ms: Date.now() - item.started,
      inactivity_ms: Date.now() - item.progress,
    }) + "\n"
    await appendFile(path.join(dir, "stall-events.jsonl"), line, "utf8")
  }

  const abort = async (item, reason) => {
    if (item.aborting) return
    item.aborting = true
    try {
      await record(item, reason)
      await client.session.abort(
        { sessionID: item.sessionID, directory: item.directory, scope: "tree" },
        { throwOnError: true },
      )
    } catch (error) {
      try {
        const dir = path.join(item.directory, ".prime")
        await mkdir(dir, { recursive: true })
        await appendFile(
          path.join(dir, "stall-events.jsonl"),
          JSON.stringify({
            at: new Date().toISOString(),
            session_id: item.sessionID,
            parent_id: item.parentID,
            state: "STALL_ABORT_FAILED",
            reason,
            error: String(error),
          }) + "\n",
          "utf8",
        )
      } catch {}
    } finally {
      live.delete(item.sessionID)
    }
  }

  const stateAnchor = async (item) => {
    try {
      const raw = await readFile(path.join(item.directory, ".prime", "state.json"), "utf8")
      const anchor = compactAnchor(JSON.parse(raw))
      return anchor ? JSON.stringify(anchor) : undefined
    } catch {
      return undefined
    }
  }

  const compactPrime = async (item) => {
    if (item.agent !== "prime" || item.compacting) return
    if (item.promptTokens < PRIME_CONTEXT_SOFT_TOKENS) return
    if (!item.model?.providerID || !item.model?.modelID) return
    if (Date.now() - item.lastCompact < PRIME_COMPACT_COOLDOWN_MS) return

    item.compacting = true
    try {
      await client.session.summarize(
        {
          sessionID: item.sessionID,
          directory: item.directory,
          providerID: item.model.providerID,
          modelID: item.model.modelID,
          auto: false,
        },
        { throwOnError: true },
      )
      item.promptTokens = 0
      item.lastCompact = Date.now()
    } catch {
      // Native compaction failure is non-destructive. Kilo can still compact on its own limit;
      // the next idle boundary may retry after the cooldown.
      item.lastCompact = Date.now()
    } finally {
      item.compacting = false
    }
  }

  const timer = setInterval(() => {
    const now = Date.now()
    for (const item of live.values()) {
      if (item.aborting) continue
      if (now - item.started >= WALL_MS) {
        void abort(item, "wall")
        continue
      }
      if (now - item.progress >= STALL_MS) void abort(item, "inactivity")
    }
  }, TICK_MS)
  timer.unref?.()

  return {
    dispose: async () => clearInterval(timer),

    "chat.message": async (input) => {
      remember(input.sessionID, {
        agent: input.agent,
        model: input.model,
      })
    },

    "shell.env": async (_input, output) => {
      output.env.PRIME_STATE_PS1 = helper
    },

    "tool.execute.before": async (input, output) => {
      const session = sessions.get(input.sessionID)
      if (session?.agent !== "prime" || input.tool !== "task") return

      if (output.args?.subagent_type !== "sub") {
        throw new Error("PRIME_DELEGATION_INVALID: Prime may delegate only to sub")
      }

      const contract = parseContract(output.args?.prompt)
      output.args.prompt = JSON.stringify(contract)

      // Routing is architecture-owned. Normalizing here avoids wasting a model retry
      // when Prime omitted the otherwise redundant model field.
      output.args.model = "9router/sub"
      delete output.args.provider
    },

    "tool.execute.after": async (input) => {
      // A completed Sub tool call is observable progress. Streamed/reasoning text is intentionally not.
      mark(input.sessionID)
    },

    "experimental.session.compacting": async (input, output) => {
      const item = sessions.get(input.sessionID)
      if (item?.agent !== "prime") return
      const anchor = await stateAnchor(item)
      output.prompt = [
        "Compact the persistent Prime controller into a small operational checkpoint.",
        "The external state anchor and Git are authoritative. Preserve only information needed to continue that is NOT already recoverable from them:",
        "- current Human constraints or corrections newer than the anchor;",
        "- unresolved decisions, assumptions, blockers, acceptance gaps, and pending verification;",
        "- active task status, changed paths that still matter, and the immediate next action.",
        "Drop completed Sub transcripts, old tool outputs, code excerpts, superseded plans, repeated rationale, and anything already represented by state/Git.",
        "Do not invent facts. If conversation conflicts with the anchor, preserve the conflict explicitly.",
        "Keep the checkpoint concise; prefer IDs, paths, symbols, and exact commands over prose.",
        anchor ? `STATE_ANCHOR:\n${anchor}` : "STATE_ANCHOR: unavailable; preserve the minimum required continuation facts.",
      ].join("\n")
    },

    event: async ({ event }) => {
      const evt = event
      const props = evt.properties ?? {}

      if (evt.type === "session.created" || evt.type === "session.updated") {
        const info = props.info ?? {}
        const item = remember(props.sessionID ?? info.id, {
          agent: info.agent,
          directory: info.directory ?? directory,
          model: info.model
            ? { providerID: info.model.providerID, modelID: info.model.id ?? info.model.modelID }
            : undefined,
        })

        if (evt.type === "session.created" && info.agent === "sub" && info.parentID) {
          const now = Date.now()
          live.set(info.id, {
            sessionID: info.id,
            parentID: info.parentID,
            directory: info.directory ?? directory,
            started: now,
            progress: now,
            aborting: false,
          })
        }
        return
      }

      if (evt.type === "message.updated") {
        const info = props.info ?? {}
        if (info.role !== "assistant") return
        const item = remember(props.sessionID ?? info.sessionID, {
          agent: info.agent,
          model:
            info.providerID && info.modelID ? { providerID: info.providerID, modelID: info.modelID } : undefined,
        })
        if (item?.agent === "prime") item.promptTokens = promptTokens(info)
        return
      }

      if (evt.type === "session.compacted") {
        const item = sessions.get(props.sessionID)
        if (item) {
          item.promptTokens = 0
          item.lastCompact = Date.now()
        }
        return
      }

      if (evt.type === "session.diff") {
        if (Array.isArray(props.diff) && props.diff.length > 0) mark(props.sessionID)
        return
      }

      if (evt.type === "session.idle") {
        forget(props.sessionID)
        const item = sessions.get(props.sessionID)
        if (item?.agent === "prime") void compactPrime(item)
        return
      }

      if (evt.type === "session.deleted") {
        const id = props.sessionID ?? props.info?.id
        forget(id)
        sessions.delete(id)
      }
    },
  }
}

export default { id: "prime-sub-watchdog", server }
