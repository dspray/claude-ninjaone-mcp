# claude-ninjaone-mcp

PrecisionIT Azure Key Vault launcher for the **NinjaOne (NinjaRMM)** MCP connector.

This repo does **not** contain a custom MCP server. It is a thin launcher that
wraps the community package [`@adamhancock/ninjarmm-mcp`](https://www.npmjs.com/package/@adamhancock/ninjarmm-mcp)
(pinned, see `package.json`) and injects credentials from Azure Key Vault at
runtime — the same pattern as `claude-halopsa-mcp` and the Meraki connector.

## How it works

1. `mcp-keyvault-launch.js` authenticates to Azure using the technician's own
   `az login` identity (`AzureCliCredential`).
2. It reads the NinjaOne secrets from `PrecisionIT-MCP-RW` (whole-set fallback to
   `PrecisionIT-MCP-RO`) and injects them as environment variables.
3. It then spawns the pinned `@adamhancock/ninjarmm-mcp` server over stdio.

No credentials are ever written to the Claude config file. Per-technician
attribution lives at the Key Vault access layer (your Entra entitlement governs
which vault answers); NinjaOne itself sees the shared OAuth application.

## Key Vault secrets

| Secret | Value |
|---|---|
| `NinjaOneClientId` | OAuth client ID of the PrecisionIT "API Services" app |
| `NinjaOneClientSecret` | OAuth client secret (rotate here, never in config) |
| `NinjaOneRegion` | `us` (North America) |

`NINJAONE_SCOPE` (`monitoring management control`) is set as a constant in the
launcher — it is not sensitive and is not vaulted.

## Install

Run the guided `ninjaone-connector-deploy` skill, or directly:

**macOS / Linux**
```bash
curl -fsSL https://raw.githubusercontent.com/dspray/claude-ninjaone-mcp/main/install/install.sh | bash
```

**Windows (PowerShell)**
```powershell
powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/dspray/claude-ninjaone-mcp/main/install/install.ps1 -OutFile $env:TEMP\n.ps1; & $env:TEMP\n.ps1"
```

The installer resolves node's absolute path, clones/updates this repo, runs
`npm ci`, and wires the `ninjaone` entry into both Claude Desktop and Claude
Code (backing up the Desktop config first). Fully restart Claude Desktop after.

## Version pinning

`@adamhancock/ninjarmm-mcp` is pinned to an exact version in `package.json`
(not `latest`) because the connector carries `management control` scope — it can
run scripts on endpoints. Treat version bumps as reviewed changes: update the
pin deliberately, regenerate `package-lock.json`, and re-test.

## Pairs with

- `ninjaone-connector-deploy` — guided installation skill
- `ninjaone-connector` — connector usage / quirks reference
- `NinjaOne_Connector_Setup.docx` — handoff guide
