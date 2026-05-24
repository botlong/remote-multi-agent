'use strict';

const os = require('node:os');
const path = require('node:path');

const {
  commandExists,
  resolveClaudeCommand,
} = require('../cli');
const { cachedModels } = require('./model_cache');
const { commands, markdownCommands, publicCommand } = require('./command_helpers');
const { runJsonCli } = require('./json_cli');

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

  models(options = {}) {
    const profileId = options.profileId || 'none';
    return cachedModels(`claude-code:${profileId}`, () => this._fetchModels(options));
  }

  async _fetchModels(options = {}) {
    const envModels = (process.env.CLAUDE_CODE_MODELS || '')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean);
    if (envModels.length > 0) {
      return envModels.map((id) => ({ id, displayName: id, raw: { id } }));
    }

    const profileKey = this.profileStore?.getKeyForProviderById(options.profileId, 'anthropic');
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

  run({ session, prompt, onEvent, onText, onToolCall, onAgentSessionId, onExit }) {
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
      onToolCall,
      onAgentSessionId,
      onExit,
    });
  }

  _runOnce({ session, prompt, withResume, onEvent, onText, onToolCall, onAgentSessionId, onExit }) {
    const args = [
      '-p',
      '--output-format',
      'stream-json',
      '--verbose',
      '--include-partial-messages',
    ];
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
          onToolCall,
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
      onToolCall,
      onAgentSessionId,
      onExit: wrappedExit,
    });
    Object.assign(handle, inner);
    return handle;
  }
}

module.exports = {
  ClaudeCodeAdapter,
  CLAUDE_COMMANDS,
};
