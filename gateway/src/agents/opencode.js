'use strict';

const path = require('node:path');

const {
  commandExists,
  resolveOpenCodeCommand,
  runCapture,
} = require('../cli');
const { OpenCodeServerManager } = require('../opencode_server');
const { cachedModels } = require('./model_cache');
const { commands, markdownCommands, opencodeJsonCommands, publicCommand } = require('./command_helpers');
const { runJsonCli } = require('./json_cli');
const {
  providerModels,
  splitOpenCodeModel,
  normalizeOpenCodeEvent,
  openCodeEventSessionId,
  openCodeTerminalResult,
} = require('./opencode_helpers');

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

module.exports = {
  OpenCodeAdapter,
  OPENCODE_COMMANDS,
  normalizeOpenCodeEvent,
};
