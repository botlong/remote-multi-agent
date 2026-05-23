'use strict';

const os = require('node:os');
const path = require('node:path');

const {
  commandExists,
  resolveClaudeCommand,
  resolveCodexCommand,
  resolveOpenCodeCommand,
  runCapture,
} = require('./cli');
const { OpenCodeServerManager } = require('./opencode_server');
const { cachedModels } = require('./agents/model_cache');
const {
  commands,
  markdownCommands,
  opencodeJsonCommands,
  publicCommand,
} = require('./agents/command_helpers');
const { runJsonCli } = require('./agents/json_cli');
const {
  providerModels,
  splitOpenCodeModel,
  normalizeOpenCodeEvent,
  openCodeEventSessionId,
  openCodeTerminalResult,
} = require('./agents/opencode_helpers');

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
  constructor({ openCodeServer, profileStore } = {}) {
    this.profileStore = profileStore || null;
    this.adapters = new Map(
      [
        new CodexAdapter({ profileStore }),
        new ClaudeCodeAdapter({ profileStore }),
        new OpenCodeAdapter({ server: openCodeServer, profileStore }),
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
  constructor({ profileStore } = {}) {
    this.id = 'codex';
    this.displayName = 'Codex';
    this.command = resolveCodexCommand();
    this.profileStore = profileStore || null;
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

  models() {
    return cachedModels('codex', () => this._fetchModels());
  }

  async _fetchModels() {
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

    const profileKey = this.profileStore?.getKeyForProviderById(
      session.raw?.profileId, 'openai');
    const extraEnv = {};
    if (profileKey?.key) {
      extraEnv.OPENAI_API_KEY = profileKey.key;
      if (profileKey.baseUrl) extraEnv.OPENAI_BASE_URL = profileKey.baseUrl;
    }

    // Codex `exec ... -` reads the prompt from stdin until EOF; keeping
    // stdin open would block codex from starting work.
    return runJsonCli({
      command: this.command,
      args,
      cwd: session.directory,
      env: extraEnv,
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
  constructor({ profileStore } = {}) {
    this.id = 'claude-code';
    this.displayName = 'Claude Code';
    this.command = resolveClaudeCommand();
    this.profileStore = profileStore || null;
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

  models() {
    return cachedModels("claude-code", () => this._fetchModels());
  }

  async _fetchModels() {
    // 1. Explicit env var override (list of model IDs, not credentials).
    const envModels = (process.env.CLAUDE_CODE_MODELS || '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean);
    if (envModels.length > 0) {
      return envModels.map((id) => ({ id, displayName: id, raw: { id } }));
    }

    // 2. Fetch from Anthropic API using the active profile's credentials.
    //    Credentials live only in the gateway profile store — no implicit
    //    fallback to env vars, CC-Switch, or ~/.claude/settings.json. To pull
    //    a live model list, the user must first import a profile via the
    //    /settings/credential-sources/* + /settings/profiles/import flow.
    const profileKey = this.profileStore?.getKeyForProvider('anthropic');
    const apiKey = profileKey?.key || null;
    const baseUrl = profileKey?.baseUrl || null;
    if (apiKey) {
      try {
        const url = (baseUrl || 'https://api.anthropic.com').replace(/\/+$/, '');
        const res = await fetch(`${url}/v1/models`, {
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
    const isSlashCommand = prompt.trim().startsWith('/');
    const withResume = Boolean(session.agentSessionId);
    if (isSlashCommand && !withResume) {
      onEvent({
        type: 'command.updated',
        data: { source: 'claude-code', eventType: 'slash-command', command: prompt.trim() },
        raw: { command: prompt.trim(), hasSession: false },
      });
    }
    return this._runOnce({
      session,
      prompt,
      withResume,
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

    const profileKey = this.profileStore?.getKeyForProviderById(
      session.raw?.profileId, 'anthropic');
    const extraEnv = {};
    if (profileKey?.key) {
      extraEnv.ANTHROPIC_API_KEY = profileKey.key;
      if (profileKey.baseUrl) extraEnv.ANTHROPIC_BASE_URL = profileKey.baseUrl;
    }

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
      env: extraEnv,
      stdin: prompt,
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
  constructor({ command, server, profileStore } = {}) {
    this.id = 'opencode';
    this.displayName = 'OpenCode';
    this.command = command || resolveOpenCodeCommand();
    this.profileStore = profileStore || null;
    this._explicitServer = server || null;
    this._server = null;
  }

  get server() {
    if (!this._server) {
      this._server = this._explicitServer || new OpenCodeServerManager({
        command: this.command,
        extraEnv: this._buildProfileEnv(),
      });
    }
    return this._server;
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

  models() {
    return cachedModels("opencode", () => this._fetchModels());
  }

  async _fetchModels() {
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
          directory: session.directory,
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
          directory: session.directory,
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

    const extraEnv = this._buildProfileEnv(session.raw?.profileId);

    return runJsonCli({
      command: this.command,
      args,
      cwd: session.directory,
      env: extraEnv,
      stdin: null,
      agentId: this.id,
      onEvent,
      onText,
      onAgentSessionId,
      onExit,
    });
  }

  _buildProfileEnv(profileId) {
    const extraEnv = {};
    const anthropicKey = this.profileStore?.getKeyForProviderById(profileId, 'anthropic');
    if (anthropicKey?.key) {
      extraEnv.ANTHROPIC_API_KEY = anthropicKey.key;
      if (anthropicKey.baseUrl) extraEnv.ANTHROPIC_BASE_URL = anthropicKey.baseUrl;
    }
    const openaiKey = this.profileStore?.getKeyForProviderById(profileId, 'openai');
    if (openaiKey?.key) {
      extraEnv.OPENAI_API_KEY = openaiKey.key;
      if (openaiKey.baseUrl) extraEnv.OPENAI_BASE_URL = openaiKey.baseUrl;
    }
    const googleKey = this.profileStore?.getKeyForProviderById(profileId, 'google');
    if (googleKey?.key) {
      extraEnv.GOOGLE_API_KEY = googleKey.key;
      if (googleKey.baseUrl) extraEnv.GOOGLE_BASE_URL = googleKey.baseUrl;
    }
    return extraEnv;
  }

  close() {
    this.server.close?.();
  }
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
