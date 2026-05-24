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

test('Codex full access sessions bypass approvals and sandbox', () => {
  const args = buildCodexArgs({
    directory: 'D:\\Code\\WorkSpace\\AgentLens',
    modelId: 'gpt-5.5',
    agentSessionId: '',
    raw: { sandbox: 'danger-full-access' },
  });

  assert(args.includes('--dangerously-bypass-approvals-and-sandbox'));
  assert.equal(args.includes('--sandbox'), false);
  assert.deepEqual(args.slice(-3), ['--model', 'gpt-5.5', '-']);
});

test('Codex resume preserves full access bypass', () => {
  const args = buildCodexArgs({
    directory: 'D:\\Code\\WorkSpace\\AgentLens',
    modelId: 'gpt-5.5',
    agentSessionId: 'session-123',
    raw: { sandbox: 'danger-full-access' },
  });

  assert.deepEqual(args.slice(0, 5), [
    'exec',
    'resume',
    '--json',
    '--dangerously-bypass-approvals-and-sandbox',
    '--skip-git-repo-check',
  ]);
  assert.deepEqual(args.slice(-4), ['--model', 'gpt-5.5', 'session-123', '-']);
});

test('Codex legacy full-auto sandbox maps to full access bypass', () => {
  const args = buildCodexArgs({
    directory: 'D:\\Code\\WorkSpace\\AgentLens',
    modelId: 'gpt-5.5',
    agentSessionId: '',
    raw: { sandbox: 'full-auto' },
  });

  assert(args.includes('--dangerously-bypass-approvals-and-sandbox'));
  assert.equal(args.includes('full-auto'), false);
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

test('runJsonCli emits activity for function call lifecycle', async () => {
  const script = [
    'console.log(JSON.stringify({type:"function_call",call_id:"call-1",name:"shell",arguments:JSON.stringify({command:"npm test"}),status:"running"}));',
    'console.log(JSON.stringify({type:"function_call_output",call_id:"call-1",output:"ok\\n"}));',
    'process.exit(0);',
  ].join('');
  const activities = [];
  const result = await new Promise((resolve) => {
    runJsonCli({
      command: { command: process.execPath },
      args: ['-e', script],
      cwd: process.cwd(),
      stdin: null,
      onEvent: (event) => {
        if (event.type === 'activity.updated') {
          activities.push(event.data.activity);
        }
      },
      onText: () => {},
      onExit: resolve,
    });
  });
  assert.equal(result.exitCode, 0);
  assert.equal(activities.length, 2);
  assert.equal(activities[0].id, 'call-1');
  assert.equal(activities[0].kind, 'command');
  assert.equal(activities[0].status, 'running');
  assert.equal(activities[0].command, 'npm test');
  assert.equal(activities[1].id, 'call-1');
  assert.equal(activities[1].kind, 'command');
  assert.equal(activities[1].status, 'completed');
  assert.equal(activities[1].title, 'Ran npm test');
  assert.equal(activities[1].outputDelta, 'ok\n');
});

test('runJsonCli emits activity for stderr lines', async () => {
  const script = 'console.error("warning line");process.exit(0);';
  const activities = [];
  const result = await new Promise((resolve) => {
    runJsonCli({
      command: { command: process.execPath },
      args: ['-e', script],
      cwd: process.cwd(),
      stdin: null,
      onEvent: (event) => {
        if (event.type === 'activity.updated') {
          activities.push(event.data.activity);
        }
      },
      onText: () => {},
      onExit: resolve,
    });
  });
  assert.equal(result.exitCode, 0);
  assert.equal(activities.length, 1);
  assert.equal(activities[0].kind, 'output');
  assert.equal(activities[0].status, 'info');
  assert.equal(activities[0].stream, 'stderr');
  assert.equal(activities[0].outputDelta, 'warning line\n');
});
