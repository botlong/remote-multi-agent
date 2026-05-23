'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

class JsonStore {
  constructor(file) {
    this.file = file;
    this.saveQueue = Promise.resolve();
    this.data = {
      projects: [],
      sessions: [],
      messagesBySession: {},
    };
  }

  async load() {
    await fs.mkdir(path.dirname(this.file), { recursive: true });
    try {
      const raw = await fs.readFile(this.file, 'utf8');
      const parsed = JSON.parse(raw);
      this.data = {
        projects: Array.isArray(parsed.projects) ? parsed.projects : [],
        sessions: Array.isArray(parsed.sessions) ? parsed.sessions : [],
        messagesBySession:
          parsed.messagesBySession && typeof parsed.messagesBySession === 'object'
            ? parsed.messagesBySession
            : {},
      };
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
      await this.save();
    }
  }

  async save() {
    const run = this.saveQueue.then(
      () => this.writeSnapshot(),
      () => this.writeSnapshot(),
    );
    this.saveQueue = run.catch(() => {});
    return run;
  }

  /** Debounced save — coalesces rapid writes during streaming (500ms). */
  saveSoon() {
    if (this._saveTimer) return;
    this._saveTimer = setTimeout(() => {
      this._saveTimer = null;
      this.save().catch(() => {});
    }, 500);
  }

  async resetOrphaned() {
    for (const session of this.data.sessions) {
      if (session.status === 'running') {
        session.status = 'idle';
      }
    }
    for (const messages of Object.values(this.data.messagesBySession || {})) {
      if (!Array.isArray(messages)) continue;
      for (const msg of messages) {
        if (msg && msg.status === 'running') {
          msg.status = 'error';
          msg.time = msg.time || {};
          msg.time.completed = msg.time.completed || Date.now();
        }
      }
    }
    await this.save();
  }

  async writeSnapshot() {
    await fs.mkdir(path.dirname(this.file), { recursive: true });
    const temp = `${this.file}.${process.pid}.${crypto.randomUUID()}.tmp`;
    await fs.writeFile(temp, `${JSON.stringify(this.data, null, 2)}\n`, 'utf8');
    await fs.rename(temp, this.file);
  }

  listProjects() {
    return [...this.data.projects].sort((a, b) => b.updatedAt - a.updatedAt);
  }

  async createProject({ directory, name }) {
    const normalized = await normalizeDirectory(directory);
    const now = Date.now();
    const existing = this.data.projects.find(
      (project) => samePath(project.directory, normalized),
    );
    if (existing) {
      existing.name = name || existing.name || path.basename(normalized);
      existing.updatedAt = now;
      await this.save();
      return existing;
    }
    const project = {
      id: crypto.randomUUID(),
      name: name || path.basename(normalized) || normalized,
      directory: normalized,
      updatedAt: now,
    };
    this.data.projects.push(project);
    await this.save();
    return project;
  }

  getProject(projectId) {
    return this.data.projects.find((project) => project.id === projectId) || null;
  }

  async deleteProject(projectId) {
    this.data.projects = this.data.projects.filter(
      (project) => project.id !== projectId,
    );
    const removedSessions = this.data.sessions
      .filter((session) => session.projectId === projectId)
      .map((session) => session.id);
    this.data.sessions = this.data.sessions.filter(
      (session) => session.projectId !== projectId,
    );
    for (const sessionId of removedSessions) {
      delete this.data.messagesBySession[sessionId];
    }
    await this.save();
  }

  listSessions(projectId) {
    return this.data.sessions
      .filter((session) => session.projectId === projectId)
      .sort((a, b) => b.updatedAt - a.updatedAt);
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
    this.data.sessions.push(session);
    this.data.messagesBySession[session.id] = [];
    await this.save();
    return session;
  }

  getSession(sessionId) {
    return this.data.sessions.find((session) => session.id === sessionId) || null;
  }

  async updateSession(sessionId, patch) {
    const session = this.getSession(sessionId);
    if (!session) return null;
    for (const key of ['title', 'modelId', 'status', 'agentSessionId', 'agentId']) {
      if (Object.prototype.hasOwnProperty.call(patch, key)) {
        session[key] = patch[key];
      }
    }
    if (patch.raw && typeof patch.raw === 'object') {
      session.raw = { ...(session.raw || {}), ...patch.raw };
    }
    session.updatedAt = Date.now();
    await this.save();
    return session;
  }

  async deleteSession(sessionId) {
    this.data.sessions = this.data.sessions.filter(
      (session) => session.id !== sessionId,
    );
    delete this.data.messagesBySession[sessionId];
    await this.save();
  }

  listMessages(sessionId) {
    return [...(this.data.messagesBySession[sessionId] || [])];
  }

  async appendMessage(sessionId, message) {
    const list = this.data.messagesBySession[sessionId] || [];
    list.push(message);
    this.data.messagesBySession[sessionId] = list;
    await this.touchSession(sessionId);
    await this.save();
    return message;
  }

  async updateMessage(sessionId, messageId, updater) {
    const list = this.data.messagesBySession[sessionId] || [];
    const index = list.findIndex((message) => message.id === messageId);
    if (index === -1) return null;
    list[index] = updater(list[index]);
    await this.touchSession(sessionId, false);
    // Use debounced save — during streaming this is called per-token; coalesce.
    this.saveSoon();
    return list[index];
  }

  async deleteMessage(sessionId, messageId) {
    const list = this.data.messagesBySession[sessionId];
    if (!list) return false;
    const index = list.findIndex((m) => m.id === messageId);
    if (index === -1) return false;
    list.splice(index, 1);
    await this.touchSession(sessionId);
    await this.save();
    return true;
  }

  async touchSession(sessionId, save = false) {
    const session = this.getSession(sessionId);
    if (session) session.updatedAt = Date.now();
    if (save) await this.save();
  }
}

function createTextMessage({
  sessionId,
  role,
  text,
  status = 'completed',
  modelId,
}) {
  const now = Date.now();
  const id = crypto.randomUUID();
  const partId = `${id}_text`;
  const message = {
    id,
    role,
    sessionID: sessionId,
    status,
    time: {
      created: now,
      ...(status === 'completed' ? { completed: now } : {}),
    },
    parts: [
      {
        id: partId,
        messageID: id,
        sessionID: sessionId,
        type: 'text',
        text,
      },
    ],
  };
  if (modelId) message.modelID = modelId;
  return message;
}

function appendTextToMessage(message, delta) {
  if (!message.parts || message.parts.length === 0) {
    message.parts = [
      {
        id: `${message.id}_text`,
        messageID: message.id,
        sessionID: message.sessionID,
        type: 'text',
        text: '',
      },
    ];
  }
  message.parts[0].text = `${message.parts[0].text || ''}${delta}`;
  return message;
}

function appendToolPartToMessage(message, toolCall) {
  const partId = `${message.id}_tool_${toolCall.callId || toolCall.toolUseId || crypto.randomUUID()}`;
  // Check if this tool part already exists (update vs create).
  const existingIdx = message.parts.findIndex(
    (p) => p.type === 'tool' && p.toolCallId === (toolCall.callId || toolCall.toolUseId),
  );
  const rawInput = toolCall.input;
  const inputObj = typeof rawInput === 'string'
    ? (tryParseJsonSafe(rawInput) || (rawInput ? { command: rawInput } : null))
    : (rawInput && typeof rawInput === 'object' ? rawInput : null);
  const toolPart = {
    id: partId,
    messageID: message.id,
    sessionID: message.sessionID,
    type: 'tool',
    tool: toolCall.name,
    name: toolCall.name,
    input: inputObj,
    output: toolCall.output ?? null,
    status: toolCall.status || 'running',
    toolCallId: toolCall.callId || toolCall.toolUseId || null,
  };
  if (existingIdx >= 0) {
    // Merge: keep existing input if new one is empty, append output.
    const existing = message.parts[existingIdx];
    toolPart.id = existing.id;
    if (!toolPart.input && existing.input) toolPart.input = existing.input;
    if (existing.output && toolPart.output) {
      toolPart.output = existing.output + toolPart.output;
    } else if (existing.output) {
      toolPart.output = existing.output;
    }
    message.parts[existingIdx] = toolPart;
  } else {
    message.parts.push(toolPart);
  }
  return message;
}

function completeMessage(message, status = 'completed') {
  message.status = status;
  message.time = {
    ...(message.time || {}),
    completed: Date.now(),
  };
  return message;
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

async function browseDirectories(targetPath) {
  const root = targetPath ? path.resolve(targetPath) : defaultDirectoryRoot();
  const stat = await fs.stat(root).catch(() => null);
  if (!stat || !stat.isDirectory()) {
    throw Object.assign(new Error(`directory does not exist: ${root}`), {
      statusCode: 400,
    });
  }
  const entries = await fs.readdir(root, { withFileTypes: true });
  const dirs = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    dirs.push({
      name: entry.name,
      path: path.join(root, entry.name),
    });
  }
  return {
    path: root,
    dirs: dirs.sort((a, b) => a.name.localeCompare(b.name)),
  };
}

async function mkdir(targetPath) {
  if (!targetPath || typeof targetPath !== 'string') {
    throw Object.assign(new Error('path is required'), { statusCode: 400 });
  }
  await fs.mkdir(path.resolve(targetPath), { recursive: true });
  return { path: path.resolve(targetPath) };
}

function defaultDirectoryRoot() {
  if (process.platform === 'win32') {
    return process.env.SystemDrive ? `${process.env.SystemDrive}\\` : 'C:\\';
  }
  return os.homedir();
}

function samePath(a, b) {
  const left = path.resolve(a);
  const right = path.resolve(b);
  return process.platform === 'win32'
    ? left.toLowerCase() === right.toLowerCase()
    : left === right;
}

function defaultDirectories(store) {
  const configured = (process.env.GATEWAY_DIRECTORIES || '')
    .split(path.delimiter)
    .map((item) => item.trim())
    .filter(Boolean);
  return Array.from(
    new Set([
      ...configured,
      ...store.listProjects().map((project) => project.directory),
      process.cwd(),
      os.homedir(),
    ]),
  );
}

function tryParseJsonSafe(value) {
  if (typeof value !== 'string') return null;
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch (_) {
    return null;
  }
}

module.exports = {
  JsonStore,
  appendTextToMessage,
  appendToolPartToMessage,
  browseDirectories,
  completeMessage,
  createTextMessage,
  defaultDirectories,
  mkdir,
};
