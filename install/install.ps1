# PrecisionIT — NinjaOne (NinjaRMM) MCP connector installer (Windows / PowerShell)
#
# Resolves node's absolute path, clones (or updates) the launcher repo, installs
# dependencies, and wires the `ninjaone` entry into Claude Desktop and Claude Code.
# Backs up the Desktop config first. Idempotent — safe to re-run.
# Config merge runs through node so it works on Windows PowerShell 5.1 and pwsh 7+.

$ErrorActionPreference = "Stop"

$RepoUrl    = "https://github.com/dspray/claude-ninjaone-mcp.git"
$InstallDir = Join-Path $HOME "claude-ninjaone-mcp"
$Launcher   = Join-Path $InstallDir "mcp-keyvault-launch.js"

Write-Host "==> PrecisionIT NinjaOne connector installer"

# 1. Resolve absolute node path
$NodeBin = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $NodeBin) { Write-Error "node not found on PATH. Install Node 18+ and re-run."; exit 1 }
Write-Host "    node: $NodeBin"

# 2. Clone or update the repo
if (Test-Path (Join-Path $InstallDir ".git")) {
  Write-Host "==> Updating existing checkout in $InstallDir"
  git -C $InstallDir pull --ff-only
} else {
  Write-Host "==> Cloning into $InstallDir"
  git clone $RepoUrl $InstallDir
}

# 3. Install dependencies (pinned via package-lock.json)
Write-Host "==> npm ci"
Push-Location $InstallDir
npm ci
Pop-Location

# 4. Wire Claude Desktop config (node-based JSON merge; backs up first)
$DesktopCfg = Join-Path $env:APPDATA "Claude\claude_desktop_config.json"
New-Item -ItemType Directory -Force -Path (Split-Path $DesktopCfg) | Out-Null
if (Test-Path $DesktopCfg) {
  Copy-Item $DesktopCfg "$DesktopCfg.bak.$(Get-Date -Format yyyyMMddHHmmss)"
}

$mergeScript = @'
const fs = require('fs');
const cfgPath = process.env.CFG;
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8')); } catch (_) {}
cfg.mcpServers = cfg.mcpServers || {};
cfg.mcpServers.ninjaone = { command: process.env.NODE_BIN, args: [process.env.LAUNCHER] };
fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
console.log("    wrote ninjaone -> " + cfgPath);
'@

$env:CFG = $DesktopCfg
$env:NODE_BIN = $NodeBin
$env:LAUNCHER = $Launcher
$mergeScript | & $NodeBin -

# 5. Wire Claude Code (if the CLI is present)
if (Get-Command claude -ErrorAction SilentlyContinue) {
  Write-Host "==> Wiring Claude Code"
  claude mcp remove ninjaone --scope user 2>$null
  claude mcp add --scope user ninjaone -- $NodeBin $Launcher
} else {
  Write-Host "    (claude CLI not found — skipping Claude Code wiring)"
}

Write-Host "==> Install complete. Fully quit and reopen Claude Desktop, then verify the ninjaone tools load."
