'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { createGatewayServer } = require('../src/server');
const { OpenCodeAdapter } = require('../src/agents');

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

test('gateway proxies OpenCode sessions through server API and SSE', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-opencode-'));
  const dataFile = path.join(root, 'store.json');
  const projectDir = path.join(root, 'project');
  await fs.mkdir(projectDir);

  const fakeOpenCode = new FakeOpenCodeServer();
  const adapters = new SingleAdapterRegistry(
    new OpenCodeAdapter({
      command: { command: 'missing-opencode', prefixArgs: [], shell: false },
      server: fakeOpenCode,
    }),
  );
  const server = await createGatewayServer({ dataFile, adapters });
  await listen(server);
  t.after(() => {
    server.closeAllRuns?.();
    server.close();
  });

  const base = `http://127.0.0.1:${server.address().port}`;
  const project = await postJson(`${base}/projects`, { directory: projectDir });
  const models = await getJson(`${base}/agents/opencode/models`);
  assert.equal(models.models[0].id, 'anthropic/claude-sonnet-4');

  const session = await postJson(`${base}/projects/${project.id}/sessions`, {
    agentId: 'opencode',
    modelId: 'anthropic/claude-sonnet-4',
  });
  assert.equal(session.agentSessionId, 'oc-1');

  const events = collectSseUntil(
    `${base}/sessions/${session.id}/events`,
    (event) => event.type === 'session.completed',
  );
  const accepted = await postJson(`${base}/sessions/${session.id}/messages`, {
    text: 'hello',
    parts: [{ type: 'file', path: 'README.md' }],
  });
  assert.equal(accepted.accepted, true);

  const received = await events;
  assert(received.some((event) => event.type === 'message.updated'));
  assert(received.some((event) => event.type === 'message.part.delta'));
  assert(received.some((event) => event.type === 'message.completed'));
  assert.equal(fakeOpenCode.sentMessages[0].providerID, 'anthropic');
  assert.equal(fakeOpenCode.sentMessages[0].modelID, 'claude-sonnet-4');
  assert.deepEqual(fakeOpenCode.sentMessages[0].parts, [
    { type: 'text', text: 'hello' },
    { type: 'file', path: 'README.md' },
  ]);

  const messages = await getJson(`${base}/sessions/${session.id}/messages`);
  assert.equal(messages[0].info.id, 'oc-message-1');
  assert.equal(messages[0].parts[0].text, 'native response');

  const deleted = await deleteJson(`${base}/sessions/${session.id}`);
  assert.equal(deleted.ok, true);
  assert.equal(fakeOpenCode.deletedSessionId, 'oc-1');
});

test('OpenCode abort delegates to native server when no local run is active', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-opencode-abort-'));
  const dataFile = path.join(root, 'store.json');
  const projectDir = path.join(root, 'project');
  await fs.mkdir(projectDir);

  const fakeOpenCode = new FakeOpenCodeServer();
  const adapters = new SingleAdapterRegistry(
    new OpenCodeAdapter({
      command: { command: 'missing-opencode', prefixArgs: [], shell: false },
      server: fakeOpenCode,
    }),
  );
  const server = await createGatewayServer({ dataFile, adapters });
  await listen(server);
  t.after(() => {
    server.closeAllRuns?.();
    server.close();
  });

  const base = `http://127.0.0.1:${server.address().port}`;
  const project = await postJson(`${base}/projects`, { directory: projectDir });
  const session = await postJson(`${base}/projects/${project.id}/sessions`, {
    agentId: 'opencode',
  });

  const aborted = await postJson(`${base}/sessions/${session.id}/abort`, {});
  assert.equal(aborted.ok, true);
  assert.equal(fakeOpenCode.abortedSessionId, 'oc-1');
});

test('aborting an active run returns the session to idle without error state', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-gateway-abort-'));
  const dataFile = path.join(root, 'store.json');
  const projectDir = path.join(root, 'project');
  await fs.mkdir(projectDir);

  const adapters = new FakeRegistry(new HangingAdapter());
  const server = await createGatewayServer({ dataFile, adapters });
  await listen(server);
  t.after(() => {
    server.closeAllRuns?.();
    server.close();
  });

  const base = `http://127.0.0.1:${server.address().port}`;
  const project = await postJson(`${base}/projects`, { directory: projectDir });
  const session = await postJson(`${base}/projects/${project.id}/sessions`, {
    agentId: 'fake',
  });

  await postJson(`${base}/sessions/${session.id}/messages`, { text: 'wait' });
  const aborted = await postJson(`${base}/sessions/${session.id}/abort`, {});
  assert.equal(aborted.ok, true);

  const updated = await getJson(`${base}/sessions/${session.id}`);
  assert.equal(updated.status, 'idle');
  assert.equal(updated.raw.lastAborted, true);
  assert.notEqual(updated.status, 'error');
});

test('gateway stores CLI stderr when an adapter exits with an error', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-gateway-error-'));
  const dataFile = path.join(root, 'store.json');
  const projectDir = path.join(root, 'project');
  await fs.mkdir(projectDir);

  const adapters = new FakeRegistry(new FailingAdapter());
  const server = await createGatewayServer({ dataFile, adapters });
  await listen(server);
  t.after(() => {
    server.closeAllRuns?.();
    server.close();
  });

  const base = `http://127.0.0.1:${server.address().port}`;
  const project = await postJson(`${base}/projects`, { directory: projectDir });
  const session = await postJson(`${base}/projects/${project.id}/sessions`, {
    agentId: 'fake',
  });

  const events = collectSseUntil(
    `${base}/sessions/${session.id}/events`,
    (event) => event.type === 'session.error',
  );
  await postJson(`${base}/sessions/${session.id}/messages`, { text: 'fail' });
  const received = await events;
  assert(received.some((event) => event.type === 'message.delta'));

  const updated = await getJson(`${base}/sessions/${session.id}`);
  assert.equal(updated.status, 'error');
  assert.equal(updated.raw.lastExitCode, 2);
  assert.equal(updated.raw.lastError, 'cli usage error');

  const messages = await getJson(`${base}/sessions/${session.id}/messages`);
  assert.equal(messages[1].status, 'error');
  assert.equal(messages[1].parts[0].text, 'cli usage error');
});

test('gateway startup marks orphaned running messages as error', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-gateway-recover-'));
  const dataFile = path.join(root, 'store.json');
  const projectDir = path.join(root, 'project');
  await fs.mkdir(projectDir);
  await fs.writeFile(
    dataFile,
    JSON.stringify(
      {
        projects: [
          {
            id: 'p1',
            name: 'project',
            directory: projectDir,
            updatedAt: 1,
          },
        ],
        sessions: [
          {
            id: 's1',
            projectId: 'p1',
            directory: projectDir,
            agentId: 'fake',
            title: 'Recover me',
            status: 'running',
            createdAt: 1,
            updatedAt: 1,
            raw: {},
          },
        ],
        messagesBySession: {
          s1: [
            {
              id: 'm1',
              role: 'assistant',
              sessionID: 's1',
              status: 'running',
              time: { created: 1 },
              parts: [
                {
                  id: 'm1_text',
                  messageID: 'm1',
                  sessionID: 's1',
                  type: 'text',
                  text: '',
                },
              ],
            },
          ],
        },
      },
      null,
      2,
    ),
    'utf8',
  );

  const server = await createGatewayServer({ dataFile, adapters: new FakeRegistry() });
  await listen(server);
  t.after(() => {
    server.closeAllRuns?.();
    server.close();
  });

  const base = `http://127.0.0.1:${server.address().port}`;
  const session = await getJson(`${base}/sessions/s1`);
  assert.equal(session.status, 'idle');

  const messages = await getJson(`${base}/sessions/s1/messages`);
  assert.equal(messages[0].status, 'error');
  assert.equal(typeof messages[0].time.completed, 'number');
});

class SingleAdapterRegistry {
  constructor(adapter) {
    this.adapter = adapter;
  }

  get(agentId) {
    return agentId === this.adapter.id ? this.adapter : null;
  }

  async list() {
    return [await this.adapter.metadata()];
  }

  close() {
    this.adapter.close?.();
  }
}

class FakeRegistry {
  constructor(adapter = new FakeAdapter()) {
    this.adapter = adapter;
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

class HangingAdapter extends FakeAdapter {
  run({ onExit }) {
    return {
      abort() {
        onExit({ exitCode: -1, error: 'aborted' });
      },
    };
  }
}

class FailingAdapter extends FakeAdapter {
  run({ onExit }) {
    setImmediate(() => onExit({ exitCode: 2, error: 'cli usage error' }));
    return {
      abort() {},
    };
  }
}

class FakeOpenCodeServer {
  constructor() {
    this.sentMessages = [];
    this.deletedSessionId = null;
    this.abortedSessionId = null;
    this.eventHandlers = [];
  }

  async request(route, { method = 'GET', body } = {}) {
    if (method === 'GET' && route === '/provider') {
      return {
        all: [
          {
            id: 'anthropic',
            name: 'Anthropic',
            models: {
              'claude-sonnet-4': {
                id: 'claude-sonnet-4',
                name: 'Claude Sonnet 4',
                tool_call: true,
              },
            },
          },
        ],
      };
    }
    if (method === 'POST' && route.startsWith('/session?')) {
      return {
        id: 'oc-1',
        title: 'OpenCode native',
        directory: route,
        time: { created: 1, updated: 1 },
      };
    }
    if (method === 'GET' && route === '/session/oc-1/message') {
      return [
        {
          info: {
            id: 'oc-message-1',
            sessionID: 'oc-1',
            role: 'assistant',
            status: 'completed',
            time: { created: 1, completed: 2 },
          },
          parts: [
            {
              id: 'oc-part-1',
              sessionID: 'oc-1',
              messageID: 'oc-message-1',
              type: 'text',
              text: 'native response',
            },
          ],
        },
      ];
    }
    if (method === 'POST' && route === '/session/oc-1/message') {
      this.sentMessages.push(body);
      setImmediate(() => {
        this.emit({
          type: 'message.updated',
          properties: {
            info: {
              id: 'oc-message-1',
              sessionID: 'oc-1',
              role: 'assistant',
              status: 'running',
              time: { created: 1 },
            },
          },
        });
        this.emit({
          type: 'message.part.delta',
          properties: {
            sessionID: 'oc-1',
            messageID: 'oc-message-1',
            partID: 'oc-part-1',
            field: 'text',
            delta: 'native response',
          },
        });
        this.emit({
          type: 'session.idle',
          properties: { info: { id: 'oc-1' } },
        });
      });
      return { ok: true };
    }
    if (method === 'POST' && route === '/session/oc-1/abort') {
      this.abortedSessionId = 'oc-1';
      return true;
    }
    if (method === 'DELETE' && route === '/session/oc-1') {
      this.deletedSessionId = 'oc-1';
      return true;
    }
    throw new Error(`unexpected fake OpenCode request: ${method} ${route}`);
  }

  openEventStream({ signal, onEvent }) {
    this.eventHandlers.push(onEvent);
    signal?.addEventListener('abort', () => {
      this.eventHandlers = this.eventHandlers.filter((handler) => handler !== onEvent);
    });
    return {
      opened: Promise.resolve(),
      done: new Promise(() => {}),
    };
  }

  emit(event) {
    for (const handler of this.eventHandlers) {
      handler(event, 'message');
    }
  }

  close() {}
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

async function deleteJson(url) {
  const response = await fetch(url, { method: 'DELETE' });
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
