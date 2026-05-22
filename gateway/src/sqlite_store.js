'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

/**
 * SQLite-backed store — drop-in replacement for JsonStore.
 *
 * Requires Node 22+ (node:sqlite). Enable with env GATEWAY_STORE=sqlite.
 * Data is stored at ~/.remote-multi-agent/gateway.db by default
 * (override with GATEWAY_DB_PATH).
 */
class SqliteStore {
  constructor(dbPath) {
    this.dbPath = dbPath || path.join(os.homedir(), '.remote-multi-agent', 'gateway.db');
    this.db = null;
  }

  async load() {
    await fs.mkdir(path.dirname(this.dbPath), { recursive: true });
    let DatabaseSync;
    try {
      ({ DatabaseSync } = require('node:sqlite'));
    } catch {
      throw new Error('node:sqlite not available — upgrade to Node 22+ or use GATEWAY_STORE=json');
    }
    this.db = new DatabaseSync(this.dbPath);
    this.db.exec('PRAGMA journal_mode=WAL');
    this.db.exec('PRAGMA foreign_keys=ON');
    this._migrate();
  }

  _migrate() {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        directory TEXT NOT NULL UNIQUE,
        updatedAt INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS sessions (
        id TEXT PRIMARY KEY,
        projectId TEXT NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        directory TEXT,
        agentId TEXT NOT NULL,
        modelId TEXT,
        title TEXT NOT NULL DEFAULT 'New session',
        status TEXT NOT NULL DEFAULT 'idle',
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        agentSessionId TEXT,
        raw TEXT DEFAULT '{}'
      );
      CREATE INDEX IF NOT EXISTS idx_sessions_project ON sessions(projectId);
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        sessionId TEXT NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        ordering INTEGER NOT NULL,
        data TEXT NOT NULL
      );
      CREATE INDEX IF NOT EXISTS idx_messages_session ON messages(sessionId, ordering);
    `);
  }

  // ── Projects ───────────────────────────────────────────────────────────

  listProjects() {
    return this.db
      .prepare('SELECT id, name, directory, updatedAt FROM projects ORDER BY updatedAt DESC')
      .all();
  }

  async createProject({ directory, name }) {
    const normalized = await normalizeDirectory(directory);
    const now = Date.now();
    const existing = this.db
      .prepare('SELECT id, name, directory, updatedAt FROM projects WHERE LOWER(directory) = LOWER(?)')
      .get(normalized);
    if (existing) {
      this.db.prepare('UPDATE projects SET name = ?, updatedAt = ? WHERE id = ?')
        .run(name || existing.name, now, existing.id);
      return { ...existing, name: name || existing.name, updatedAt: now };
    }
    const project = {
      id: crypto.randomUUID(),
      name: name || path.basename(normalized) || normalized,
      directory: normalized,
      updatedAt: now,
    };
    this.db.prepare('INSERT INTO projects (id, name, directory, updatedAt) VALUES (?, ?, ?, ?)')
      .run(project.id, project.name, project.directory, project.updatedAt);
    return project;
  }

  getProject(projectId) {
    return this.db.prepare('SELECT * FROM projects WHERE id = ?').get(projectId) || null;
  }

  async deleteProject(projectId) {
    this.db.prepare('DELETE FROM projects WHERE id = ?').run(projectId);
  }

  // ── Sessions ───────────────────────────────────────────────────────────

  listSessions(projectId) {
    const rows = this.db
      .prepare('SELECT * FROM sessions WHERE projectId = ? ORDER BY updatedAt DESC')
      .all(projectId);
    return rows.map(this._deserializeSession);
  }

  async createSession({ project, agentId, modelId, title, agentSessionId, raw }) {
    const now = Date.now();
    const session = {
      id: crypto.randomUUID(),
      projectId: project.id,
      directory: project.directory,
      agentId,
      modelId: modelId || null,
      title: title || 'New session',
      status: 'idle',
      createdAt: now,
      updatedAt: now,
      agentSessionId: agentSessionId || null,
      raw: raw && typeof raw === 'object' ? raw : {},
    };
    this.db.prepare(
      `INSERT INTO sessions (id, projectId, directory, agentId, modelId, title, status, createdAt, updatedAt, agentSessionId, raw)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(
      session.id, session.projectId, session.directory, session.agentId,
      session.modelId, session.title, session.status, session.createdAt,
      session.updatedAt, session.agentSessionId, JSON.stringify(session.raw),
    );
    return session;
  }

  getSession(sessionId) {
    const row = this.db.prepare('SELECT * FROM sessions WHERE id = ?').get(sessionId);
    return row ? this._deserializeSession(row) : null;
  }

  async updateSession(sessionId, patch) {
    const session = this.getSession(sessionId);
    if (!session) return null;
    for (const key of ['title', 'modelId', 'status', 'agentSessionId']) {
      if (Object.prototype.hasOwnProperty.call(patch, key)) {
        session[key] = patch[key];
      }
    }
    if (patch.raw && typeof patch.raw === 'object') {
      session.raw = { ...(session.raw || {}), ...patch.raw };
    }
    session.updatedAt = Date.now();
    this.db.prepare(
      `UPDATE sessions SET title=?, modelId=?, status=?, agentSessionId=?, raw=?, updatedAt=? WHERE id=?`
    ).run(
      session.title, session.modelId, session.status, session.agentSessionId,
      JSON.stringify(session.raw), session.updatedAt, session.id,
    );
    return session;
  }

  async deleteSession(sessionId) {
    this.db.prepare('DELETE FROM sessions WHERE id = ?').run(sessionId);
  }

  // ── Messages ───────────────────────────────────────────────────────────

  listMessages(sessionId) {
    const rows = this.db
      .prepare('SELECT data FROM messages WHERE sessionId = ? ORDER BY ordering')
      .all(sessionId);
    return rows.map(row => JSON.parse(row.data));
  }

  async appendMessage(sessionId, message) {
    const maxRow = this.db
      .prepare('SELECT MAX(ordering) as m FROM messages WHERE sessionId = ?')
      .get(sessionId);
    const ordering = (maxRow?.m ?? -1) + 1;
    this.db.prepare('INSERT INTO messages (id, sessionId, ordering, data) VALUES (?, ?, ?, ?)')
      .run(message.id, sessionId, ordering, JSON.stringify(message));
    await this.touchSession(sessionId);
    return message;
  }

  async updateMessage(sessionId, messageId, updater) {
    const row = this.db
      .prepare('SELECT data FROM messages WHERE id = ? AND sessionId = ?')
      .get(messageId, sessionId);
    if (!row) return null;
    const updated = updater(JSON.parse(row.data));
    this.db.prepare('UPDATE messages SET data = ? WHERE id = ?')
      .run(JSON.stringify(updated), messageId);
    await this.touchSession(sessionId, false);
    return updated;
  }

  async deleteMessage(sessionId, messageId) {
    const info = this.db.prepare('DELETE FROM messages WHERE id = ? AND sessionId = ?')
      .run(messageId, sessionId);
    if (info.changes === 0) return false;
    await this.touchSession(sessionId);
    return true;
  }

  async touchSession(sessionId, save = false) {
    this.db.prepare('UPDATE sessions SET updatedAt = ? WHERE id = ?')
      .run(Date.now(), sessionId);
  }

  _deserializeSession(row) {
    return {
      ...row,
      raw: row.raw ? JSON.parse(row.raw) : {},
    };
  }

  // Compatibility: JsonStore exposes a save() — noop for SQLite
  async save() {}
}

async function normalizeDirectory(directory) {
  if (!directory || typeof directory !== 'string') {
    throw Object.assign(new Error('directory is required'), { statusCode: 400 });
  }
  const resolved = path.resolve(directory);
  const stat = await fs.stat(resolved).catch(() => null);
  if (!stat || !stat.isDirectory()) {
    throw Object.assign(new Error(`directory does not exist: ${resolved}`), {
      statusCode: 400,
    });
  }
  return fs.realpath(resolved);
}

module.exports = { SqliteStore };
