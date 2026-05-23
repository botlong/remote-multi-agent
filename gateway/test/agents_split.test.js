'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

test('agent facade exports registry and adapter utilities', () => {
  const agents = require('../src/agents');

  assert.equal(typeof agents.AgentRegistry, 'function');
  assert.equal(typeof agents.CodexAdapter, 'function');
  assert.equal(typeof agents.ClaudeCodeAdapter, 'function');
  assert.equal(typeof agents.OpenCodeAdapter, 'function');
  assert.equal(typeof agents.buildCodexArgs, 'function');
  assert.equal(typeof agents.normalizeOpenCodeEvent, 'function');
  assert.equal(typeof agents.runJsonCli, 'function');
});

test('each agent adapter is importable from its dedicated file', () => {
  const { CodexAdapter, buildCodexArgs } = require('../src/agents/codex');
  const { ClaudeCodeAdapter } = require('../src/agents/claude_code');
  const { OpenCodeAdapter } = require('../src/agents/opencode');

  assert.equal(new CodexAdapter().id, 'codex');
  assert.equal(new ClaudeCodeAdapter().id, 'claude-code');
  assert.equal(new OpenCodeAdapter({
    server: {
      externalBaseUrl: 'http://127.0.0.1:1234',
      baseUrl: null,
      request() {
        throw new Error('not used');
      },
      close() {},
    },
  }).id, 'opencode');

  assert.deepEqual(
    buildCodexArgs({
      directory: 'D:\\Code\\WorkSpace\\remote-multi-agent',
      modelId: 'gpt-5.3-codex',
      agentSessionId: null,
      raw: { sandbox: 'workspace-write' },
    }),
    [
      'exec',
      '--json',
      '--color',
      'never',
      '--cd',
      'D:\\Code\\WorkSpace\\remote-multi-agent',
      '--sandbox',
      'workspace-write',
      '--skip-git-repo-check',
      '--model',
      'gpt-5.3-codex',
      '-',
    ],
  );
});
