'use strict';

function providerModels(payload) {
  const all = Array.isArray(payload?.all) ? payload.all : [];
  const configured = [];
  const unconfigured = [];
  for (const provider of all) {
    if (!provider || typeof provider !== 'object') continue;
    const providerId = provider.id || provider.providerID;
    if (!providerId) continue;
    const providerName = provider.name || providerId;
    const models = provider.models || {};
    // A provider is "configured" if it has an API key or env set
    const isConfigured = Boolean(
      provider.configured || provider.apiKey || provider.api_key || provider.env,
    );
    const target = isConfigured ? configured : unconfigured;
    for (const [modelId, model] of Object.entries(models)) {
      target.push({
        id: `${providerId}/${modelId}`,
        displayName: `${providerName} / ${model?.name || modelId}`,
        raw: compactOpenCodeModel(providerId, modelId, model),
      });
    }
  }
  // Configured providers first, then unconfigured
  return [...configured, ...unconfigured];
}

function compactOpenCodeModel(providerId, modelId, model) {
  return {
    providerID: providerId,
    modelID: modelId,
    name: model?.name,
    toolCall: model?.tool_call,
    attachment: model?.attachment,
    reasoning: model?.reasoning,
    limit: model?.limit,
  };
}

function splitOpenCodeModel(value) {
  const fallback = process.env.OPENCODE_DEFAULT_MODEL || 'opencode/big-pickle';
  const text = String(value || fallback);
  const slash = text.indexOf('/');
  if (slash === -1) {
    return {
      providerId: process.env.OPENCODE_DEFAULT_PROVIDER || 'opencode',
      modelId: text,
    };
  }
  return {
    providerId: text.slice(0, slash),
    modelId: text.slice(slash + 1),
  };
}

function normalizeOpenCodeEvent(raw, eventName = 'message') {
  if (!raw || typeof raw !== 'object') return null;
  const type = raw.type || eventName;
  const properties = raw.properties || raw.data || {};
  switch (type) {
    case 'message.updated': {
      const info = properties.info || raw.info || raw.message || null;
      return {
        type,
        data: info ? { info } : properties,
        raw,
      };
    }
    case 'message.part.updated': {
      const part = properties.part || raw.part || null;
      return {
        type,
        data: part ? { part } : properties,
        raw,
      };
    }
    case 'message.part.delta':
      return {
        type,
        data: {
          sessionID: properties.sessionID || raw.sessionID,
          messageID: properties.messageID || raw.messageID,
          partID: properties.partID || raw.partID,
          field: properties.field || raw.field || 'text',
          delta: properties.delta ?? raw.delta ?? '',
        },
        raw,
      };
    case 'session.updated':
      return {
        type: 'status.updated',
        data: {
          status: 'running',
          source: 'opencode',
          eventType: type,
          session: properties.info || properties.session || raw.session || properties,
        },
        raw,
      };
    case 'session.error':
      return {
        type,
        data: { error: openCodeErrorMessage(raw) },
        raw,
      };
    case 'session.idle':
      return {
        type: 'status.updated',
        data: {
          status: 'idle',
          source: 'opencode',
          eventType: type,
          session: properties.info || properties.session || raw.session || properties,
        },
        raw,
      };
    default:
      return {
        type: 'command.updated',
        data: { source: 'opencode', eventType: type, properties },
        raw,
      };
  }
}

function openCodeEventSessionId(raw) {
  const properties = raw.properties || raw.data || {};
  return (
    properties.sessionID ||
    raw.sessionID ||
    properties.sessionId ||
    raw.sessionId ||
    properties.session?.id ||
    raw.session?.id ||
    properties.info?.sessionID ||
    raw.info?.sessionID ||
    raw.message?.sessionID ||
    properties.part?.sessionID ||
    raw.part?.sessionID ||
    (String(raw.type || '').startsWith('session.') ? properties.info?.id : null) ||
    null
  );
}

function openCodeTerminalResult(raw) {
  const type = raw?.type;
  const properties = raw?.properties || raw?.data || {};
  const info = properties.info || raw?.info || raw?.message || {};
  if (type === 'session.error') {
    return { exitCode: -1, error: openCodeErrorMessage(raw) };
  }
  if (info.status === 'error') {
    return { exitCode: -1, error: openCodeErrorMessage(raw) };
  }
  if (type === 'session.idle' || type === 'session.completed') {
    return { exitCode: 0 };
  }
  if (info.role === 'assistant' && info.status === 'completed') {
    return { exitCode: 0 };
  }
  return null;
}

function openCodeErrorMessage(raw) {
  const properties = raw?.properties || raw?.data || {};
  const error = properties.error || raw?.error || {};
  return error.message || raw?.message || 'OpenCode error';
}

module.exports = {
  providerModels,
  splitOpenCodeModel,
  normalizeOpenCodeEvent,
  openCodeEventSessionId,
  openCodeTerminalResult,
};
