'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

const { fetchOpenAICompatibleModels } = require('../src/agents/openai_compatible_models');

test('OpenAI-compatible model listing keeps the first model for each id', async (t) => {
  const originalFetch = global.fetch;
  global.fetch = async () => ({
    ok: true,
    async json() {
      return {
        data: [
          { id: 'gpt-5.5', name: 'GPT 5.5' },
          { id: 'glm-5' },
          { id: 'gpt-5.5', name: 'Duplicate GPT 5.5' },
        ],
      };
    },
  });
  t.after(() => {
    global.fetch = originalFetch;
  });

  const models = await fetchOpenAICompatibleModels({
    apiKey: 'sk-test',
    baseUrl: 'https://models.example/v1',
  });

  assert.deepEqual(models.map((model) => model.id), ['gpt-5.5', 'glm-5']);
  assert.equal(models[0].displayName, 'GPT 5.5');
});
