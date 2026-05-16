import path from "node:path"
import { readFile } from "node:fs/promises"

export interface ReinforceConfig {
  disabled: boolean
  reminderThreshold: number
  opencodeReflectCommand: string
  opencodeReflectModel: string
  opencodeReflectTimeoutSec: number
  opencodeIdleReflectSec: number
  opencodeTranscriptMaxBytes: number
  nodeCommand: string
}

export const DEFAULT_CONFIG: ReinforceConfig = {
  disabled: false,
  reminderThreshold: 5,
  opencodeReflectCommand: "",
  opencodeReflectModel: "",
  opencodeReflectTimeoutSec: 240,
  opencodeIdleReflectSec: 0,
  opencodeTranscriptMaxBytes: 1024 * 1024,
  nodeCommand: "node",
}

type ConfigValues = Record<string, string>
type Env = Record<string, string | undefined>

export function truthy(value: unknown): boolean {
  return /^(1|true|yes)$/i.test(String(value ?? ""))
}

export function numberValue(value: unknown, fallback: number): number {
  const parsed = Number.parseInt(String(value ?? ""), 10)
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback
}

function firstPresent(...values: Array<string | undefined>): string | undefined {
  return values.find((value) => value !== undefined && value !== "")
}

export async function readConfigFile(configPath: string): Promise<ConfigValues> {
  const values: ConfigValues = {}

  let text = ""
  try {
    text = await readFile(configPath, "utf8")
  } catch {
    return values
  }

  for (const rawLine of text.split(/\r?\n/)) {
    const trimmed = rawLine.trim()
    if (!trimmed || trimmed.startsWith("#")) continue
    const index = trimmed.indexOf("=")
    if (index < 0) continue
    const key = trimmed.slice(0, index).trim()
    const value = trimmed.slice(index + 1).trim()
    if (key) values[key] = value
  }

  return values
}

export async function loadConfig(reinforceRoot: string, env: Env = process.env): Promise<ReinforceConfig> {
  const fileValues = await readConfigFile(path.join(reinforceRoot, "config"))

  const disabled = firstPresent(env.REINFORCE_DISABLED, fileValues.disabled)
  const reminderThreshold = firstPresent(env.REINFORCE_REMINDER_THRESHOLD, fileValues.reminder_threshold)
  const reflectCommand = firstPresent(env.REINFORCE_OPENCODE_REFLECT_COMMAND, fileValues.opencode_reflect_command)
  const reflectModel = firstPresent(env.REINFORCE_OPENCODE_REFLECT_MODEL, fileValues.opencode_reflect_model)
  const reflectTimeout = firstPresent(env.REINFORCE_OPENCODE_REFLECT_TIMEOUT_SEC, fileValues.opencode_reflect_timeout_sec)
  const idleReflect = firstPresent(env.REINFORCE_OPENCODE_IDLE_REFLECT_SEC, fileValues.opencode_idle_reflect_sec)
  const transcriptMaxBytes = firstPresent(env.REINFORCE_OPENCODE_TRANSCRIPT_MAX_BYTES, fileValues.opencode_transcript_max_bytes)
  const nodeCommand = firstPresent(env.REINFORCE_NODE_COMMAND, env.REINFORCE_NODE, fileValues.node_command)

  return {
    disabled: truthy(disabled),
    reminderThreshold: numberValue(reminderThreshold, DEFAULT_CONFIG.reminderThreshold),
    opencodeReflectCommand: reflectCommand ?? DEFAULT_CONFIG.opencodeReflectCommand,
    opencodeReflectModel: reflectModel ?? DEFAULT_CONFIG.opencodeReflectModel,
    opencodeReflectTimeoutSec: numberValue(reflectTimeout, DEFAULT_CONFIG.opencodeReflectTimeoutSec),
    opencodeIdleReflectSec: numberValue(idleReflect, DEFAULT_CONFIG.opencodeIdleReflectSec),
    opencodeTranscriptMaxBytes: numberValue(transcriptMaxBytes, DEFAULT_CONFIG.opencodeTranscriptMaxBytes),
    nodeCommand: nodeCommand ?? DEFAULT_CONFIG.nodeCommand,
  }
}
