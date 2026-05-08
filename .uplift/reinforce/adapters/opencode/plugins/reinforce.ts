import { spawn } from "node:child_process"
import { existsSync } from "node:fs"
import { appendFile, mkdir, readdir, readFile, stat } from "node:fs/promises"
import path from "node:path"

const SERVICE = "uplift.reinforce.opencode"
const PREFIX_TEMPLATE = ".uplift"
const INSTALL_PREFIX = PREFIX_TEMPLATE.startsWith("__") ? ".uplift" : PREFIX_TEMPLATE
const DEFAULT_MAX_TRANSCRIPT_BYTES = 1024 * 1024
const CAPTURE_TYPES = new Set([
  "session.created",
  "session.updated",
  "session.deleted",
  "session.status",
  "session.error",
  "session.diff",
  "message.updated",
  "message.part.updated",
  "message.part.removed",
  "command.executed",
])

function truthy(value) {
  return /^(1|true|yes)$/i.test(String(value ?? ""))
}

function numberValue(value, fallback) {
  const parsed = Number.parseInt(String(value ?? ""), 10)
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback
}

async function readConfig(reinforceRoot) {
  const config = {
    disabled: false,
    reminderThreshold: 5,
    idleReflectSec: 0,
    transcriptMaxBytes: DEFAULT_MAX_TRANSCRIPT_BYTES,
    bash: process.env.REINFORCE_BASH || "",
  }

  try {
    const text = await readFile(path.join(reinforceRoot, "config"), "utf8")
    for (const rawLine of text.split(/\r?\n/)) {
      const line = rawLine.trim()
      if (!line || line.startsWith("#")) continue
      const index = line.indexOf("=")
      if (index < 0) continue
      const key = line.slice(0, index).trim()
      const value = line.slice(index + 1).trim()
      if (key === "disabled") config.disabled = truthy(value)
      if (key === "reminder_threshold") config.reminderThreshold = numberValue(value, config.reminderThreshold)
      if (key === "opencode_idle_reflect_sec") config.idleReflectSec = numberValue(value, config.idleReflectSec)
      if (key === "opencode_transcript_max_bytes") config.transcriptMaxBytes = numberValue(value, config.transcriptMaxBytes)
    }
  } catch {
    // Missing config should not break OpenCode startup.
  }

  if (truthy(process.env.REINFORCE_DISABLED)) config.disabled = true
  if (process.env.REINFORCE_REMINDER_THRESHOLD) {
    config.reminderThreshold = numberValue(process.env.REINFORCE_REMINDER_THRESHOLD, config.reminderThreshold)
  }
  if (process.env.REINFORCE_OPENCODE_IDLE_REFLECT_SEC) {
    config.idleReflectSec = numberValue(process.env.REINFORCE_OPENCODE_IDLE_REFLECT_SEC, config.idleReflectSec)
  }
  if (process.env.REINFORCE_OPENCODE_TRANSCRIPT_MAX_BYTES) {
    config.transcriptMaxBytes = numberValue(process.env.REINFORCE_OPENCODE_TRANSCRIPT_MAX_BYTES, config.transcriptMaxBytes)
  }

  return config
}

function limitString(value, max = 8000) {
  const text = String(value ?? "")
  if (text.length <= max) return text
  return `${text.slice(0, max)}\n[reinforce: truncated ${text.length - max} chars]`
}

function sanitize(value, depth = 0) {
  if (depth > 4) return "[reinforce: max depth]"
  if (value === null || value === undefined) return value
  if (typeof value === "string") return limitString(value)
  if (typeof value === "number" || typeof value === "boolean") return value
  if (Array.isArray(value)) return value.slice(0, 50).map((item) => sanitize(item, depth + 1))
  if (typeof value === "object") {
    const out = {}
    for (const [key, nested] of Object.entries(value).slice(0, 80)) {
      out[key] = sanitize(nested, depth + 1)
    }
    return out
  }
  return String(value)
}

function sessionIDFrom(event) {
  const properties = event?.properties ?? {}
  return properties.sessionID || properties.info?.id || properties.info?.sessionID || properties.session?.id || ""
}

function safeSessionID(sessionID) {
  return String(sessionID).replace(/[\\/:]/g, "_")
}

function shouldCapture(type) {
  return CAPTURE_TYPES.has(type) || type.startsWith("session.next.")
}

function resolveBash(config) {
  if (config.bash) return config.bash
  if (process.platform === "win32") {
    const candidates = [
      "C:/Program Files/Git/bin/bash.exe",
      "C:/Program Files/Git/usr/bin/bash.exe",
      `${process.env.LOCALAPPDATA || ""}/Programs/Git/bin/bash.exe`,
    ].filter(Boolean)
    for (const candidate of candidates) {
      if (existsSync(candidate)) return candidate
    }
  }
  return "bash"
}

export default {
  id: "uplift.reinforce",
  server: async ({ client, directory, worktree }) => {
    const projectRoot = worktree || directory || process.cwd()
    const reinforceRoot = path.join(projectRoot, INSTALL_PREFIX, "reinforce")
    const transcriptsDir = path.join(reinforceRoot, "opencode", "transcripts")
    const reflectionsDir = path.join(reinforceRoot, "reflections")
    const activeSessions = new Set()
    const reflectedSessions = new Set()
    const remindedSessions = new Set()
    const truncatedSessions = new Set()
    const idleTimers = new Map()
    let reminderMessage = ""
    let cachedConfig = await readConfig(reinforceRoot)

    async function log(level, message, extra = {}) {
      try {
        await client.app.log({ body: { service: SERVICE, level, message, extra } })
      } catch {
        // Logging must never break the user's OpenCode session.
      }
    }

    async function refreshReminder() {
      const config = await readConfig(reinforceRoot)
      cachedConfig = config
      if (config.disabled) {
        reminderMessage = ""
        return
      }
      try {
        const files = await readdir(reflectionsDir)
        const count = files.filter((name) => name.endsWith(".md")).length
        reminderMessage = count >= config.reminderThreshold
          ? `[reinforce] ${count} reflections accumulated in ${reflectionsDir}/. Recommend running $reinforce to process them.`
          : ""
      } catch {
        reminderMessage = ""
      }
    }

    function transcriptPath(sessionID) {
      return path.join(transcriptsDir, `${safeSessionID(sessionID)}.jsonl`)
    }

    async function appendTranscript(sessionID, event) {
      const config = await readConfig(reinforceRoot)
      cachedConfig = config
      if (config.disabled) return

      const file = transcriptPath(sessionID)
      await mkdir(path.dirname(file), { recursive: true })

      const current = await stat(file).catch(() => null)
      if (current && current.size >= config.transcriptMaxBytes) {
        if (truncatedSessions.has(sessionID)) return
        truncatedSessions.add(sessionID)
        const marker = {
          time: new Date().toISOString(),
          type: "reinforce.transcript.truncated",
          properties: { maxBytes: config.transcriptMaxBytes },
        }
        await appendFile(file, `${JSON.stringify(marker)}\n`, "utf8")
        return
      }

      const record = {
        time: new Date().toISOString(),
        type: event.type,
        properties: sanitize(event.properties ?? {}),
      }
      await appendFile(file, `${JSON.stringify(record)}\n`, "utf8")
    }

    function runReflection(sessionID, reason) {
      if (!sessionID || reflectedSessions.has(sessionID)) return
      const config = cachedConfig
      if (config.disabled) return

      const file = transcriptPath(sessionID)
      if (!existsSync(file)) return

      reflectedSessions.add(sessionID)
      const script = path.join(reinforceRoot, "core", "cmd", "session-reflect-opencode.sh")
      const bash = resolveBash(config)
      const child = spawn(bash, [script, "--session-id", sessionID, "--transcript-path", file, "--reinforce-root", reinforceRoot], {
        cwd: projectRoot,
        detached: true,
        stdio: "ignore",
        env: { ...process.env, REINFORCE_OPENCODE_TRIGGER_REASON: reason },
      })
      child.unref()
      void log("info", "reflection scheduled", { sessionID, reason, bash })
    }

    async function scheduleIdleReflection(sessionID) {
      const config = await readConfig(reinforceRoot)
      cachedConfig = config
      if (config.disabled || config.idleReflectSec <= 0) return
      clearIdleTimer(sessionID)
      const timer = setTimeout(() => {
        idleTimers.delete(sessionID)
        void runReflection(sessionID, "idle")
      }, config.idleReflectSec * 1000)
      if (typeof timer.unref === "function") timer.unref()
      idleTimers.set(sessionID, timer)
    }

    function clearIdleTimer(sessionID) {
      const timer = idleTimers.get(sessionID)
      if (timer) clearTimeout(timer)
      idleTimers.delete(sessionID)
    }

    await mkdir(transcriptsDir, { recursive: true }).catch(() => {})
    void refreshReminder()
    await log("info", "loaded", { projectRoot, reinforceRoot })

    return {
      event: async ({ event }) => {
        const type = event?.type || ""
        const sessionID = sessionIDFrom(event)

        try {
          if (type === "server.instance.disposed") {
            for (const activeSessionID of activeSessions) {
              clearIdleTimer(activeSessionID)
              void runReflection(activeSessionID, "server-disposed")
            }
            return
          }

          if (!sessionID) return
          activeSessions.add(sessionID)

          if (shouldCapture(type)) {
            await appendTranscript(sessionID, event)
          }

          if (type === "session.status") {
            const status = event.properties?.status?.type
            if (status === "idle") void scheduleIdleReflection(sessionID)
            if (status === "busy" || status === "retry") clearIdleTimer(sessionID)
          }

          if (type === "session.deleted") {
            clearIdleTimer(sessionID)
            void runReflection(sessionID, "session-deleted")
          }
        } catch (error) {
          await log("warn", "event handling failed", { type, sessionID, error: String(error) })
        }
      },

      "experimental.chat.system.transform": async (input, output) => {
        try {
          const sessionID = input?.sessionID || ""
          if (!reminderMessage) await refreshReminder()
          if (!reminderMessage) return
          if (sessionID && remindedSessions.has(sessionID)) return
          if (sessionID) remindedSessions.add(sessionID)
          output.system.push(`${reminderMessage}\nIf the user asks to process retros, suggest $reinforce.`)
        } catch (error) {
          await log("warn", "reminder injection failed", { error: String(error) })
        }
      },
    }
  },
}
