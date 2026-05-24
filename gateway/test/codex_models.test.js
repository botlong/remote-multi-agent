'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { CodexAdapter } = require('../src/agents/codex');

test('Codex model listing uses the selected OpenAI profile credentials', async (t) => {
  const originalFetch = global.fetch;
  const calls = [];
  global.fetch = async (url, options = {}) => {
    calls.push({ url: String(url), headers: options.headers || {} });
    return {
      ok: true,
      async json() {
        return {
          data: [
            {
              id: 'gpt-profile-model',
              object: 'model',
              owned_by: 'profile',
            },
            { object: 'model' },
          ],
        };
      },
    };
  };
  t.after(() => {
    global.fetch = originalFetch;
  });

  const adapter = new CodexAdapter({
    profileStore: {
      getKeyForProviderById(profileId, provider) {
        assert.equal(profileId, 'profile-openai');
        assert.equal(provider, 'openai');
        return {
          key: 'sk-profile-secret',
          baseUrl: 'https://openai.example/v1/',
        };
      },
    },
  });

  const models = await adapter._fetchModels({ profileId: 'profile-openai' });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://openai.example/v1/models');
  assert.equal(calls[0].headers.authorization, 'Bearer sk-profile-secret');
  assert.deepEqual(models, [
    {
      id: 'gpt-profile-model',
      displayName: 'gpt-profile-model',
      raw: {
        id: 'gpt-profile-model',
        object: 'model',
        owned_by: 'profile',
      },
    },
  ]);
});

test('Codex model listing adds /v1 for OpenAI-compatible root URLs', async (t) => {
  const originalFetch = global.fetch;
  const calls = [];
  global.fetch = async (url) => {
    calls.push(String(url));
    return {
      ok: true,
      async json() {
        return { data: [{ id: 'model-from-compatible-root' }] };
      },
    };
  };
  t.after(() => {
    global.fetch = originalFetch;
  });

  const adapter = new CodexAdapter({
    profileStore: {
      getKeyForProviderById() {
        return {
          key: 'mr-compatible-secret',
          baseUrl: 'https://mr.zhi-yuan.net',
        };
      },
    },
  });

  const models = await adapter._fetchModels({ profileId: 'profile-zhiyuan' });

  assert.equal(calls[0], 'https://mr.zhi-yuan.net/v1/models');
  assert.equal(models[0].id, 'model-from-compatible-root');
});
