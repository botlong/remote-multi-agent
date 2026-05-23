'use strict';

/**
 * Credential source discovery (multi-provider).
 *
 * Surfaces credentials that exist on the gateway host so the user can
 * explicitly import them into a gateway profile. These functions are
 * read-only and never mutate the source files.
 *
 * Supported providers:
 *   - anthropic  (Claude)
 *   - openai     (Codex)
 *   - opencode   (OpenCode)
 *
 * Sources:
 *   - official:  per-provider config files (~/.claude/settings.json,
 *                ~/.codex/auth.json)
 *   - cc-switch: ~/.cc-switch/cc-switch.db (every row, all app_types)
 *
 * The legacy implicit fallback chain (env vars + auto-read these files at
 * agent run time) was removed. All credentials now live in
 * ~/.gateway/profiles.json and are imported on demand through these helpers.
 */

const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const CLAUDE_SETTINGS_PATH = path.join(os.homedir(), '.claude', 'settings.json');
const CODEX_AUTH_PATH = path.join(os.homedir(), '.codex', 'auth.json');
const CC_SWITCH_DB_PATH = path.join(os.homedir(), '.cc-switch', 'cc-switch.db');

const APP_TYPE_TO_PROVIDER = {
  claude: 'anthropic',
  'claude-desktop': 'anthropic',
  codex: 'openai',
  opencode: 'opencode',
};

const CACHE_TTL_MS = 30_000;
const _cache = new Map();

function cached(key, fetcher) {
  const entry = _cache.get(key);
  if (entry && Date.now() - entry.ts < CACHE_TTL_MS) return entry.value;
  const value = fetcher();
  _cache.set(key, { ts: Date.now(), value });
  return value;
}

function invalidateCache() {
  _cache.clear();
}

// Test seam: override paths credential discovery reads from.
//   • configurePaths()                         — reset everything to defaults
//   • configurePaths({ claudePath: '/tmp/x' }) — partial update; other paths
//                                                keep their previous override
let _claudePath = CLAUDE_SETTINGS_PATH;
let _codexPath = CODEX_AUTH_PATH;
let _ccSwitchPath = CC_SWITCH_DB_PATH;

function configurePaths(options) {
  if (options === undefined || options === null) {
    _claudePath = CLAUDE_SETTINGS_PATH;
    _codexPath = CODEX_AUTH_PATH;
    _ccSwitchPath = CC_SWITCH_DB_PATH;
    invalidateCache();
    return;
  }
  // `officialPath` is a back-compat alias for `claudePath`.
  if ('officialPath' in options) {
    _claudePath = options.officialPath || CLAUDE_SETTINGS_PATH;
  }
  if ('claudePath' in options) {
    _claudePath = options.claudePath || CLAUDE_SETTINGS_PATH;
  }
  if ('codexPath' in options) {
    _codexPath = options.codexPath || CODEX_AUTH_PATH;
  }
  if ('ccSwitchPath' in options) {
    _ccSwitchPath = options.ccSwitchPath || CC_SWITCH_DB_PATH;
  }
  invalidateCache();
}

/**
 * @typedef {Object} CredentialEntry
 * @property {string} id          Stable identifier within the source.
 * @property {'official'|'cc-switch'} source
 * @property {'anthropic'|'openai'|'opencode'} provider Gateway provider slot for this credential.
 * @property {string} label       Human-readable name.
 * @property {boolean} hasToken   True iff a token was found.
 * @property {string|null} authToken Raw token. **Caller must mask before HTTP.**
 * @property {string|null} baseUrl
 * @property {boolean} [isCurrent] CC-Switch only: marks the active provider.
 * @property {Object} [raw]       Source-specific extras.
 */

/**
 * List credentials discoverable in known per-provider config files.
 * Returns 0..N entries spanning multiple providers.
 *
 * @returns {Promise<CredentialEntry[]>}
 */
async function listOfficialCredentials() {
  return cached('official', async () => {
    const out = [];
    const claude = await _readClaudeOfficial(_claudePath);
    if (claude) out.push(claude);
    const codex = await _readCodexOfficial(_codexPath);
    if (codex) out.push(codex);
    return out;
  });
}

async function _readClaudeOfficial(filePath) {
  let raw;
  try {
    raw = await fs.readFile(filePath, 'utf8');
  } catch {
    return null;
  }
  let cfg;
  try {
    cfg = JSON.parse(raw);
  } catch (err) {
    console.warn(`[credential-sources] ${filePath} is not valid JSON: ${err.message}`);
    return null;
  }
  const env = (cfg && cfg.env) || {};
  const authToken = env.ANTHROPIC_AUTH_TOKEN || env.ANTHROPIC_API_KEY || null;
  if (!authToken || authToken === 'PROXY_MANAGED') return null;
  const baseUrl = env.ANTHROPIC_BASE_URL || null;
  if (baseUrl && /127\.0\.0\.1|localhost/i.test(baseUrl)) return null;
  return {
    id: 'claude',
    source: 'official',
    provider: 'anthropic',
    label: filePath === CLAUDE_SETTINGS_PATH ? '~/.claude/settings.json' : filePath,
    hasToken: true,
    authToken,
    baseUrl,
    raw: { path: filePath },
  };
}

async function _readCodexOfficial(filePath) {
  let raw;
  try {
    raw = await fs.readFile(filePath, 'utf8');
  } catch {
    return null;
  }
  let cfg;
  try {
    cfg = JSON.parse(raw);
  } catch (err) {
    console.warn(`[credential-sources] ${filePath} is not valid JSON: ${err.message}`);
    return null;
  }
  const authToken =
    cfg.OPENAI_API_KEY ||
    cfg.openai_api_key ||
    cfg.apiKey ||
    cfg.api_key ||
    null;
  if (!authToken) return null;
  const baseUrl =
    cfg.OPENAI_BASE_URL ||
    cfg.openai_base_url ||
    cfg.base_url ||
    null;
  return {
    id: 'codex',
    source: 'official',
    provider: 'openai',
    label: filePath === CODEX_AUTH_PATH ? '~/.codex/auth.json' : filePath,
    hasToken: true,
    authToken,
    baseUrl,
    raw: { path: filePath },
  };
}

/**
 * List all credentials discoverable in the CC-Switch SQLite database.
 * Includes every supported app_type. The active provider per app_type is
 * flagged with `isCurrent: true`.
 *
 * Returns [] if the DB or node:sqlite is unavailable. Never throws.
 *
 * @returns {Promise<CredentialEntry[]>}
 */
async function listCcSwitchCredentials() {
  return cached('cc-switch', () => _readCcSwitchCredentials());
}

async function _readCcSwitchCredentials() {
  const dbPath = _ccSwitchPath;
  try {
    await fs.access(dbPath);
  } catch {
    return [];
  }
  let DatabaseSync;
  try {
    ({ DatabaseSync } = require('node:sqlite'));
  } catch {
    return [];
  }
  // Copy the file to avoid SQLITE_BUSY if CC-Switch is running.
  const tmpPath = path.join(
    os.tmpdir(),
    `cc-switch-${process.pid}-${Date.now()}.db`,
  );
  try {
    await fs.copyFile(dbPath, tmpPath);
  } catch (err) {
    console.warn(`[credential-sources] CC-Switch copy failed: ${err.message}`);
    return [];
  }
  let db;
  try {
    db = new DatabaseSync(tmpPath, { readOnly: true });
    // SELECT * is defensive — older and newer CC-Switch schemas differ in
    // whether `auth_config` exists, so we just take whatever columns are there.
    const rows = db
      .prepare(
        'SELECT * FROM providers ORDER BY app_type ASC, is_current DESC, name ASC',
      )
      .all();
    const entries = [];
    for (const row of rows) {
      const provider = APP_TYPE_TO_PROVIDER[row.app_type];
      if (!provider) continue;
      const extracted = _extractCcSwitchCred(row);
      if (!extracted || !extracted.authToken) continue;
      entries.push({
        id: _ccSwitchEntryId(row),
        source: 'cc-switch',
        provider,
        label: row.name || `${row.app_type} #${row.id}`,
        hasToken: true,
        authToken: extracted.authToken,
        baseUrl: extracted.baseUrl,
        isCurrent: Boolean(row.is_current),
        raw: {
          providerId: row.id,
          appType: row.app_type,
          ...(row.provider_type ? { providerType: row.provider_type } : {}),
          ...(extracted.models ? { models: extracted.models } : {}),
        },
      });
    }
    return entries;
  } catch (err) {
    console.warn(`[credential-sources] CC-Switch read failed: ${err.message}`);
    return [];
  } finally {
    try {
      if (db) db.close();
    } catch {}
    fs.unlink(tmpPath).catch(() => {});
  }
}

function _ccSwitchEntryId(row) {
  return `${row.app_type}:${row.id}`;
}

function _extractCcSwitchCred(row) {
  if (row.app_type === 'claude' || row.app_type === 'claude-desktop') {
    const cfg = _tryParseJson(row.settings_config);
    const env = (cfg && cfg.env) || {};
    const authToken = env.ANTHROPIC_AUTH_TOKEN || env.ANTHROPIC_API_KEY || null;
    if (!authToken) return null;
    return { authToken, baseUrl: env.ANTHROPIC_BASE_URL || null };
  }
  if (row.app_type === 'codex') {
    const settings = _tryParseJson(row.settings_config);
    // CC-Switch has used both a dedicated `auth_config` column and a nested
    // `settings_config.auth` object across versions.
    const auth =
      _tryParseJson(row.auth_config) ||
      (settings && typeof settings.auth === 'object' ? settings.auth : null) ||
      settings;
    const authToken =
      (auth &&
        (auth.OPENAI_API_KEY ||
          auth.openai_api_key ||
          auth.apiKey ||
          auth.api_key)) ||
      null;
    let baseUrl =
      (auth &&
        (auth.OPENAI_BASE_URL ||
          auth.openai_base_url ||
          auth.baseUrl ||
          auth.base_url)) ||
      null;
    const configText =
      (settings && typeof settings.config === 'string' && settings.config) ||
      (typeof row.settings_config === 'string' ? row.settings_config : '');
    if (!baseUrl) baseUrl = _extractTomlString(configText, 'base_url');
    if (!authToken) return null;
    return { authToken, baseUrl };
  }
  if (row.app_type === 'opencode') {
    const cfg = _tryParseJson(row.settings_config);
    const options = cfg && typeof cfg.options === 'object' ? cfg.options : {};
    const authToken =
      options.apiKey ||
      options.api_key ||
      options.OPENAI_API_KEY ||
      options.openai_api_key ||
      null;
    const baseUrl =
      options.baseURL ||
      options.baseUrl ||
      options.base_url ||
      options.OPENAI_BASE_URL ||
      options.openai_base_url ||
      null;
    if (!authToken) return null;
    const models = cfg && typeof cfg.models === 'object'
      ? Object.keys(cfg.models)
      : undefined;
    return { authToken, baseUrl, models };
  }
  return null;
}

function _extractTomlString(raw, key) {
  if (typeof raw !== 'string' || !raw) return null;
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = raw.match(new RegExp(`^\\s*${escaped}\\s*=\\s*"([^"]+)"`, 'm'));
  return match ? match[1] : null;
}

function _tryParseJson(raw) {
  if (typeof raw !== 'string' || !raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

/**
 * Resolve a single credential by source + optional id. For `cc-switch`,
 * `sourceId` selects a specific row; if omitted, the active Claude provider
 * (or first available entry) is returned.
 *
 * @param {{ source: 'official'|'cc-switch', sourceId?: string }} options
 * @returns {Promise<CredentialEntry|null>}
 */
async function loadCredential({ source, sourceId } = {}) {
  if (source === 'official') {
    const entries = await listOfficialCredentials();
    if (sourceId != null && sourceId !== '') {
      return entries.find((e) => e.id === String(sourceId)) || null;
    }
    return entries[0] || null;
  }
  if (source === 'cc-switch') {
    const entries = await listCcSwitchCredentials();
    if (sourceId != null && sourceId !== '') {
      const id = String(sourceId);
      return entries.find((e) => (
        e.id === id ||
        String(e.raw?.providerId) === id ||
        `${e.raw?.appType}:${e.raw?.providerId}` === id
      )) || null;
    }
    return entries.find((e) => e.isCurrent) || entries[0] || null;
  }
  return null;
}

/**
 * Strip the raw `authToken` from a credential entry. Use before sending entries
 * over HTTP. Replaces it with a short masked preview.
 *
 * @param {CredentialEntry} entry
 * @returns {Object}
 */
function maskCredentialEntry(entry) {
  if (!entry) return entry;
  const token = entry.authToken || '';
  const masked = token.length >= 12 ? `${token.slice(0, 7)}...${token.slice(-3)}` : token ? '***' : null;
  const copy = { ...entry, tokenPreview: masked };
  delete copy.authToken;
  return copy;
}

module.exports = {
  CC_SWITCH_DB_PATH,
  CLAUDE_SETTINGS_PATH,
  CODEX_AUTH_PATH,
  APP_TYPE_TO_PROVIDER,
  configurePaths,
  invalidateCache,
  listCcSwitchCredentials,
  listOfficialCredentials,
  loadCredential,
  maskCredentialEntry,
};
