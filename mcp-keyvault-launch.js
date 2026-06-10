#!/usr/bin/env node
/**
 * mcp-keyvault-launch.js — NinjaOne (NinjaRMM) MCP launcher (PrecisionIT)
 *
 * Mirrors the HaloPSA / Meraki connector pattern:
 *   - Authenticates to Azure with the tech's `az login` identity (AzureCliCredential)
 *   - Pulls NinjaOne OAuth config from Key Vault at runtime (RW first, whole-set RO fallback)
 *   - Injects NINJAONE_* env vars and spawns @adamhancock/ninjarmm-mcp over stdio
 *   - No secrets ever touch the Claude config file
 *
 * The wrapped server reads NINJAONE_CLIENT_ID / NINJAONE_CLIENT_SECRET / NINJAONE_REGION,
 * plus NINJAONE_SCOPE. Scope is not sensitive and rarely changes, so it is set here as a
 * constant rather than vaulted. The package version is pinned in package.json (not `latest`),
 * because this connector carries `management control` scope (it can run scripts on endpoints).
 *
 * IMPORTANT: stdout is reserved for the MCP JSON-RPC stream. All diagnostics go to stderr.
 */

const path = require('path');
const { spawn } = require('child_process');
const { AzureCliCredential } = require('@azure/identity');
const { SecretClient } = require('@azure/keyvault-secrets');

// --- Config -----------------------------------------------------------------
const RW_VAULT = 'https://precisionit-mcp-rw.vault.azure.net';
const RO_VAULT = 'https://precisionit-mcp-ro.vault.azure.net';

// Vault secret name -> env var the connector expects.
// Edit the secret names here if you named them differently in Key Vault.
const SECRET_MAP = {
  NINJAONE_CLIENT_ID: 'NinjaOneClientId',
  NINJAONE_CLIENT_SECRET: 'NinjaOneClientSecret',
  NINJAONE_REGION: 'NinjaOneRegion',
};

// Not sensitive; rarely changes. Set here rather than vaulted.
const NINJAONE_SCOPE = 'monitoring management control';

const MCP_PACKAGE = '@adamhancock/ninjarmm-mcp';
// ----------------------------------------------------------------------------

function log(msg) {
  process.stderr.write(`[ninjaone-launch] ${msg}\n`);
}

async function readAllFromVault(vaultUrl, credential) {
  const client = new SecretClient(vaultUrl, credential);
  const out = {};
  for (const [envVar, secretName] of Object.entries(SECRET_MAP)) {
    const secret = await client.getSecret(secretName);
    out[envVar] = secret.value;
  }
  return out;
}

async function resolveSecrets(credential) {
  // Whole-set fallback: read every secret from RW; if RW is unavailable for any
  // reason, read the full set from RO instead. Creds never come from mixed vaults.
  try {
    log('Reading secrets from RW vault…');
    const env = await readAllFromVault(RW_VAULT, credential);
    log('RW vault OK');
    return env;
  } catch (rwErr) {
    log(`RW vault unavailable (${rwErr.message}); falling back to RO…`);
    const env = await readAllFromVault(RO_VAULT, credential);
    log('RO vault OK');
    return env;
  }
}

function resolveMcpBin() {
  const pkgJsonPath = require.resolve(`${MCP_PACKAGE}/package.json`);
  const pkgDir = path.dirname(pkgJsonPath);
  const pkg = require(pkgJsonPath);
  let bin = pkg.bin;
  if (bin && typeof bin === 'object') bin = Object.values(bin)[0];
  if (!bin) throw new Error(`${MCP_PACKAGE} exposes no bin entry`);
  return path.join(pkgDir, bin);
}

(async () => {
  try {
    const credential = new AzureCliCredential();
    const secretEnv = await resolveSecrets(credential);

    const childEnv = {
      ...process.env,
      ...secretEnv,
      NINJAONE_SCOPE,
    };

    const binPath = resolveMcpBin();
    log(`Launching ${MCP_PACKAGE}…`);

    const child = spawn(process.execPath, [binPath], {
      stdio: 'inherit',
      env: childEnv,
    });

    child.on('exit', (code) => process.exit(code ?? 0));
    child.on('error', (err) => {
      log(`spawn error: ${err.message}`);
      process.exit(1);
    });
  } catch (err) {
    log(`FATAL: ${err.message}`);
    process.exit(1);
  }
})();
