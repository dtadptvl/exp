import { appendFile, mkdir } from "node:fs/promises"
import path from "node:path"
import { fileURLToPath } from "node:url"

const positive = (name, fallback) => {
  const raw = process.env[name]
  if (!raw) return fallback
  const value = Number(raw)
  return Number.isFinite(value) && value > 0 ? value : fallback
}

// Wall and inactivity are lifecycle limits, not model step/tool/token budgets.
const WALL_MS = positive("PRIME_SUB_WALL_MS", 60 * 60 * 1000)
const STALL_MS = positive("PRIME_SUB_STALL_MS", 15 * 60 * 1000)
const TICK_MS = Math.max(5_000, Math.min(30_000, Math.floor(STALL_MS / 6)))

const server = async ({ client, directory }) => {
  const live = new Map()
  const helper = fileURLToPath(new URL("../prime-sub/prime-state.ps1", import.meta.url))

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
    "shell.env": async (_input, output) => {
      output.env.PRIME_STATE_PS1 = helper
    },
    event: async ({ event }) => {
      const evt = event
      const props = evt.properties ?? {}
      if (evt.type === "session.created") {
        const info = props.info ?? {}
        if (info.agent === "sub" && info.parentID) {
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
      if (evt.type === "session.diff") {
        if (Array.isArray(props.diff) && props.diff.length > 0) mark(props.sessionID)
        return
      }
      if (evt.type === "session.idle" || evt.type === "session.deleted" || evt.type === "session.error") {
        forget(props.sessionID ?? props.info?.id)
      }
    },
    "tool.execute.after": async (input) => {
      // A completed tool call is observable progress. Streamed/reasoning text is intentionally not.
      mark(input.sessionID)
    },
  }
}

export default { id: "prime-sub-watchdog", server }
