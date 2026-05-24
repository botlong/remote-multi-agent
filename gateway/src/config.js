'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const DEFAULT_PROFILES_PATH = path.join(os.homedir(), '.gateway', 'profiles.json');

/**
 * Mask an API key for display purposes.
 * Shows first 7 chars + "..." + last 3 chars if key length >= 12,
 * otherwise returns "***".
 */
function maskKey(key) {
  if (!key || typeof key !== 'string') return '***';
  if (key.length < 12) return '***';
  return `${key.slice(0, 7)}...${key.slice(-3)}`;
}

/**
 * Deep-clone a profile with all key values masked.
 */
function maskProfile(profile) {
  const masked = { ...profile };
  if (masked.keys && typeof masked.keys === 'object') {
    const maskedKeys = {};
    for (const [provider, entry] of Object.entries(masked.keys)) {
      maskedKeys[provider] = {
        ...entry,
        key: maskKey(entry.key),
      };
    }
    masked.keys = maskedKeys;
  }
  return masked;
}

class ProfileStore {
  constructor(file) {
    this.file = file || DEFAULT_PROFILES_PATH;
    this.profiles = [];
    this.agentSettings = { agents: {} };
    this.saveQueue = Promise.resolve();
  }

  /**
   * Load profiles from disk. Creates the file with an empty array if it
   * does not exist. Handles corrupt JSON gracefully by starting fresh.
   */
  async load() {
    await fs.mkdir(path.dirname(this.file), { recursive: true });
    try {
      const raw = await fs.readFile(this.file, 'utf8');
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) {
        this.profiles = parsed;
        this.agentSettings = { agents: {} };
      } else if (parsed && typeof parsed === 'object') {
        this.profiles = Array.isArray(parsed.profiles) ? parsed.profiles : [];
        this.agentSettings = normalizeAgentSettings(parsed.agentSettings);
      } else {
        this.profiles = [];
        this.agentSettings = { agents: {} };
      }
    } catch (error) {
      if (error.code === 'ENOENT') {
        this.profiles = [];
        this.agentSettings = { agents: {} };
        await this.save();
      } else if (error instanceof SyntaxError) {
        this.profiles = [];
        this.agentSettings = { agents: {} };
        await this.save();
      } else {
        throw error;
      }
    }
  }

  /**
   * Return all profiles with keys masked for safe display.
   */
  list() {
    return this.profiles.map(maskProfile);
  }

  /**
   * Return all profiles with full (unmasked) keys. Internal use only.
   */
  listFull() {
    return [...this.profiles];
  }

  /**
   * Get a single profile by ID with full keys. Returns null if not found.
   */
  get(id) {
    return this.profiles.find((p) => p.id === id) || null;
  }

  /**
   * Get the currently active profile (isCurrent === true) with full keys.
   * Returns null if no profile is active.
   */
  getActive() {
    return this.profiles.find((p) => p.isCurrent === true) || null;
  }

  /**
   * Create a new profile. If it's the first profile, it becomes active
   * automatically.
   */
  async create({ name, keys }) {
    if (!name || typeof name !== 'string') {
      throw Object.assign(new Error('Profile name is required'), { statusCode: 400 });
    }

    const isFirst = this.profiles.length === 0;
    const profile = {
      id: crypto.randomUUID(),
      name,
      isCurrent: isFirst,
      keys: keys && typeof keys === 'object' ? keys : {},
      createdAt: Date.now(),
    };

    this.profiles.push(profile);
    await this.save();
    return profile;
  }

  /**
   * Update fields on an existing profile. Only known fields are patched.
   * Returns the updated profile or null if not found.
   */
  async update(id, patch) {
    const profile = this.get(id);
    if (!profile) return null;

    if (patch.name !== undefined) profile.name = patch.name;
    if (patch.keys !== undefined && typeof patch.keys === 'object') {
      // Merge keys: only overwrite providers that are explicitly provided.
      // Others keep their existing values.
      if (!profile.keys) profile.keys = {};
      for (const [provider, entry] of Object.entries(patch.keys)) {
        if (!entry || typeof entry !== 'object') continue;
        const existing = profile.keys[provider] || {};
        profile.keys[provider] = {
          ...existing,
          ...(entry.key ? { key: entry.key } : {}),
          ...(entry.baseUrl !== undefined ? { baseUrl: entry.baseUrl } : {}),
        };
      }
    }
    await this.save();
    return profile;
  }

  /**
   * Delete a profile by ID. Returns true if deleted, false if not found.
   */
  async delete(id) {
    const index = this.profiles.findIndex((p) => p.id === id);
    if (index === -1) return false;

    const wasActive = this.profiles[index].isCurrent;
    this.profiles.splice(index, 1);

    // If the deleted profile was active and others remain, activate the first.
    if (wasActive && this.profiles.length > 0) {
      this.profiles[0].isCurrent = true;
    }

    await this.save();
    return true;
  }

  /**
   * Set a profile as the active one. Deactivates all others.
   * Returns the activated profile or null if not found.
   */
  async activate(id) {
    const target = this.get(id);
    if (!target) return null;

    for (const profile of this.profiles) {
      profile.isCurrent = profile.id === id;
    }

    await this.save();
    return target;
  }

  /**
   * From the active profile, return the { key, baseUrl } for a given provider.
   * Returns null if no active profile or provider not configured.
   */
  getKeyForProvider(provider) {
    const active = this.getActive();
    if (!active || !active.keys || !active.keys[provider]) return null;
    const entry = active.keys[provider];
    return { key: entry.key || null, baseUrl: entry.baseUrl || null };
  }

  getKeyForProviderById(profileId, provider) {
    const profile = profileId ? this.get(profileId) : this.getActive();
    if (!profile || !profile.keys || !profile.keys[provider]) return null;
    const entry = profile.keys[provider];
    return { key: entry.key || null, baseUrl: entry.baseUrl || null };
  }

  getDefaultModel(agentId) {
    return this.getAgentSettings(agentId).defaultModel;
  }

  getAgentProfileId(agentId) {
    return this.getAgentSettings(agentId).profileId;
  }

  getAgentSettings(agentId) {
    const settings = this.agentSettings.agents[agentId] || {};
    return {
      profileId: settings.profileId || null,
      defaultModel: settings.defaultModel || null,
    };
  }

  listAgentSettings(agentIds = []) {
    const ids = new Set([
      ...agentIds,
      ...Object.keys(this.agentSettings.agents || {}),
    ]);
    return [...ids].map((agentId) => ({
      agentId,
      ...this.getAgentSettings(agentId),
    }));
  }

  async updateAgentSettings(agentId, patch) {
    if (!agentId || typeof agentId !== 'string') {
      throw Object.assign(new Error('agentId is required'), { statusCode: 400 });
    }
    const current = this.getAgentSettings(agentId);
    const next = { ...current };
    if (Object.prototype.hasOwnProperty.call(patch, 'profileId')) {
      if (patch.profileId !== null && typeof patch.profileId !== 'string') {
        throw Object.assign(new Error('profileId must be a string or null'), { statusCode: 400 });
      }
      if (patch.profileId && !this.get(patch.profileId)) {
        throw Object.assign(new Error('profile not found'), { statusCode: 404 });
      }
      next.profileId = patch.profileId || null;
    }
    if (Object.prototype.hasOwnProperty.call(patch, 'defaultModel')) {
      if (patch.defaultModel !== null && typeof patch.defaultModel !== 'string') {
        throw Object.assign(new Error('defaultModel must be a string or null'), { statusCode: 400 });
      }
      next.defaultModel = patch.defaultModel || null;
    }
    this.agentSettings.agents[agentId] = next;
    await this.save();
    return this.getAgentSettings(agentId);
  }

  /**
   * Persist profiles to disk using atomic write (temp file + rename).
   * Serializes concurrent save calls to prevent corruption.
   */
  async save() {
    const run = this.saveQueue.then(
      () => this._writeSnapshot(),
      () => this._writeSnapshot(),
    );
    this.saveQueue = run.catch(() => {});
    return run;
  }

  /** @private */
  async _writeSnapshot() {
    await fs.mkdir(path.dirname(this.file), { recursive: true });
    const temp = `${this.file}.${process.pid}.${crypto.randomUUID()}.tmp`;
    try {
      await fs.writeFile(
        temp,
        `${JSON.stringify(
          {
            profiles: this.profiles,
            agentSettings: this.agentSettings,
          },
          null,
          2,
        )}\n`,
        'utf8',
      );
      await fs.rename(temp, this.file);
    } catch (error) {
      // Clean up temp file on failure.
      await fs.unlink(temp).catch(() => {});
      throw error;
    }
  }
}

function normalizeAgentSettings(value) {
  const settings = { agents: {} };
  const agents = value && typeof value === 'object' && value.agents && typeof value.agents === 'object'
    ? value.agents
    : {};
  for (const [agentId, entry] of Object.entries(agents)) {
    if (!entry || typeof entry !== 'object') continue;
    settings.agents[agentId] = {
      profileId: typeof entry.profileId === 'string' ? entry.profileId : null,
      defaultModel: typeof entry.defaultModel === 'string' ? entry.defaultModel : null,
    };
  }
  return settings;
}

module.exports = { ProfileStore, maskProfile };
