import test from "node:test"
import assert from "node:assert/strict"
import { execFile } from "node:child_process"
import { chmod, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import { promisify } from "node:util"
import { install } from "../cli/install"
import { runSessionReflect } from "../core/session-reflect-opencode"

const execFileAsync = promisify(execFile)

const DEFAULT_REFLECTION = `# Session Reflection

**Date:** fake-opencode-date

## Goal
Verify OpenCode default reflection backend.

## Outcome
ACCOMPLISHED - The fake OpenCode command returned a reflection.

## What worked
The backend invoked opencode run with the transcript attached.

## Mistakes and corrections
None

## What was left undone
All goals met

## Key decision
Use OpenCode as the default external command.

## Quality check
Clean

## Lesson learned
WHEN testing OpenCode reflection -> DO fake the CLI BECAUSE it avoids network and model variance.

## Action items
Keep this test covering the default OpenCode command path.`

const CUSTOM_REFLECTION = `# Session Reflection

**Date:** fake-custom-date

## Goal
Verify OpenCode custom reflection command.

## Outcome
ACCOMPLISHED - The configured external command returned a reflection.

## What worked
The backend passed prompt, transcript, and repository env vars.

## Mistakes and corrections
None

## What was left undone
All goals met

## Key decision
Allow user-configurable reflection commands with a safe fallback.

## Quality check
Clean

## Lesson learned
WHEN users need a different backend -> DO use opencode_reflect_command BECAUSE the default may not fit every environment.

## Action items
Keep this test covering the custom command path.`

function quote(value: string): string {
  return `"${value.replace(/"/g, '\\"')}"`
}

async function writeNodeCommand(dir: string, name: string, source: string): Promise<string> {
  await mkdir(dir, { recursive: true })
  const scriptPath = path.join(dir, `${name}-impl.js`)
  await writeFile(scriptPath, source, "utf8")
  if (process.platform === "win32") {
    const commandPath = path.join(dir, `${name}.cmd`)
    await writeFile(commandPath, `@echo off\r\n"${process.execPath}" "${scriptPath}" %*\r\n`, "utf8")
    return commandPath
  }

  const commandPath = path.join(dir, name)
  await writeFile(commandPath, `#!/usr/bin/env node\nrequire(${JSON.stringify(scriptPath)})\n`, "utf8")
  await chmod(commandPath, 0o755)
  return commandPath
}

async function reflectionFiles(repo: string): Promise<string[]> {
  const dir = path.join(repo, ".uplift", "reinforce", "reflections")
  const files = await readdir(dir)
  return files.filter((file) => file.endsWith(".md")).map((file) => path.join(dir, file))
}

function envWithPathPrepended(dir: string): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = { ...process.env }
  const pathKey = Object.keys(env).find((key) => key.toLowerCase() === "path") ?? "PATH"
  env[pathKey] = `${dir}${path.delimiter}${env[pathKey] ?? ""}`
  if (pathKey !== "PATH") delete env.PATH
  return env
}

test("reflection backend invokes default opencode command", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "reinforce-reflect-default-"))
  const previousCwd = process.cwd()
  try {
    const repo = path.join(temp, "repo")
    const fakeBin = path.join(temp, "bin")
    await execFileAsync("git", ["init", repo])
    await install({ target: repo, prefix: ".uplift", sourceRoot: path.resolve(__dirname, "..", "..") })

    await writeNodeCommand(fakeBin, "opencode", `
const args = process.argv.slice(2)
if (args.shift() !== "run") process.exit(2)
let sawPure = false
let sawFormat = false
let sawDir = false
let sawFile = false
let prompt = ""
for (let index = 0; index < args.length; index += 1) {
  const arg = args[index]
  if (arg === "--pure") { sawPure = true; continue }
  if (arg === "--format") { sawFormat = args[index + 1] === "default"; index += 1; continue }
  if (arg === "--dir") { sawDir = true; index += 1; continue }
  if (arg === "--file") { sawFile = true; index += 1; continue }
  if (arg === "--model") { index += 1; continue }
  prompt = arg
}
if (!sawPure || !sawFormat || !sawDir || !sawFile || !prompt) {
  console.error(JSON.stringify({ sawPure, sawFormat, sawDir, sawFile, prompt, args }))
  process.exit(2)
}
console.log(${JSON.stringify(DEFAULT_REFLECTION)})
`)

    const transcript = path.join(temp, "transcript.jsonl")
    const sessionId = `opencode-default-${Date.now()}`
    await writeFile(transcript, JSON.stringify({ type: "session.next.prompted", properties: { sessionID: sessionId } }) + "\n", "utf8")

    await runSessionReflect([
      "--session-id", sessionId,
      "--reinforce-root", path.join(repo, ".uplift", "reinforce"),
      "--transcript-path", transcript,
    ], envWithPathPrepended(fakeBin))

    const files = await reflectionFiles(repo)
    assert.equal(files.length, 1)
    assert.match(await readFile(files[0], "utf8"), /Verify OpenCode default reflection backend/)
    assert.match(path.basename(files[0]), new RegExp(sessionId))
  } finally {
    process.chdir(previousCwd)
    await rm(temp, { recursive: true, force: true })
  }
})

test("reflection backend invokes configured custom command", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "reinforce-reflect-custom-"))
  const previousCwd = process.cwd()
  try {
    const repo = path.join(temp, "repo")
    await execFileAsync("git", ["init", repo])
    await install({ target: repo, prefix: ".uplift", sourceRoot: path.resolve(__dirname, "..", "..") })

    const customScript = path.join(temp, "custom-reflect.js")
    await writeFile(customScript, `
if (!process.env.REINFORCE_REFLECT_PROMPT) process.exit(2)
if (!process.env.REINFORCE_TRANSCRIPT_PATH) process.exit(2)
if (!process.env.REINFORCE_REPO_ROOT) process.exit(2)
process.stdin.resume()
process.stdin.on("end", () => {
  console.log(${JSON.stringify(CUSTOM_REFLECTION)})
})
`, "utf8")

    await writeFile(
      path.join(repo, ".uplift", "reinforce", "config"),
      `opencode_reflect_command=${quote(process.execPath)} ${quote(customScript)}\n`,
      "utf8",
    )

    const transcript = path.join(temp, "custom-transcript.jsonl")
    const sessionId = `opencode-custom-${Date.now()}`
    await writeFile(transcript, JSON.stringify({ type: "session.next.prompted", properties: { sessionID: sessionId } }) + "\n", "utf8")

    await runSessionReflect([
      "--session-id", sessionId,
      "--reinforce-root", path.join(repo, ".uplift", "reinforce"),
      "--transcript-path", transcript,
    ], process.env)

    const files = await reflectionFiles(repo)
    assert.equal(files.length, 1)
    assert.match(await readFile(files[0], "utf8"), /Verify OpenCode custom reflection command/)
    assert.match(path.basename(files[0]), new RegExp(sessionId))
  } finally {
    process.chdir(previousCwd)
    await rm(temp, { recursive: true, force: true })
  }
})
