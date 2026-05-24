'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { OpenCodeAdapter } = require('../src/agents/opencode');

test('OpenCode maps opencode profile keys to OpenAI-compatible env vars', () => {
  const adapter = new OpenCodeAdapter({
    command: 'opencode',
    server: { externalBaseUrl: 'http://127.0.0.1:4097' },
    profileStore: {
      getKeyForProviderById(profileId, provider) {
        assert.equal(profileId, 'profile-opencode');
        if (provider !== 'opencode') return null;
        return {
          key: 'sk-opencode-secret',
          baseUrl: 'https://opencode.example/v1',
        };
      },
    },
  });

  assert.deepEqual(adapter._buildProfileEnv('profile-opencode'), {
    OPENAI_API_KEY: 'sk-opencode-secret',
    OPENAI_BASE_URL: 'https://opencode.example/v1',
  });
});
