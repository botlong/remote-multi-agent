'use strict';

const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

const {
  commandExists,
  killProcessTree,
  readLines,
  resolveClaudeCommand,
  resolveCodexCommand,
  resolveOpenCodeCommand,
  runCapture,
  spawnCli,
} = require('./cli');
const { OpenCodeServerManager } = require('./opencode_server');

const CODEX_COMMANDS = [
  '/permissions',
  '/ide',
  '/keymap',
  '/vim',
  '/sandbox-add-read-dir',
  '/agent',
  '/apps',
  '/plugins',
  '/hooks',
  '/clear',
  '/compact',
  '/copy',
  '/diff',
  '/exit',
  '/quit',
  '/experimental',
  '/approve',
  '/memories',
  '/skills',
  '/feedback',
  '/init',
  '/logout',
  '/mcp',
  '/mention',
  '/model',
  '/fast',
  '/plan',
  '/goal',
  '/personality',
  '/ps',
  '/stop',
  '/fork',
  '/side',
  '/raw',
  '/status',
  '/debug-config',
];

const CLAUDE_COMMANDS = [
  '/add-dir',
  '/agents',
  '/bug',
  '/clear',
  '/compact',
  '/config',
  '/cost',
  '/doctor',
  '/help',
  '/init',
  '/login',
  '/logout',
  '/mcp',
  '/memory',
  '/model',
  '/permissions',
  '/pr_comments',
  '/review',
  '/status',
  '/terminal-setup',
  '/vim',
];

const OPENCODE_COMMANDS = [
  '/help',
  '/editor',
  '/export',
  '/new',
  '/clear',
  '/sessions',
  '/resume',
  '/continue',
  '/share',
  '/unshare',
  '/compact',
  '/summarize',
  '/details',
  '/models',
  '/themes',
  '/init',
  '/undo',
  '/redo',
  '/exit',
  '/quit',
  '/q',
];

class AgentRegistry {
  constructor({ openCodeServer } = {}) {
    this.adapters = new Map(
      [
        new CodexAdapter(),
        new ClaudeCodeAdapter(),
        new OpenCodeAdapter({ server: openCodeServer }),
      ].map((adapter) => [adapter.id, adapter]),
    );
  }

  get(agentId) {
    return this.adapters.get(agentId) || null;
  }

  async list(projectDirectory) {
    return Promise.all(
      [...this.adapters.values()].map((adapter) => adapter.metadata(projectDirectory)),
    );
  }

  close() {
    for (const adapter of this.adapters.values()) {
      adapter.close?.();
    }
  }
}

class CodexAdapter {
  constructor() {
    this.id = 'codex';
    this.displayName = 'Codex';
    this.command = resolveCodexCommand();
  }

  async metadata(projectDirectory) {
    return {
      id: this.id,
      displayName: this.displayName,
      supportsModels: true,
      supportsSlashCommands: true,
      supportsAttachments: false,
      supportsPermissions: true,
      sessionKind: 'thread',
      commands: commands(CODEX_COMMANDS),
      raw: {
        available: commandExists(this.command),
        command: publicCommand(this.command),
        projectDirectory,
      },
    };
  }

  async models() {
    const result = await runCapture(this.command, ['debug', 'models', '--bundled']);
    if (result.exitCode === 0) {
      try {
        const parsed = JSON.parse(result.stdout);
        const models = Array.isArray(parsed.models) ? parsed.models : [];
        return models
          .filter((model) => model.visibility !== 'hidden')
          .map((model) => ({
            id: model.slug,
            displayName: model.display_name || model.slug,
            raw: compactCodexModel(model),
          }));
      } catch (_) {
        // Fall through to static list.
      }
    }
    return [
      'gpt-5.5',
      'gpt-5.4',
      'gpt-5.4-mini',
      'gpt-5.3-codex',
      'gpt-5.2',
    ].map((id) => ({ id, displayName: id, raw: { id } }));
  }

  async commands() {
    return commands(CODEX_COMMANDS);
  }

  run({ session, prompt, onEvent, onText, onAgentSessionId, onExit }) {
    const args = session.agentSessionId
      ? ['exec', 'resume', '--json']
      : [
          'exec',
          '--json',
          '--color',
          'never',
          '--cd',
          session.directory,
          '--sandbox',
          process.env.CODEX_SANDBOX || 'workspace-write',
          '--skip-git-repo-check',
        ];
    if (session.modelId) args.push('--model', session.modelId);
    if (session.agentSessionId) args.push(session.agentSessionId);
    args.push('-');
    return runJsonCli({
      command: this.command,
      args,
      cwd: session.directory,
      stdin: prompt,
      agentId: this.id,
      onEvent,
      onText,
      onAgentSessionId,
      onExit,
    });
  }
}

class ClaudeCodeAdapter {
  constructor() {
    this.id = 'claude-code';
    this.displayName = 'Claude Code';
    this.command = resolveClaudeCommand();
  }

  async metadata(projectDirectory) {
    return {
      id: this.id,
      displayName: this.displayName,
      supportsModels: true,
      supportsSlashCommands: true,
      supportsAttachments: true,
      supportsPermissions: true,
      sessionKind: 'thread',
      commands: await this.commands(projectDirectory),
      raw: {
        available: commandExists(this.command),
        command: publicCommand(this.command),
        projectDirectory,
      },
    };
  }

  async models() {
    return (process.env.CLAUDE_CODE_MODELS || '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean)
      .map((id) => ({ id, displayName: id, raw: { id } }));
  }

  async commands(projectDirectory) {
    return commands([
      ...CLAUDE_COMMANDS,
      ...(await markdownCommands(path.join(projectDirectory || '', '.claude', 'commands'))),
      ...(await markdownCommands(path.join(os.homedir(), '.claude', 'commands'))),
    ]);
  }

  run({ session, prompt, onEvent, onText, onAgentSessionId, onExit }) {
    const args = [
      '-p',
      '--output-format',
      'stream-json',
      '--verbose',
      '--include-partial-messages',
    ];
    if (process.env.CLAUDE_CODE_PERMISSION_MODE) {
      args.push('--permission-mode', process.env.CLAUDE_CODE_PERMISSION_MODE);
    }
    if (session.modelId) args.push('--model', session.modelId);
    if (session.agentSessionId) args.push('--resume', session.agentSessionId);
    args.push(prompt);
    return runJsonCli({
      command: this.command,
      args,
      cwd: session.directory,
      stdin: null,
      agentId: this.id,
      onEvent,
      onText,
      onAgentSessionId,
      onExit,
    });
  }
}

class OpenCodeAdapter {
  constructor({ command, server } = {}) {
    this.id = 'opencode';
    this.displayName = 'OpenCode';
    this.command = command || resolveOpenCodeCommand();
    this.server = server || new OpenCodeServerManager({ command: this.command });
  }

  async metadata(projectDirectory) {
    return {
      id: this.id,
      displayName: this.displayName,
      supportsModels: true,
      supportsSlashCommands: true,
      supportsAttachments: true,
      supportsPermissions: true,
      sessionKind: 'session',
      commands: await this.commands(projectDirectory),
      raw: {
        available: commandExists(this.command) || Boolean(this.server.externalBaseUrl),
        command: publicCommand(this.command),
        serverUrl: this.server.baseUrl || this.server.externalBaseUrl || null,
        projectDirectory,
      },
    };
  }

  async models() {
    try {
      const providers = await this.server.request('/provider');
      const models = providerModels(providers);
      if (models.length > 0) return models;
    } catch (_) {
      // Fall back to the CLI's static model list when server mode is unavailable.
    }
    const result = await runCapture(this.command, ['models']);
    if (result.exitCode === 0) {
      return result.stdout
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter((line) => /^[^/\s]+\/[^/\s]+$/.test(line))
        .map((id) => ({ id, displayName: id, raw: { id } }));
    }
    return [{ id: 'opencode/big-pickle', displayName: 'opencode/big-pickle', raw: {} }];
  }

  async commands(projectDirectory) {
    return commands([
      ...OPENCODE_COMMANDS,
      ...(await markdownCommands(path.join(projectDirectory || '', '.opencode', 'commands'))),
      ...(await opencodeJsonCommands(projectDirectory)),
    ]);
  }

  async createSession({ project, title }) {
    const query = project?.directory
      ? `?directory=${encodeURIComponent(project.directory)}`
      : '';
    const raw = await this.server.request(`/session${query}`, {
      method: 'POST',
      body: {},
    });
    const agentSessionId = raw && typeof raw.id === 'string' ? raw.id : null;
    if (!agentSessionId) throw new Error('OpenCode did not return a session id');
    return {
      agentSessionId,
      title:
        typeof raw.title === 'string' && raw.title.trim()
          ? raw.title
          : title || 'OpenCode session',
      raw,
    };
  }

  async listMessages(session) {
    if (!session.agentSessionId) return null;
    return await this.server.request(
      `/session/${encodeURIComponent(session.agentSessionId)}/message`,
    );
  }

  async abort(session) {
    if (!session.agentSessionId) return false;
    await this.server.request(
      `/session/${encodeURIComponent(session.agentSessionId)}/abort`,
      { method: 'POST' },
    );
    return true;
  }

  async deleteSession(session) {
    if (!session.agentSessionId) return false;
    await this.server.request(
      `/session/${encodeURIComponent(session.agentSessionId)}`,
      { method: 'DELETE' },
    );
    return true;
  }

  async runNative({ session, prompt, parts = [], onEvent, onExit }) {
    if (!session.agentSessionId) return null;

    const abortController = new AbortController();
    let settled = false;
    let sent = false;
    let completionTimer = null;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(completionTimer);
      abortController.abort();
      onExit(result);
    };
    const markCompletedSoon = (result = { exitCode: 0 }) => {
      clearTimeout(completionTimer);
      completionTimer = setTimeout(() => finish(result), 250);
    };

    const stream = this.server.openEventStream({
      signal: abortController.signal,
      onEvent: (raw, eventName) => {
        const event = normalizeOpenCodeEvent(raw, eventName);
        if (!event) return;
        const remoteSessionId = openCodeEventSessionId(raw);
        if (remoteSessionId && remoteSessionId !== session.agentSessionId) return;
        onEvent(event);
        const terminal = openCodeTerminalResult(raw);
        if (terminal) markCompletedSoon(terminal);
      },
    });
    await stream.opened;

    const { providerId, modelId } = splitOpenCodeModel(session.modelId);
    const messageParts = [
      ...(prompt.trim() ? [{ type: 'text', text: prompt }] : []),
      ...parts.filter((part) => part && typeof part === 'object'),
    ];
    sent = true;
    this.server
      .request(`/session/${encodeURIComponent(session.agentSessionId)}/message`, {
        method: 'POST',
        body: {
          providerID: providerId,
          modelID: modelId,
          mode: process.env.OPENCODE_MODE || 'build',
          parts: messageParts,
        },
        signal: abortController.signal,
      })
      .then(() => {})
      .catch((error) => {
        if (!abortController.signal.aborted) {
          finish({ exitCode: -1, error: error.message });
        }
      });
    stream.done.catch((error) => {
      if (!abortController.signal.aborted && sent) {
        finish({ exitCode: -1, error: error.message });
      }
    });

    return {
      pid: null,
      abort: () => {
        this.abort(session).catch(() => {});
        finish({ exitCode: -1, error: 'aborted' });
      },
    };
  }

  run({ session, prompt, onEvent, onText, onAgentSessionId, onExit }) {
    const args = ['run', '--format', 'json', '--dir', session.directory];
    if (session.modelId) args.push('--model', session.modelId);
    if (session.agentSessionId) args.push('--session', session.agentSessionId);
    args.push(prompt);
    return runJsonCli({
      command: this.command,
      args,
      cwd: session.directory,
      stdin: null,
      agentId: this.id,
      onEvent,
      onText,
      onAgentSessionId,
      onExit,
    });
  }

  close() {
    this.server.close?.();
  }
}

function providerModels(payload) {
  const all = Array.isArray(payload?.all) ? payload.all : [];
  const out = [];
  for (const provider of all) {
    if (!provider || typeof provider !== 'object') continue;
    const providerId = provider.id || provider.providerID;
    if (!providerId) continue;
    const providerName = provider.name || providerId;
    const models = provider.models || {};
    for (const [modelId, model] of Object.entries(models)) {
      out.push({
        id: `${providerId}/${modelId}`,
        displayName: `${providerName} / ${model?.name || modelId}`,
        raw: compactOpenCodeModel(providerId, modelId, model),
      });
    }
  }
  return out;
}

function compactOpenCodeModel(providerId, modelId, model) {
  return {
    providerID: providerId,
    modelID: modelId,
    name: model?.name,
    toolCall: model?.tool_call,
    attachment: model?.attachment,
    reasoning: model?.reasoning,
    limit: model?.limit,
  };
}

function splitOpenCodeModel(value) {
  const fallback = process.env.OPENCODE_DEFAULT_MODEL || 'opencode/big-pickle';
  const text = String(value || fallback);
  const slash = text.indexOf('/');
  if (slash === -1) {
    return {
      providerId: process.env.OPENCODE_DEFAULT_PROVIDER || 'opencode',
      modelId: text,
    };
  }
  return {
    providerId: text.slice(0, slash),
    modelId: text.slice(slash + 1),
  };
}

function normalizeOpenCodeEvent(raw, eventName = 'message') {
  if (!raw || typeof raw !== 'object') return null;
  const type = raw.type || eventName;
  const properties = raw.properties || raw.data || {};
  switch (type) {
    case 'message.updated': {
      const info = properties.info || raw.info || raw.message || null;
      return {
        type,
        data: info ? { info } : properties,
        raw,
      };
    }
    case 'message.part.updated': {
      const part = properties.part || raw.part || null;
      return {
        type,
        data: part ? { part } : properties,
        raw,
      };
    }
    case 'message.part.delta':
      return {
        type,
        data: {
          sessionID: properties.sessionID || raw.sessionID,
          messageID: properties.messageID || raw.messageID,
          partID: properties.partID || raw.partID,
          field: properties.field || raw.field || 'text',
          delta: properties.delta ?? raw.delta ?? '',
        },
        raw,
      };
    case 'session.updated':
      return {
        type: 'status.updated',
        data: {
          status: 'running',
          source: 'opencode',
          eventType: type,
          session: properties.info || properties.session || raw.session || properties,
        },
        raw,
      };
    case 'session.error':
      return {
        type,
        data: { error: openCodeErrorMessage(raw) },
        raw,
      };
    case 'session.idle':
      return {
        type: 'status.updated',
        data: {
          status: 'idle',
          source: 'opencode',
          eventType: type,
          session: properties.info || properties.session || raw.session || properties,
        },
        raw,
      };
    default:
      return {
        type: 'command.updated',
        data: { source: 'opencode', eventType: type, properties },
        raw,
      };
  }
}

function openCodeEventSessionId(raw) {
  const properties = raw.properties || raw.data || {};
  return (
    properties.sessionID ||
    raw.sessionID ||
    properties.sessionId ||
    raw.sessionId ||
    properties.session?.id ||
    raw.session?.id ||
    properties.info?.sessionID ||
    raw.info?.sessionID ||
    raw.message?.sessionID ||
    properties.part?.sessionID ||
    raw.part?.sessionID ||
    (String(raw.type || '').startsWith('session.') ? properties.info?.id : null) ||
    null
  );
}

function openCodeTerminalResult(raw) {
  const type = raw?.type;
  const properties = raw?.properties || raw?.data || {};
  const info = properties.info || raw?.info || raw?.message || {};
  if (type === 'session.error') {
    return { exitCode: -1, error: openCodeErrorMessage(raw) };
  }
  if (info.status === 'error') {
    return { exitCode: -1, error: openCodeErrorMessage(raw) };
  }
  if (type === 'session.idle' || type === 'session.completed') {
    return { exitCode: 0 };
  }
  if (info.role === 'assistant' && info.status === 'completed') {
    return { exitCode: 0 };
  }
  return null;
}

function openCodeErrorMessage(raw) {
  const properties = raw?.properties || raw?.data || {};
  const error = properties.error || raw?.error || {};
  return error.message || raw?.message || 'OpenCode error';
}

function runJsonCli({
  command,
  args,
  cwd,
  stdin,
  agentId,
  onEvent,
  onText,
  onAgentSessionId,
  onExit,
}) {
  let child;
  try {
    child = spawnCli(command, args, { cwd });
  } catch (error) {
    onExit({
      exitCode: -1,
      error: error.message,
    });
    return {
      pid: null,
      abort() {},
    };
  }
  const state = {
    lastFullTextByKey: new Map(),
    sawText: false,
    stderrLines: [],
  };
  readLines(child.stdout, (line) => {
    const raw = parseJsonLine(line);
    if (!raw) {
      onText(line.endsWith('\n') ? line : `${line}\n`);
      return;
    }
    const eventType = raw.type || raw.event || 'cli.event';
    onEvent({
      type: 'command.updated',
      data: { stream: 'stdout', eventType },
      raw,
    });
    const agentSessionId = extractAgentSessionId(raw);
    if (agentSessionId) onAgentSessionId(agentSessionId, raw);
    const delta = extractTextDelta(raw, state);
    if (delta) {
      state.sawText = true;
      onText(delta);
    }
  });
  readLines(child.stderr, (line) => {
    state.stderrLines.push(line);
    if (state.stderrLines.length > 80) state.stderrLines.shift();
    onEvent({
      type: 'command.updated',
      data: { stream: 'stderr', text: line },
      raw: { line },
    });
  });
  if (stdin !== null && stdin !== undefined) {
    child.stdin.end(stdin);
  } else {
    child.stdin.end();
  }
  let settled = false;
  const finish = (result) => {
    if (settled) return;
    settled = true;
    onExit(result);
  };
  child.on('error', (error) => {
    finish({
      exitCode: -1,
      error: error.message,
    });
  });
  child.on('close', (exitCode) => {
    const stderr = state.stderrLines.join('\n').trim();
    finish({
      exitCode,
      error: exitCode === 0 ? null : stderr || `agent exited with code ${exitCode}`,
    });
  });
  return {
    pid: child.pid,
    abort() {
      killProcessTree(child);
    },
  };
}

function extractTextDelta(raw, state) {
  if (typeof raw.delta === 'string') return raw.delta;
  if (typeof raw.text_delta === 'string') return raw.text_delta;
  if (typeof raw.content_delta === 'string') return raw.content_delta;

  const properties = raw.properties || raw.data || {};
  const part = properties.part || raw.part;
  if (part && typeof part.text === 'string') {
    return suffixDelta(`part:${part.id || raw.type || 'text'}`, part.text, state);
  }

  if (raw.type === 'assistant' && raw.message) {
    const text = contentArrayText(raw.message.content);
    if (text) return suffixDelta('claude:assistant', text, state);
  }

  if (raw.item && raw.item.role === 'assistant') {
    const text = contentArrayText(raw.item.content);
    if (text) return suffixDelta(`item:${raw.item.id || raw.type || 'assistant'}`, text, state);
  }

  if (raw.message && raw.message.role === 'assistant') {
    const text =
      typeof raw.message.content === 'string'
        ? raw.message.content
        : contentArrayText(raw.message.content);
    if (text) return suffixDelta(`message:${raw.message.id || raw.type || 'assistant'}`, text, state);
  }

  if (raw.role === 'assistant') {
    const text =
      typeof raw.content === 'string' ? raw.content : contentArrayText(raw.content);
    if (text) return suffixDelta(`assistant:${raw.id || raw.type || 'content'}`, text, state);
  }

  if (!state.sawText && typeof raw.result === 'string') return raw.result;
  return '';
}

function suffixDelta(key, fullText, state) {
  const previous = state.lastFullTextByKey.get(key) || '';
  state.lastFullTextByKey.set(key, fullText);
  if (!previous) return fullText;
  return fullText.startsWith(previous) ? fullText.slice(previous.length) : fullText;
}

function contentArrayText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .map((item) => {
      if (typeof item === 'string') return item;
      if (!item || typeof item !== 'object') return '';
      if (typeof item.text === 'string') return item.text;
      if (typeof item.content === 'string') return item.content;
      return '';
    })
    .join('');
}

function extractAgentSessionId(raw) {
  if (raw.thread_id) return raw.thread_id;
  if (raw.threadId) return raw.threadId;
  if (raw.session_id) return raw.session_id;
  if (raw.sessionId) return raw.sessionId;
  if (raw.conversation_id) return raw.conversation_id;
  if (raw.conversationId) return raw.conversationId;
  if (raw.id && /session|thread|conversation/.test(String(raw.type || ''))) {
    return raw.id;
  }
  return null;
}

function parseJsonLine(line) {
  try {
    const parsed = JSON.parse(line);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch (_) {
    return null;
  }
}

function commands(items) {
  const seen = new Set();
  const out = [];
  for (const item of items) {
    const name = typeof item === 'string' ? item : item.name;
    if (!name) continue;
    const normalized = name.startsWith('/') ? name : `/${name}`;
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    out.push({
      name: normalized,
      description: typeof item === 'object' ? item.description || '' : '',
    });
  }
  return out;
}

async function markdownCommands(directory) {
  if (!directory) return [];
  const entries = await fs.readdir(directory, { withFileTypes: true }).catch(() => []);
  const out = [];
  for (const entry of entries) {
    if (entry.isDirectory()) {
      const nested = await markdownCommands(path.join(directory, entry.name));
      out.push(...nested.map((command) => `${entry.name}:${command}`));
      continue;
    }
    if (!entry.name.endsWith('.md')) continue;
    out.push(entry.name.slice(0, -3));
  }
  return out;
}

async function opencodeJsonCommands(projectDirectory) {
  if (!projectDirectory) return [];
  const file = path.join(projectDirectory, 'opencode.json');
  try {
    const parsed = JSON.parse(await fs.readFile(file, 'utf8'));
    if (Array.isArray(parsed.commands)) {
      return parsed.commands.map((command) =>
        typeof command === 'string' ? command : command.name || command.id || '',
      );
    }
    if (parsed.commands && typeof parsed.commands === 'object') {
      return Object.keys(parsed.commands);
    }
  } catch (_) {
    // Ignore invalid or missing project config.
  }
  return [];
}

function publicCommand(command) {
  return {
    command: command.command,
    prefixArgs: command.prefixArgs || [],
    shell: Boolean(command.shell),
  };
}

function compactCodexModel(model) {
  return {
    id: model.slug,
    description: model.description,
    defaultReasoningLevel: model.default_reasoning_level,
    supportedReasoningLevels: model.supported_reasoning_levels,
    additionalSpeedTiers: model.additional_speed_tiers,
    serviceTiers: model.service_tiers,
  };
}

module.exports = {
  AgentRegistry,
  OpenCodeAdapter,
  normalizeOpenCodeEvent,
};
