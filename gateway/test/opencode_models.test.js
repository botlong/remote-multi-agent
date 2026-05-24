'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { OpenCodeAdapter } = require('../src/agents/opencode');

test('OpenCode model listing uses the selected OpenAI-compatible profile', async (t) => {
  const originalFetch = global.fetch;
  const calls = [];
  global.fetch = async (url, options = {}) => {
    calls.push({ url: String(url), headers: options.headers || {} });
    return {
      ok: true,
      async json() {
        return {
          data: [
            { id: 'glm-4.6' },
            { id: 'glm-4.7' },
            { id: 'glm-4.7-air' },
          ],
        };
      },
    };
  };
  t.after(() => {
    global.fetch = originalFetch;
  });

  const adapter = new OpenCodeAdapter({
    command: 'opencode',
    server: {
      async request() {
        throw new Error('server should not be used for selected profile models');
      },
    },
    profileStore: {
      getKeyForProviderById(profileId, provider) {
        assert.equal(profileId, 'profile-zhiyuan');
        if (provider !== 'opencode') return null;
        return {
          key: 'mr-opencode-secret',
          baseUrl: 'https://mr.zhi-yuan.net',
        };
      },
    },
  });

  const models = await adapter._fetchModels({ profileId: 'profile-zhiyuan' });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://mr.zhi-yuan.net/v1/models');
  assert.equal(calls[0].headers.authorization, 'Bearer mr-opencode-secret');
  assert.deepEqual(models.map((model) => model.id), [
    'opencode/glm-4.6',
    'opencode/glm-4.7',
    'opencode/glm-4.7-air',
  ]);
});
