import test from "node:test"
import assert from "node:assert/strict"
import { execFile } from "node:child_process"
import { mkdtemp, readFile, rm, stat, writeFile } from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import { promisify } from "node:util"
import { install } from "../cli/install"

const execFileAsync = promisify(execFile)

async function exists(filePath: string): Promise<boolean> {
  return Boolean(await stat(filePath).catch(() => null))
}

test("installer creates idempotent OpenCode integration", async () => {
  const temp = await mkdtemp(path.join(os.tmpdir(), "reinforce-install-"))
  try {
    const repo = path.join(temp, "repo")
    await rm(repo, { recursive: true, force: true })
    await execFileAsync("git", ["init", repo])
    await writeFile(path.join(repo, "opencode.json"), '{"permission":{"bash":{"git status*":"allow"}}}\n', "utf8")

    const sourceRoot = path.resolve(__dirname, "..", "..")
    await install({ target: repo, prefix: ".uplift", sourceRoot })

    assert.equal(await exists(path.join(repo, ".uplift", "reinforce", "dist", "core", "session-reflect-opencode.js")), true)
    assert.equal(await exists(path.join(repo, ".uplift", "reinforce", "core", "templates", "reflection-output-prompt-opencode.md")), true)
    assert.equal(await exists(path.join(repo, ".uplift", "reinforce", "adapters", "opencode", "plugins", "reinforce.ts")), true)
    assert.equal(await exists(path.join(repo, ".opencode", "plugins", "reinforce.ts")), true)
    assert.equal(await exists(path.join(repo, ".opencode", "skills", "reinforce", "SKILL.md")), true)
    assert.equal(await exists(path.join(repo, ".uplift", "reinforce", "core", "cmd", "session-reflect-opencode.sh")), false)

    const plugin = await readFile(path.join(repo, ".opencode", "plugins", "reinforce.ts"), "utf8")
    assert.match(plugin, /session-reflect-opencode\.js/)
    assert.match(plugin, /server\.instance\.disposed/)
    assert.match(plugin, /session\.status/)
    assert.doesNotMatch(plugin, /\.sh/)

    const config = await readFile(path.join(repo, ".uplift", "reinforce", "config"), "utf8")
    assert.match(config, /opencode_reflect_command=/)
    assert.match(await readFile(path.join(repo, "opencode.json"), "utf8"), /git status/)

    await install({ target: repo, prefix: ".uplift", sourceRoot })
    assert.equal(await exists(path.join(repo, ".opencode", "plugins", "reinforce.ts")), true)
  } finally {
    await rm(temp, { recursive: true, force: true })
  }
})
