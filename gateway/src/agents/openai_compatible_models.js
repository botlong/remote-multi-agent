'use strict';

async function fetchOpenAICompatibleModels({
  apiKey,
  baseUrl,
  idPrefix = '',
  timeoutMs = 8000,
} = {}) {
  if (!apiKey) return [];
  const res = await fetch(openAICompatibleModelsUrl(baseUrl), {
    headers: {
      authorization: `Bearer ${apiKey}`,
      accept: 'application/json',
    },
    signal: AbortSignal.timeout(timeoutMs),
  });
  if (!res.ok) return [];
  const body = await res.json();
  const seen = new Set();
  return readOpenAICompatibleModels(body)
    .filter((model) => {
      if (!model.id || seen.has(model.id)) return false;
      seen.add(model.id);
      return true;
    })
    .map((model) => {
      const id = `${idPrefix}${model.id}`;
      return {
        id,
        displayName: model.display_name || model.name || id,
        raw: model,
      };
    });
}

function openAICompatibleModelsUrl(baseUrl) {
  const root = (baseUrl || 'https://api.openai.com/v1').replace(/\/+$/, '');
  if (/\/v1(?:\/)?$/i.test(root)) return `${root}/models`;
  return `${root}/v1/models`;
}

function readOpenAICompatibleModels(body) {
  if (Array.isArray(body)) return body;
  if (Array.isArray(body?.data)) return body.data;
  if (Array.isArray(body?.models)) return body.models;
  return [];
}

module.exports = {
  fetchOpenAICompatibleModels,
  openAICompatibleModelsUrl,
  readOpenAICompatibleModels,
};
