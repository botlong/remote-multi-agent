'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { createGatewayServer } = require('../src/server');

test('gateway exposes projects, sessions, messages, and SSE events', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-gateway-'));
  const dataFile = path.join(root, 'store.json');
  const projectDir = path.join(root, 'project');
  await fs.mkdir(projectDir);

  const adapters = new FakeRegistry();
  const server = await createGatewayServer({ dataFile, adapters });
  await listen(server);
  t.after(() => {
    server.closeAllRuns?.();
    server.close();
  });

  const base = `http://127.0.0.1:${server.address().port}`;
  const project = await postJson(`${base}/projects`, { directory: projectDir });
  assert.equal(project.name, 'project');

  const agents = await getJson(`${base}/agents`);
  assert.equal(agents[0].id, 'fake');

  const session = await postJson(`${base}/projects/${project.id}/sessions`, {
    agentId: 'fake',
  });
  assert.equal(session.agentId, 'fake');

  const events = collectSseUntil(
    `${base}/sessions/${session.id}/events`,
    (event) => event.type === 'session.completed',
  );
  const accepted = await postJson(`${base}/sessions/${session.id}/messages`, {
    text: 'hello',
  });
  assert.equal(accepted.accepted, true);

  const received = await events;
  assert(received.some((event) => event.type === 'message.delta'));
  assert(received.some((event) => event.type === 'session.completed'));

  const messages = await getJson(`${base}/sessions/${session.id}/messages`);
  assert.equal(messages.length, 2);
  assert.equal(messages[1].parts[0].text, 'fake response');
});

class FakeRegistry {
  constructor() {
    this.adapter = new FakeAdapter();
  }

  get(agentId) {
    return agentId === 'fake' ? this.adapter : null;
  }

  async list() {
    return [await this.adapter.metadata()];
  }
}

class FakeAdapter {
  constructor() {
    this.id = 'fake';
    this.displayName = 'Fake';
  }

  async metadata() {
    return {
      id: 'fake',
      displayName: 'Fake',
      supportsModels: false,
      supportsSlashCommands: false,
      supportsAttachments: false,
      supportsPermissions: false,
      sessionKind: 'thread',
      commands: [],
    };
  }

  async models() {
    return [];
  }

  async commands() {
    return [];
  }

  run({ onText, onExit }) {
    setImmediate(async () => {
      await onText('fake response');
      onExit({ exitCode: 0 });
    });
    return {
      abort() {},
    };
  }
}

function listen(server) {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', resolve);
  });
}

async function getJson(url) {
  const response = await fetch(url);
  const text = await response.text();
  assert.equal(response.ok, true, text);
  if (!text) return null;
  return JSON.parse(text);
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  assert.equal(response.ok, true, text);
  if (!text) return null;
  return JSON.parse(text);
}

async function collectSseUntil(url, predicate) {
  const response = await fetch(url);
  assert.equal(response.ok, true);
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  const events = [];
  let buffer = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    let index;
    while ((index = buffer.indexOf('\n\n')) !== -1) {
      const block = buffer.slice(0, index);
      buffer = buffer.slice(index + 2);
      const data = block
        .split(/\r?\n/)
        .filter((line) => line.startsWith('data:'))
        .map((line) => line.slice(5).trimStart())
        .join('\n');
      if (data) {
        const event = JSON.parse(data);
        events.push(event);
        if (predicate(event)) {
          await reader.cancel();
          return events;
        }
      }
    }
  }
  return events;
}
