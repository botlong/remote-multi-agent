'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { buildCodexArgs, runJsonCli } = require('../src/agents');

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

test('runJsonCli closes stdin by default so one-shot CLIs see EOF', async () => {
  // Script that exits with code 0 only if stdin sees EOF, else hangs.
  const script =
    'process.stdin.resume();' +
    'process.stdin.on("end",()=>{console.log(JSON.stringify({type:"done"}));process.exit(0)});' +
    'setTimeout(()=>process.exit(1),1500);';
  const result = await new Promise((resolve) => {
    runJsonCli({
      command: { command: process.execPath },
      args: ['-e', script],
      cwd: process.cwd(),
      stdin: null,
      onEvent: () => {},
      onText: () => {},
      onExit: resolve,
    });
  });
  assert.equal(result.exitCode, 0, `expected EOF-driven exit, got ${result.exitCode}`);
});

test('runJsonCli with keepStdinOpen keeps stdin writable after initial prompt', async () => {
  // Script reads first line then exits cleanly.
  const script =
    'let buf="";process.stdin.on("data",(c)=>{buf+=c;if(buf.includes("\\n")){' +
    'console.log(JSON.stringify({type:"got",line:buf.trim()}));process.exit(0)}});';
  const result = await new Promise((resolve) => {
    runJsonCli({
      command: { command: process.execPath },
      args: ['-e', script],
      cwd: process.cwd(),
      stdin: 'hello',
      keepStdinOpen: true,
      onEvent: () => {},
      onText: () => {},
      onExit: resolve,
    });
  });
  assert.equal(result.exitCode, 0);
});

test('runJsonCli does not duplicate assistant snapshots after text deltas', async () => {
  const script = [
    'console.log(JSON.stringify({delta:"Hello"}));',
    'console.log(JSON.stringify({type:"assistant",message:{content:[{text:"Hello"}]}}));',
    'process.exit(0);',
  ].join('');
  const chunks = [];
  const result = await new Promise((resolve) => {
    runJsonCli({
      command: { command: process.execPath },
      args: ['-e', script],
      cwd: process.cwd(),
      stdin: null,
      onEvent: () => {},
      onText: (text) => chunks.push(text),
      onExit: resolve,
    });
  });
  assert.equal(result.exitCode, 0);
  assert.deepEqual(chunks, ['Hello']);
});
