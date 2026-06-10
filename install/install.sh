#!/usr/bin/env bash
#
# PrecisionIT — NinjaOne (NinjaRMM) MCP connector installer (macOS / Linux)
#
# Resolves node's absolute path, clones (or updates) the launcher repo, installs
# dependencies, and wires the `ninjaone` entry into Claude Desktop and Claude Code.
# Backs up the Desktop config first. Idempotent — safe to re-run.
#
set -euo pipefail

REPO_URL="https://github.com/dspray/claude-ninjaone-mcp.git"
INSTALL_DIR="$HOME/claude-ninjaone-mcp"
LAUNCHER="$INSTALL_DIR/mcp-keyvault-launch.js"

echo "==> PrecisionIT NinjaOne connector installer"

# 1. Resolve absolute node path (Claude Desktop spawns with a minimal PATH)
NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
  echo "ERROR: node not found on PATH. Install Node 18+ and re-run." >&2
  exit 1
fi
NODE_BIN="$(cd "$(dirname "$NODE_BIN")" && pwd)/$(basename "$NODE_BIN")"
echo "    node: $NODE_BIN"

# 2. Clone or update the repo
if [ -d "$INSTALL_DIR/.git" ]; then
  echo "==> Updating existing checkout in $INSTALL_DIR"
  git -C "$INSTALL_DIR" pull --ff-only
else
  echo "==> Cloning into $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# 3. Install dependencies (pinned via package-lock.json)
echo "==> npm ci"
( cd "$INSTALL_DIR" && npm ci )

# 4. Wire Claude Desktop config (node-based JSON merge; backs up first)
case "$(uname -s)" in
  Darwin) DESKTOP_CFG="$HOME/Library/Application Support/Claude/claude_desktop_config.json" ;;
  Linux)  DESKTOP_CFG="$HOME/.config/Claude/claude_desktop_config.json" ;;
  *)      DESKTOP_CFG="" ;;
esac

if [ -n "$DESKTOP_CFG" ]; then
  mkdir -p "$(dirname "$DESKTOP_CFG")"
  [ -f "$DESKTOP_CFG" ] && cp "$DESKTOP_CFG" "$DESKTOP_CFG.bak.$(date +%Y%m%d%H%M%S)"
  CFG="$DESKTOP_CFG" NODE_BIN="$NODE_BIN" LAUNCHER="$LAUNCHER" "$NODE_BIN" - <<'NODE'
const fs = require('fs');
const cfgPath = process.env.CFG;
let cfg = {};
try { cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8')); } catch (_) {}
cfg.mcpServers = cfg.mcpServers || {};
cfg.mcpServers.ninjaone = { command: process.env.NODE_BIN, args: [process.env.LAUNCHER] };
fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
console.log("    wrote ninjaone -> " + cfgPath);
NODE
fi

# 5. Wire Claude Code (if the CLI is present)
if command -v claude >/dev/null 2>&1; then
  echo "==> Wiring Claude Code"
  claude mcp remove ninjaone --scope user >/dev/null 2>&1 || true
  claude mcp add --scope user ninjaone -- "$NODE_BIN" "$LAUNCHER"
else
  echo "    (claude CLI not found — skipping Claude Code wiring)"
fi

echo "==> Install complete. Fully quit and reopen Claude Desktop, then verify the ninjaone tools load."
