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
  { name: '/mcp', description: 'Show MCP server status' },
  { name: '/personality', description: 'Set personality' },
  { name: '/review', description: 'Code review' },
  { name: '/side', description: 'Start a side conversation in a temporary branch' },
  { name: '/compact', description: 'Compress this thread context' },
  { name: '/feedback', description: 'Submit feedback' },
  { name: '/model', description: 'Switch model' },
  { name: '/fast', description: 'Switch to fast model' },
  { name: '/plan', description: 'Plan a goal' },
  { name: '/goal', description: 'Set a goal for the session' },
  { name: '/fork', description: 'Fork to local branch or new worktree' },
  { name: '/status', description: 'Show session ID, context usage, and rate limits' },
  { name: '/permissions', description: 'Manage sandbox permissions' },
  { name: '/sandbox-add-read-dir', description: 'Add a read-only directory to sandbox' },
  { name: '/ide', description: 'IDE integration settings' },
  { name: '/keymap', description: 'Switch keymap' },
  { name: '/vim', description: 'Toggle vim mode' },
  { name: '/agent', description: 'Manage agents' },
  { name: '/apps', description: 'Manage apps' },
  { name: '/plugins', description: 'Manage plugins' },
  { name: '/hooks', description: 'Manage hooks' },
  { name: '/clear', description: 'Clear screen' },
  { name: '/copy', description: 'Copy last response' },
  { name: '/diff', description: 'Show diff of changes' },
  { name: '/experimental', description: 'Toggle experimental features' },
  { name: '/approve', description: 'Approve pending actions' },
  { name: '/memories', description: 'View or manage memories' },
  { name: '/skills', description: 'View learned skills' },
  { name: '/init', description: 'Initialize project config' },
  { name: '/logout', description: 'Log out' },
  { name: '/mention', description: 'Mention a file or symbol' },
  { name: '/ps', description: 'Show running processes' },
  { name: '/stop', description: 'Stop running process' },
  { name: '/raw', description: 'Send raw prompt' },
  { name: '/debug-config', description: 'Show debug config' },
  { name: '/exit', description: 'Exit session' },
  { name: '/quit', description: 'Quit session' },
  { name: '$', description: 'Run a shell command' },
];

const CLAUDE_COMMANDS = [
  { name: '/mcp', description: 'Show MCP server status' },
  { name: '/model', description: 'Switch model' },
  { name: '/compact', description: 'Compress this thread context' },
  { name: '/review', description: 'Code review' },
  { name: '/memory', description: 'View or edit memory' },
  { name: '/status', description: 'Show session ID, context usage, and rate limits' },
  { name: '/permissions', description: 'Manage permissions' },
  { name: '/agents', description: 'Show available agents' },
  { name: '/bug', description: 'Report a bug' },
  { name: '/clear', description: 'Clear conversation' },
  { name: '/config', description: 'Show or edit config' },
  { name: '/cost', description: 'Show token usage and cost' },
  { name: '/doctor', description: 'Diagnose setup issues' },
  { name: '/help', description: 'Show help' },
  { name: '/init', description: 'Initialize project config' },
  { name: '/login', description: 'Log in' },
  { name: '/logout', description: 'Log out' },
  { name: '/pr_comments', description: 'Load PR comments' },
  { name: '/add-dir', description: 'Add a directory to context' },
  { name: '/terminal-setup', description: 'Setup terminal integration' },
  { name: '/vim', description: 'Toggle vim mode' },
];

const OPENCODE_COMMANDS = [
  { name: '/models', description: 'Show or switch models' },
  { name: '/compact', description: 'Compress this thread context' },
  { name: '/summarize', description: 'Summarize conversation' },
  { name: '/help', description: 'Show help' },
  { name: '/new', description: 'Start a new session' },
  { name: '/clear', description: 'Clear conversation' },
  { name: '/sessions', description: 'List sessions' },
  { name: '/resume', description: 'Resume a session' },
  { name: '/continue', description: 'Continue last session' },
  { name: '/share', description: 'Share session' },
  { name: '/unshare', description: 'Unshare session' },
  { name: '/details', description: 'Show session details' },
  { name: '/editor', description: 'Open in editor' },
  { name: '/export', description: 'Export conversation' },
  { name: '/themes', description: 'Change theme' },
  { name: '/init', description: 'Initialize project config' },
  { name: '/undo', description: 'Undo last change' },
  { name: '/redo', description: 'Redo last change' },
  { name: '/exit', description: 'Exit session' },
  { name: '/quit', description: 'Quit session' },
  { name: '/q', description: 'Quit session' },
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
    const args = buildCodexArgs(session);
    // Codex `exec ... -` reads the prompt from stdin until EOF; keeping
    // stdin open would block codex from starting work.
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

function buildCodexArgs(session) {
  const sandbox = (session.raw && session.raw.sandbox) || process.env.CODEX_SANDBOX || 'workspace-write';
  const args = session.agentSessionId
    ? ['exec', 'resume', '--json', '--skip-git-repo-check']
    : [
        'exec',
        '--json',
        '--color',
        'never',
        '--cd',
        session.directory,
        '--sandbox',
        sandbox,
        '--skip-git-repo-check',
      ];
  if (session.modelId) args.push('--model', session.modelId);
  if (session.agentSessionId) args.push(session.agentSessionId);
  args.push('-');
  return args;
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
    // 1. Explicit env var override
    const envModels = (process.env.CLAUDE_CODE_MODELS || '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean);
    if (envModels.length > 0) {
      return envModels.map((id) => ({ id, displayName: id, raw: { id } }));
    }

    // 2. Try fetching from Anthropic API
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (apiKey) {
      try {
        const baseUrl = (process.env.ANTHROPIC_BASE_URL || 'https://api.anthropic.com').replace(/\/+$/, '');
        const res = await fetch(`${baseUrl}/v1/models`, {
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
          },
          signal: AbortSignal.timeout(8000),
        });
        if (res.ok) {
          const body = await res.json();
          const models = (body.data || [])
            .filter((m) => m.id && /claude/i.test(m.id))
            .sort((a, b) => {
              // Newest first (by created_at if available)
              const ca = a.created_at || '';
              const cb = b.created_at || '';
              return cb.localeCompare(ca);
            })
            .map((m) => ({
              id: m.id,
              displayName: m.display_name || m.id,
              raw: m,
            }));
          if (models.length > 0) return models;
        }
      } catch (err) {
        console.warn(`[claude-code] Failed to fetch models from API: ${err.message}`);
      }
    }

    // 3. Fallback defaults
    const defaults = [
      'claude-sonnet-4-20250514',
      'claude-opus-4-20250514',
      'claude-3-7-sonnet-20250219',
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
    ];
    return defaults.map((id) => ({ id, displayName: id, raw: { id } }));
  }

  async commands(projectDirectory) {
    return commands([
      ...CLAUDE_COMMANDS,
      ...(await markdownCommands(path.join(projectDirectory || '', '.claude', 'commands'))),
      ...(await markdownCommands(path.join(os.homedir(), '.claude', 'commands'))),
    ]);
  }

  run({ session, prompt, onEvent, onText, onAgentSessionId, onExit }) {
    return this._runOnce({
      session,
      prompt,
      withResume: Boolean(session.agentSessionId),
      onEvent,
      onText,
      onAgentSessionId,
      onExit,
    });
  }

  _runOnce({ session, prompt, withResume, onEvent, onText, onAgentSessionId, onExit }) {
    const args = [
      '-p',
      '--output-format',
      'stream-json',
      '--verbose',
      '--include-partial-messages',
    ];
    // Claude `-p` (print) mode cannot prompt interactively. If we don't pass
    // a permission-mode it defaults to "ask" and stalls waiting for input.
    // 'acceptEdits' is the closest match to Codex's 'workspace-write' default.
    const permissionMode = (session.raw && session.raw.permissionMode) ||
      process.env.CLAUDE_CODE_PERMISSION_MODE ||
      'acceptEdits';
    args.push('--permission-mode', permissionMode);
    if (session.modelId) args.push('--model', session.modelId);
    if (withResume && session.agentSessionId) {
      args.push('--resume', session.agentSessionId);
    }
    args.push(prompt);

    let retried = false;
    const handle = {};
    const wrappedExit = (result) => {
      // Detect stale --resume: Claude says "No conversation found".
      const stale = withResume &&
        !retried &&
        typeof result.error === 'string' &&
        /no conversation found/i.test(result.error);
      if (stale) {
        retried = true;
        console.log(`[claude] stale resume id ${session.agentSessionId} - retrying fresh`);
        session.agentSessionId = null;
        const retryHandle = this._runOnce({
          session,
          prompt,
          withResume: false,
          onEvent,
          onText,
          onAgentSessionId,
          onExit,
        });
        Object.assign(handle, retryHandle);
        return;
      }
      onExit(result);
    };

    const inner = runJsonCli({
      command: this.command,
      args,
      cwd: session.directory,
      stdin: null,
      agentId: this.id,
      onEvent,
      onText,
      onAgentSessionId,
      onExit: wrappedExit,
    });
    Object.assign(handle, inner);
    return handle;
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

  async injectMessage(session, text, parts = []) {
    if (!session.agentSessionId) return false;
    const { providerId, modelId } = splitOpenCodeModel(session.modelId);
    const messageParts = [
      ...(text.trim() ? [{ type: 'text', text }] : []),
      ...parts.filter((part) => part && typeof part === 'object'),
    ];
    await this.server.request(
      `/session/${encodeURIComponent(session.agentSessionId)}/message`,
      {
        method: 'POST',
        body: {
          providerID: providerId,
          modelID: modelId,
          mode: (session.raw && session.raw.permissionMode) || process.env.OPENCODE_MODE || 'build',
          parts: messageParts,
        },
      },
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
          mode: (session.raw && session.raw.permissionMode) || process.env.OPENCODE_MODE || 'build',
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
  const configured = [];
  const unconfigured = [];
  for (const provider of all) {
    if (!provider || typeof provider !== 'object') continue;
    const providerId = provider.id || provider.providerID;
    if (!providerId) continue;
    const providerName = provider.name || providerId;
    const models = provider.models || {};
    // A provider is "configured" if it has an API key or env set
    const isConfigured = Boolean(
      provider.configured || provider.apiKey || provider.api_key || provider.env,
    );
    const target = isConfigured ? configured : unconfigured;
    for (const [modelId, model] of Object.entries(models)) {
      target.push({
        id: `${providerId}/${modelId}`,
        displayName: `${providerName} / ${model?.name || modelId}`,
        raw: compactOpenCodeModel(providerId, modelId, model),
      });
    }
  }
  // Configured providers first, then unconfigured
  return [...configured, ...unconfigured];
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
  keepStdinOpen = false,
  agentId,
  onEvent,
  onText,
  onToolCall,
  onUsage,
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
    if (onToolCall) {
      const toolCall = extractToolCall(raw);
      if (toolCall) onToolCall(toolCall);
    }
    if (onUsage) {
      const usage = extractUsage(raw);
      if (usage) onUsage(usage);
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
    child.stdin.write(stdin + '\n');
  }
  // Close stdin unless the adapter wants to keep it open for later injection
  // (e.g. Codex which reads more lines from stdin as the user types).
  // Otherwise CLIs like Claude/OpenCode wait for EOF and emit
  // 'no stdin data received in 3s' warnings.
  if (!keepStdinOpen && child.stdin.writable) {
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
    write(text) {
      if (!settled && child.stdin.writable) {
        child.stdin.write(text + '\n');
        return true;
      }
      return false;
    },
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

  if (raw.item && typeof raw.item.text === 'string' && raw.item.text) {
    return suffixDelta(`item:${raw.item.id || raw.type || 'agent_message'}`, raw.item.text, state);
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

/**
 * Extract tool call info from agent JSON events.
 *
 * Codex:   { type: 'function_call', name: '...', arguments: '...' }
 *          or item.content[].type === 'function_call'
 * Claude:  { type: 'tool_use', name: '...', input: { ... } }
 *          or content[].type === 'tool_use'
 * OpenCode: handled natively via SSE part events.
 */
function extractToolCall(raw) {
  // Codex function_call at top level
  if (raw.type === 'function_call' && raw.name) {
    return {
      name: raw.name,
      input: tryParseJson(raw.arguments) || raw.arguments || '',
      status: raw.status || 'running',
      callId: raw.call_id,
    };
  }
  // Codex function_call_output
  if (raw.type === 'function_call_output') {
    return {
      name: raw.name || 'function_call',
      output: raw.output,
      status: 'completed',
      callId: raw.call_id,
    };
  }
  // Claude tool_use in content array
  if (raw.type === 'content_block_start' && raw.content_block?.type === 'tool_use') {
    return {
      name: raw.content_block.name,
      input: '',
      status: 'running',
      toolUseId: raw.content_block.id,
    };
  }
  if (raw.type === 'tool_use' && raw.name) {
    return {
      name: raw.name,
      input: raw.input || {},
      status: 'running',
      toolUseId: raw.id,
    };
  }
  if (raw.type === 'tool_result') {
    return {
      name: raw.name || 'tool',
      output: raw.content,
      status: raw.is_error ? 'error' : 'completed',
      toolUseId: raw.tool_use_id,
    };
  }
  // Codex item-level tool calls
  if (raw.item && Array.isArray(raw.item.content)) {
    for (const block of raw.item.content) {
      if (block.type === 'function_call' && block.name) {
        return {
          name: block.name,
          input: block.arguments || '',
          status: block.status || 'completed',
          callId: block.call_id,
        };
      }
    }
  }
  return null;
}

/**
 * Extract token usage info from agent JSON events.
 * Returns { inputTokens, outputTokens, totalTokens } or null.
 */
function extractUsage(raw) {
  // OpenAI / Codex: { usage: { input_tokens, output_tokens, total_tokens } }
  const usage = raw.usage || raw.token_usage;
  if (usage && typeof usage === 'object') {
    const input = usage.input_tokens || usage.prompt_tokens || 0;
    const output = usage.output_tokens || usage.completion_tokens || 0;
    const total = usage.total_tokens || input + output;
    if (total > 0) return { inputTokens: input, outputTokens: output, totalTokens: total };
  }
  // Claude: { message: { usage: ... } }
  if (raw.message?.usage) {
    const u = raw.message.usage;
    const input = u.input_tokens || 0;
    const output = u.output_tokens || 0;
    return { inputTokens: input, outputTokens: output, totalTokens: input + output };
  }
  // response.completed with usage at top level
  if (raw.type === 'response.completed' && raw.response?.usage) {
    const u = raw.response.usage;
    const input = u.input_tokens || u.prompt_tokens || 0;
    const output = u.output_tokens || u.completion_tokens || 0;
    return { inputTokens: input, outputTokens: output, totalTokens: input + output };
  }
  return null;
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

function tryParseJson(value) {
  if (typeof value !== 'string') return null;
  try {
    const parsed = JSON.parse(value);
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
    const normalized = name.startsWith('/') || name.startsWith('$') ? name : `/${name}`;
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
  buildCodexArgs,
  OpenCodeAdapter,
  normalizeOpenCodeEvent,
  runJsonCli,
};
