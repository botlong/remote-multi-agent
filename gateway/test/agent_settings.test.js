'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { createGatewayServer } = require('../src/server');

test('agent settings bind a profile/default model and apply them to new sessions', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-agent-settings-'));
  const dataFile = path.join(root, 'store.json');
  const profilesFile = path.join(root, 'profiles.json');
  const projectDir = path.join(root, 'project');
  await fs.mkdir(projectDir);

  const codex = new RecordingAdapter('codex');
  const server = await createGatewayServer({
    dataFile,
    profilesFile,
    adapters: new SingleAdapterRegistry(codex),
  });
  await listen(server);
  t.after(async () => {
    server.closeAllRuns?.();
    server.close();
    await fs.rm(root, { recursive: true, force: true });
  });

  const base = `http://127.0.0.1:${server.address().port}`;
  const profile = await postJson(`${base}/settings/profiles`, {
    name: 'Codex Profile',
    keys: {
      openai: {
        key: 'sk-codex-profile-secret',
        baseUrl: 'https://example.test/v1',
      },
    },
  });

  const agentSettings = await patchJson(`${base}/settings/agents/codex`, {
    profileId: profile.id,
    defaultModel: 'gpt-test-default',
  });
  assert.equal(agentSettings.agentId, 'codex');
  assert.equal(agentSettings.profile.id, profile.id);
  assert.equal(agentSettings.profile.keys.openai.key, 'sk-code...ret');
  assert.equal(agentSettings.defaultModel, 'gpt-test-default');

  const project = await postJson(`${base}/projects`, { directory: projectDir });
  const session = await postJson(`${base}/projects/${project.id}/sessions`, {
    agentId: 'codex',
  });

  assert.equal(session.raw.profileId, profile.id);
  assert.equal(session.modelId, 'gpt-test-default');
});

test('agent model listing uses the requested profileId instead of global state', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-agent-models-'));
  const dataFile = path.join(root, 'store.json');
  const profilesFile = path.join(root, 'profiles.json');

  const codex = new RecordingAdapter('codex');
  const server = await createGatewayServer({
    dataFile,
    profilesFile,
    adapters: new SingleAdapterRegistry(codex),
  });
  await listen(server);
  t.after(async () => {
    server.closeAllRuns?.();
    server.close();
    await fs.rm(root, { recursive: true, force: true });
  });

  const base = `http://127.0.0.1:${server.address().port}`;
  const profile = await postJson(`${base}/settings/profiles`, {
    name: 'Model Profile',
    keys: { openai: { key: 'sk-model-profile-secret' } },
  });

  const listed = await getJson(`${base}/agents/codex/models?profileId=${profile.id}`);

  assert.deepEqual(listed.models, [
    { id: 'model-for-codex', displayName: 'model-for-codex', raw: { profileId: profile.id } },
  ]);
  assert.equal(codex.modelCalls.length, 1);
  assert.equal(codex.modelCalls[0].profileId, profile.id);
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
}

class RecordingAdapter {
  constructor(id) {
    this.id = id;
    this.displayName = id;
    this.modelCalls = [];
  }

  async metadata() {
    return {
      id: this.id,
      displayName: this.displayName,
      supportsModels: true,
      supportsSlashCommands: false,
      supportsAttachments: false,
      supportsPermissions: false,
      sessionKind: 'thread',
      commands: [],
    };
  }

  async models(options = {}) {
    this.modelCalls.push(options);
    return [
      {
        id: `model-for-${this.id}`,
        displayName: `model-for-${this.id}`,
        raw: { profileId: options.profileId || null },
      },
    ];
  }

  run({ onExit }) {
    setImmediate(() => onExit({ exitCode: 0 }));
    return { abort() {} };
  }
}

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
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

async function patchJson(url, body) {
  const response = await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  assert.equal(response.ok, true, text);
  if (!text) return null;
  return JSON.parse(text);
}
