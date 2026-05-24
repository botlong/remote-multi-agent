'use strict';

const {
  commandExists,
  resolveCodexCommand,
  runCapture,
} = require('../cli');
const { cachedModels } = require('./model_cache');
const { commands, publicCommand } = require('./command_helpers');
const { runJsonCli } = require('./json_cli');
const { fetchOpenAICompatibleModels } = require('./openai_compatible_models');

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

  models(options = {}) {
    const profileId = options.profileId || 'none';
    return cachedModels(`codex:${profileId}`, () => this._fetchModels(options));
  }

  async _fetchModels(options = {}) {
    const profileKey = this.profileStore?.getKeyForProviderById(
      options.profileId, 'openai');
    if (profileKey?.key) {
      try {
        const models = await fetchOpenAICompatibleModels({
          apiKey: profileKey.key,
          baseUrl: profileKey.baseUrl,
        });
        if (models.length > 0) return models;
      } catch (err) {
        console.warn(`[codex] Failed to fetch models from OpenAI profile: ${err.message}`);
      }
    }

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
  const sandbox = normalizeCodexSandbox(
    (session.raw && session.raw.sandbox) || process.env.CODEX_SANDBOX,
  );
  const bypassSandbox = sandbox === 'danger-full-access';
  const args = session.agentSessionId
    ? ['exec', 'resume', '--json']
    : [
        'exec',
        '--json',
        '--color',
        'never',
        '--cd',
        session.directory,
      ];
  if (bypassSandbox) {
    args.push('--dangerously-bypass-approvals-and-sandbox');
  } else if (!session.agentSessionId) {
    args.push('--sandbox', sandbox);
  }
  args.push('--skip-git-repo-check');
  if (session.modelId) args.push('--model', session.modelId);
  if (session.agentSessionId) args.push(session.agentSessionId);
  args.push('-');
  return args;
}

function normalizeCodexSandbox(value) {
  switch (value) {
    case 'read-only':
    case 'workspace-write':
    case 'danger-full-access':
      return value;
    case 'full-auto':
    case 'bypassPermissions':
      return 'danger-full-access';
    default:
      return 'workspace-write';
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
  CodexAdapter,
  CODEX_COMMANDS,
  buildCodexArgs,
  normalizeCodexSandbox,
};
