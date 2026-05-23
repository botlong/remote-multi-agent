'use strict';

const MODEL_CACHE_TTL = 5 * 60 * 1000;
const modelCache = new Map();

function cachedModels(key, fetchFn) {
  const entry = modelCache.get(key);
  if (entry && Date.now() - entry.ts < MODEL_CACHE_TTL) return entry.promise;
  const promise = fetchFn().then((models) => {
    modelCache.set(key, { ts: Date.now(), promise: Promise.resolve(models) });
    return models;
  }).catch((err) => {
    modelCache.delete(key);
    throw err;
  });
  modelCache.set(key, { ts: Date.now(), promise });
  return promise;
}

module.exports = { cachedModels, modelCache };
