'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { buildCodexArgs } = require('../src/agents');

test('Codex new sessions skip git repository checks', () => {
  const args = buildCodexArgs({
    directory: 'D:\\Code\\WorkSpace\\AgentLens',
    modelId: 'gpt-5.5',
    agentSessionId: '',
  });

  assert.equal(args[0], 'exec');
  assert(args.includes('--skip-git-repo-check'));
  assert.deepEqual(args.slice(-3), ['--model', 'gpt-5.5', '-']);
});

test('Codex resumed sessions skip git repository checks', () => {
  const args = buildCodexArgs({
    directory: 'D:\\Code\\WorkSpace\\AgentLens',
    modelId: 'gpt-5.5',
    agentSessionId: 'session-123',
  });

  assert.deepEqual(args.slice(0, 4), [
    'exec',
    'resume',
    '--json',
    '--skip-git-repo-check',
  ]);
  assert.deepEqual(args.slice(-4), ['--model', 'gpt-5.5', 'session-123', '-']);
});
