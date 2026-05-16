#!/usr/bin/env node
import { spawn, spawnSync } from "node:child_process"
import { createReadStream } from "node:fs"
import { appendFile, mkdir, readFile, rm, stat, writeFile } from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import { loadConfig, numberValue } from "./config"

interface ReflectArgs {
  sessionId: string
  transcriptPath: string
  reinforceRoot: string
}

interface CommandResult {
  code: number
  stdout: string
  stderr: string
}

type Env = NodeJS.ProcessEnv

function parseArgs(argv: string[]): Partial<ReflectArgs> {
  const parsed: Partial<ReflectArgs> = {}
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === "--session-id") {
      parsed.sessionId = argv[index + 1] ?? ""
      index += 1
      continue
    }
    if (arg === "--transcript-path") {
      parsed.transcriptPath = argv[index + 1] ?? ""
      index += 1
      continue
    }
    if (arg === "--reinforce-root") {
      parsed.reinforceRoot = argv[index + 1] ?? ""
      index += 1
    }
  }
  return parsed
}

function defaultReinforceRoot(): string {
  return path.resolve(__dirname, "..", "..")
}

function safePathPart(value: string): string {
  return value.replace(/[\\/:]/g, "_")
}

function formatDatestamp(date: Date): string {
  const pad = (value: number) => String(value).padStart(2, "0")
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
  ].join("-") + `-${pad(date.getHours())}${pad(date.getMinutes())}${pad(date.getSeconds())}`
}

function resolveProjectRoot(reinforceRoot: string): string {
  const result = spawnSync("git", ["-C", reinforceRoot, "rev-parse", "--show-toplevel"], {
    encoding: "utf8",
    stdio: ["ignore", "pipe", "ignore"],
  })
  const root = result.status === 0 ? result.stdout.trim() : ""
  return root || path.dirname(path.dirname(reinforceRoot))
}

async function readPrompt(reinforceRoot: string, datestamp: string): Promise<string> {
  const templatePath = path.join(reinforceRoot, "core", "templates", "reflection-output-prompt-opencode.md")
  let prompt = "Review the attached OpenCode transcript. If trivial, output exactly SKIP. Otherwise output a markdown reflection with sections: Goal, Outcome, What worked, Mistakes and corrections, What was left undone, Key decision, Quality check, Lesson learned, Action items."
  try {
    prompt = await readFile(templatePath, "utf8")
  } catch {
    // Missing templates should not prevent reflection attempts.
  }
  return prompt.replaceAll("{{DATESTAMP}}", datestamp)
}

function isCi(env: Env): boolean {
  return env.CI === "true" || Boolean(env.GITHUB_ACTIONS) || Boolean(env.GITLAB_CI)
}

function windowsCmdArg(value: string): string {
  const normalized = value.replace(/\r?\n/g, " ")
  return `"${normalized.replace(/["^&|<>%]/g, (match) => `^${match}`)}"`
}

function windowsCommandLine(command: string, args: string[]): string {
  return [command, ...args.map(windowsCmdArg)].join(" ")
}

async function runCommand(options: {
  command: string
  args?: string[]
  cwd: string
  env: Env
  stdinFile?: string
  shell?: boolean
  timeoutMs: number
}): Promise<CommandResult> {
  return new Promise((resolve) => {
    let settled = false
    let stdout = ""
    let stderr = ""
    let timedOut = false

    const child = spawn(options.command, options.args ?? [], {
      cwd: options.cwd,
      env: options.env,
      shell: options.shell ?? false,
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"],
    })

    const finish = (code: number) => {
      if (settled) return
      settled = true
      clearTimeout(timer)
      resolve({ code, stdout, stderr })
    }

    const timer = setTimeout(() => {
      timedOut = true
      child.kill()
    }, options.timeoutMs)

    child.stdout.setEncoding("utf8")
    child.stderr.setEncoding("utf8")
    child.stdout.on("data", (chunk: string) => { stdout += chunk })
    child.stderr.on("data", (chunk: string) => { stderr += chunk })
    child.on("error", (error: NodeJS.ErrnoException) => {
      stderr += `${error.message}\n`
      finish(error.code === "ENOENT" ? 127 : 1)
    })
    child.on("close", (code) => finish(code ?? (timedOut ? 124 : 1)))

    if (options.stdinFile) {
      const input = createReadStream(options.stdinFile)
      input.on("error", (error) => {
        stderr += `${error.message}\n`
        child.stdin.end()
      })
      input.pipe(child.stdin)
    } else {
      child.stdin.end()
    }
  })
}

export async function runSessionReflect(argv = process.argv.slice(2), env: Env = process.env): Promise<void> {
  const parsed = parseArgs(argv)
  const sessionId = parsed.sessionId ?? ""
  const transcriptPath = parsed.transcriptPath ?? ""
  const reinforceRoot = parsed.reinforceRoot || defaultReinforceRoot()

  if (!sessionId || !transcriptPath) return

  const config = await loadConfig(reinforceRoot, env)
  if (config.disabled || isCi(env)) return

  const safeSession = safePathPart(sessionId)
  const projectRoot = resolveProjectRoot(reinforceRoot)
  const projectHash = safePathPart(projectRoot)
  const stateDir = path.join(os.tmpdir(), "reinforce-sessions", "opencode", projectHash)
  await mkdir(stateDir, { recursive: true }).catch(() => undefined)

  const dedupFile = path.join(stateDir, `${safeSession}.reflect`)
  const lockDir = path.join(stateDir, `${safeSession}.lock`)
  const logFile = path.join(stateDir, `session-reflect-opencode-${safeSession}.log`)
  const outFile = path.join(stateDir, `session-reflect-opencode-${safeSession}.out`)
  const log = async (message: string) => {
    const stamp = new Date().toTimeString().slice(0, 8)
    await appendFile(logFile, `[${stamp}] ${message}\n`, "utf8").catch(() => undefined)
  }

  const dedupState = await readFile(dedupFile, "utf8").catch(() => "")
  if (dedupState === "done" || dedupState === "skipped") return
  if (dedupState === "claimed") {
    const existingLock = await stat(lockDir).catch(() => null)
    if (existingLock?.isDirectory()) return
  }

  try {
    await mkdir(lockDir)
  } catch {
    return
  }

  try {
    await writeFile(dedupFile, "claimed", "utf8").catch(() => undefined)

    const transcript = await stat(transcriptPath).catch(() => null)
    if (!transcript?.isFile()) {
      await rm(dedupFile, { force: true }).catch(() => undefined)
      return
    }

    const reflectionsDir = path.join(reinforceRoot, "reflections")
    await mkdir(reflectionsDir, { recursive: true }).catch(() => undefined)

    const datestamp = formatDatestamp(new Date())
    const targetFile = path.join(reflectionsDir, `${datestamp}-opencode-${safeSession}-${process.pid}.md`)
    const prompt = await readPrompt(reinforceRoot, datestamp)
    const timeoutSec = numberValue(env.REINFORCE_OPENCODE_WATCHDOG_SEC, config.opencodeReflectTimeoutSec)
    const timeoutMs = Math.max(1, timeoutSec) * 1000

    await log(`session-reflect-opencode started for ${safeSession}`)
    await log(`REINFORCE_ROOT: ${reinforceRoot}`)
    await log(`TRANSCRIPT_PATH: ${transcriptPath}`)

    const project = await stat(projectRoot).catch(() => null)
    if (!project?.isDirectory()) {
      await log(`cwd-recovery-failed: ${projectRoot} missing or stat failed`)
      await writeFile(dedupFile, "failed", "utf8").catch(() => undefined)
      return
    }

    const childEnv: Env = {
      ...env,
      REINFORCE_DISABLED: "1",
    }

    let result: CommandResult
    if (config.opencodeReflectCommand) {
      await log(`reflect command=custom watchdog=${timeoutSec}s`)
      result = await runCommand({
        command: config.opencodeReflectCommand,
        cwd: projectRoot,
        env: {
          ...childEnv,
          REINFORCE_REFLECT_PROMPT: prompt,
          REINFORCE_TRANSCRIPT_PATH: transcriptPath,
          REINFORCE_REPO_ROOT: projectRoot,
          REINFORCE_OUTPUT_FILE: outFile,
        },
        stdinFile: transcriptPath,
        shell: true,
        timeoutMs,
      })
    } else {
      const args = ["run", "--pure", "--format", "default", "--dir", projectRoot, "--file", transcriptPath]
      if (config.opencodeReflectModel) args.push("--model", config.opencodeReflectModel)
      args.push(prompt)
      await log(`reflect command=opencode run watchdog=${timeoutSec}s model=${config.opencodeReflectModel || "<default>"}`)
      result = process.platform === "win32"
        ? await runCommand({
          command: windowsCommandLine("opencode", args),
          cwd: projectRoot,
          env: childEnv,
          shell: true,
          timeoutMs,
        })
        : await runCommand({
          command: "opencode",
          args,
          cwd: projectRoot,
          env: childEnv,
          timeoutMs,
        })
    }

    await writeFile(outFile, result.stdout, "utf8").catch(() => undefined)
    if (result.stderr) await appendFile(logFile, result.stderr, "utf8").catch(() => undefined)

    if (result.code !== 0) {
      await log(`FAILED: reflection command exited with code ${result.code}`)
      await writeFile(dedupFile, "failed", "utf8").catch(() => undefined)
      return
    }

    const compact = result.stdout.replace(/\s/g, "")
    if (!compact || compact === "SKIP") {
      await log("SKIPPED: reflection command returned no reflection")
      await writeFile(dedupFile, "skipped", "utf8").catch(() => undefined)
      return
    }

    await writeFile(targetFile, `${result.stdout.replace(/\s+$/u, "")}\n`, "utf8")
    await log(`SUCCESS: reflection file created at ${targetFile}`)
    await writeFile(dedupFile, "done", "utf8").catch(() => undefined)
    await log("session-reflect-opencode finished")
  } catch (error) {
    await log(`FAILED: ${String(error)}`)
    await writeFile(dedupFile, "failed", "utf8").catch(() => undefined)
  } finally {
    await rm(lockDir, { recursive: true, force: true }).catch(() => undefined)
  }
}

if (require.main === module) {
  runSessionReflect()
    .catch(() => undefined)
    .finally(() => process.exit(0))
}
