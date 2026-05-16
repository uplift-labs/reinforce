#!/usr/bin/env node
import { existsSync } from "node:fs"
import { copyFile, mkdir, readdir, readFile, rm, stat, writeFile } from "node:fs/promises"
import path from "node:path"

interface InstallOptions {
  target: string
  prefix: string
  sourceRoot?: string
}

const HELP = `install.ts - install reinforce OpenCode integration into a target git repo.

Usage:
  node dist/cli/install.js [--target <repo-dir>] [--prefix <dir>]

Installs the OpenCode project plugin, OpenCode skill, and the OpenCode
reflection backend by default.`

function parseArgs(argv: string[]): InstallOptions {
  let target = ""
  let prefix = ".uplift"

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    if (arg === "--target") {
      target = argv[index + 1] ?? ""
      index += 1
      continue
    }
    if (arg === "--prefix") {
      prefix = argv[index + 1] ?? ""
      index += 1
      continue
    }
    if (arg === "-h" || arg === "--help") {
      console.log(HELP)
      process.exit(0)
    }
    throw new Error(`unknown arg: ${arg}`)
  }

  return {
    target: path.resolve(target || process.cwd()),
    prefix: prefix || ".uplift",
  }
}

function defaultSourceRoot(): string {
  const compiledRoot = path.resolve(__dirname, "..", "..")
  if (existsSync(path.join(compiledRoot, "adapters"))) return compiledRoot
  return path.resolve(__dirname, "..")
}

async function copyDir(src: string, dest: string): Promise<void> {
  await rm(dest, { recursive: true, force: true })
  await mkdir(dest, { recursive: true })

  for (const entry of await readdir(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name)
    const destPath = path.join(dest, entry.name)
    if (entry.isDirectory()) {
      await copyDir(srcPath, destPath)
    } else if (entry.isFile()) {
      await copyFile(srcPath, destPath)
    }
  }
}

async function copyMarkdownTemplates(src: string, dest: string): Promise<void> {
  await mkdir(dest, { recursive: true })
  for (const entry of await readdir(src, { withFileTypes: true })) {
    if (entry.isFile() && entry.name.endsWith(".md")) {
      await copyFile(path.join(src, entry.name), path.join(dest, entry.name))
    }
  }
}

function escapeForDoubleQuotedString(value: string): string {
  return value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
}

async function installPlugin(sourceRoot: string, prefix: string, dest: string): Promise<void> {
  const source = path.join(sourceRoot, "adapters", "opencode", "plugins", "reinforce.ts")
  const raw = await readFile(source, "utf8")
  const rendered = raw.replaceAll("__REINFORCE_PREFIX__", escapeForDoubleQuotedString(prefix))
  await mkdir(path.dirname(dest), { recursive: true })
  await writeFile(dest, rendered, "utf8")
}

async function assertBuildAvailable(sourceRoot: string): Promise<void> {
  const backend = path.join(sourceRoot, "dist", "core", "session-reflect-opencode.js")
  const compiled = await stat(backend).catch(() => null)
  if (!compiled?.isFile()) {
    throw new Error("compiled backend missing; run `npm run build` before installing")
  }
}

export async function install(options: InstallOptions): Promise<void> {
  const sourceRoot = options.sourceRoot ?? defaultSourceRoot()
  const target = path.resolve(options.target)
  const prefix = options.prefix || ".uplift"

  if (!existsSync(path.join(target, ".git"))) {
    throw new Error(`not a git repo: ${target}`)
  }

  await assertBuildAvailable(sourceRoot)

  const installRoot = path.join(target, prefix, "reinforce")
  const coreRoot = path.join(installRoot, "core")
  const distRoot = path.join(installRoot, "dist")
  const adapterDir = path.join(installRoot, "adapters", "opencode")
  const pluginPath = path.join(target, ".opencode", "plugins", "reinforce.ts")
  const skillDest = path.join(target, ".opencode", "skills", "reinforce")

  await mkdir(path.join(coreRoot, "templates"), { recursive: true })
  await mkdir(path.join(adapterDir, "plugins"), { recursive: true })
  await mkdir(path.join(installRoot, "reflections"), { recursive: true })

  await rm(path.join(coreRoot, "cmd"), { recursive: true, force: true })
  await rm(path.join(coreRoot, "lib"), { recursive: true, force: true })

  console.log(`[reinforce] copying compiled OpenCode backend to ${distRoot}`)
  await copyDir(path.join(sourceRoot, "dist", "core"), path.join(distRoot, "core"))

  await copyMarkdownTemplates(path.join(sourceRoot, "core", "templates"), path.join(coreRoot, "templates"))

  const configPath = path.join(installRoot, "config")
  if (!existsSync(configPath)) {
    await copyFile(path.join(sourceRoot, "core", "config.defaults"), configPath)
    console.log(`[reinforce] created default config at ${configPath}`)
  }

  console.log(`[reinforce] copying OpenCode adapter to ${adapterDir}`)
  await installPlugin(sourceRoot, prefix, path.join(adapterDir, "plugins", "reinforce.ts"))
  await installPlugin(sourceRoot, prefix, pluginPath)
  console.log(`[reinforce] OpenCode plugin installed at ${pluginPath}`)

  await mkdir(skillDest, { recursive: true })
  await copyFile(path.join(sourceRoot, "skills", "reinforce", "SKILL.md"), path.join(skillDest, "SKILL.md"))
  console.log(`[reinforce] OpenCode skill installed at ${skillDest}`)

  console.log("[reinforce] done.")
  console.log(`  backend installed at: ${path.join(distRoot, "core")}`)
  console.log(`  reflections dir:      ${path.join(installRoot, "reflections")}`)
  console.log(`  opencode adapter:     ${adapterDir}`)
  console.log(`  opencode plugin:      ${pluginPath}`)
  console.log(`  opencode skill:       ${skillDest}`)
  console.log("")
  console.log(`  Commit ${installRoot}/ and .opencode/ so reinforce is available in worktrees.`)
  console.log("  OpenCode project-local plugins require this project config to be trusted by OpenCode.")
}

if (require.main === module) {
  install(parseArgs(process.argv.slice(2))).catch((error: Error) => {
    console.error(error.message)
    process.exit(error.message.startsWith("unknown arg:") ? 2 : 1)
  })
}
