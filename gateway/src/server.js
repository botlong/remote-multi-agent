'use strict';

const http = require('node:http');
const { URL } = require('node:url');
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const execFileAsync = promisify(execFile);

const { AgentRegistry } = require('./agents');
const { EventBus, makeEvent } = require('./events');
const {
  JsonStore,
  appendTextToMessage,
  appendToolPartToMessage,
  browseDirectories,
  completeMessage,
  createTextMessage,
  defaultDirectories,
  mkdir,
} = require('./store');

async function createGatewayServer({ dataFile, adapters } = {}) {
  const store = new JsonStore(dataFile);
  await store.load();

  // Reset sessions stuck in 'running' from a previous crash/restart.
  for (const session of store.data.sessions) {
    if (session.status === 'running') {
      session.status = 'idle';
    }
  }
  await store.save();

  const registry = adapters || new AgentRegistry();
  const bus = new EventBus();
  const activeRuns = new Map();

  const server = http.createServer(async (request, response) => {
    setCors(response);
    if (request.method === 'OPTIONS') {
      response.writeHead(204);
      response.end();
      return;
    }

    try {
      const url = new URL(request.url, 'http://gateway.local');
      const segments = url.pathname.split('/').filter(Boolean).map(decodeURIComponent);

      if (request.method === 'GET' && url.pathname === '/health') {
        return sendJson(response, {
          ok: true,
          version: '0.1.0',
          agents: (await registry.list()).map((agent) => agent.id),
        });
      }

      if (request.method === 'GET' && url.pathname === '/directories') {
        return sendJson(response, { directories: defaultDirectories(store) });
      }

      if (request.method === 'GET' && url.pathname === '/files/dirs') {
        return sendJson(response, await browseDirectories(url.searchParams.get('path')));
      }

      if (request.method === 'POST' && url.pathname === '/files/mkdir') {
        return sendJson(response, await mkdir((await readJson(request)).path));
      }

      if (segments[0] === 'projects') {
        return await handleProjects({
          request,
          response,
          segments,
          store,
          registry,
        });
      }

      if (segments[0] === 'agents') {
        return await handleAgents({
          request,
          response,
          segments,
          url,
          store,
          registry,
        });
      }

      if (segments[0] === 'sessions') {
        return await handleSessions({
          request,
          response,
          segments,
          store,
          registry,
          bus,
          activeRuns,
        });
      }

      // GET /search?q=...&projectId=...
      if (request.method === 'GET' && segments[0] === 'search') {
        const q = (url.searchParams.get('q') || '').toLowerCase().trim();
        const projectId = url.searchParams.get('projectId') || null;
        if (!q) return sendJson(response, []);
        const results = [];
        const sessions = projectId
          ? store.listSessions(projectId)
          : store.data.sessions;
        for (const session of sessions) {
          const messages = store.listMessages(session.id);
          for (const msg of messages) {
            const text = (msg.parts || [])
              .map((p) => p.text || p.output || '')
              .join(' ')
              .toLowerCase();
            if (text.includes(q)) {
              results.push({
                sessionId: session.id,
                sessionTitle: session.title,
                agentId: session.agentId,
                messageId: msg.id,
                role: msg.role,
                snippet: text.slice(
                  Math.max(0, text.indexOf(q) - 40),
                  text.indexOf(q) + q.length + 80,
                ),
              });
              if (results.length >= 50) break;
            }
          }
          if (results.length >= 50) break;
        }
        return sendJson(response, results);
      }

      throw httpError(404, 'not found');
    } catch (error) {
      if (response.headersSent) {
        response.destroy(error);
        return;
      }
      sendJson(
        response,
        {
          error: error.message || 'internal server error',
        },
        error.statusCode || 500,
      );
    }
  });

  server.closeAllRuns = () => {
    for (const run of activeRuns.values()) run.abort();
    activeRuns.clear();
    registry.close?.();
  };
  return server;
}

async function handleProjects({ request, response, segments, store, registry }) {
  if (segments.length === 1 && request.method === 'GET') {
    return sendJson(response, store.listProjects());
  }
  if (segments.length === 1 && request.method === 'POST') {
    const body = await readJson(request);
    return sendJson(
      response,
      await store.createProject({
        directory: body.directory,
        name: body.name,
      }),
      201,
    );
  }
  const project = store.getProject(segments[1]);
  if (!project) throw httpError(404, 'project not found');
  if (segments.length === 2 && request.method === 'GET') {
    return sendJson(response, project);
  }
  if (segments.length === 2 && request.method === 'DELETE') {
    await store.deleteProject(project.id);
    return sendJson(response, { ok: true });
  }
  if (segments.length === 3 && segments[2] === 'sessions') {
    if (request.method === 'GET') {
      return sendJson(response, store.listSessions(project.id));
    }
    if (request.method === 'POST') {
      const body = await readJson(request);
      const adapter = registry.get(body.agentId);
      if (!adapter) throw httpError(400, `unknown agent: ${body.agentId}`);
      let nativeSession = null;
      if (adapter.createSession) {
        try {
          nativeSession = await adapter.createSession({
            project,
            modelId: body.modelId,
            title: body.title || `${adapter.displayName} session`,
          });
        } catch (_) {
          nativeSession = null;
        }
      }
      const rawExtra = {};
      if (body.sandbox) rawExtra.sandbox = body.sandbox;
      if (body.permissionMode) rawExtra.permissionMode = body.permissionMode;
      const session = await store.createSession({
        project,
        agentId: body.agentId,
        modelId: body.modelId,
        title: body.title || nativeSession?.title || `${adapter.displayName} session`,
        agentSessionId: nativeSession?.agentSessionId,
        raw: { ...(nativeSession ? { agentSession: nativeSession.raw } : {}), ...rawExtra },
      });
      return sendJson(response, session, 201);
    }
  }
  throw httpError(404, 'not found');
}

async function handleAgents({ request, response, segments, url, store, registry }) {
  if (segments.length === 1 && request.method === 'GET') {
    return sendJson(response, await registry.list());
  }
  const adapter = registry.get(segments[1]);
  if (!adapter) throw httpError(404, 'agent not found');
  if (segments.length === 2 && request.method === 'GET') {
    return sendJson(response, await adapter.metadata());
  }
  if (segments.length === 3 && segments[2] === 'models' && request.method === 'GET') {
    return sendJson(response, { models: await adapter.models() });
  }
  if (segments.length === 3 && segments[2] === 'commands' && request.method === 'GET') {
    const projectId = url.searchParams.get('projectId');
    const project = projectId
      ? store.getProject(projectId)
      : store.listProjects()[0];
    return sendJson(response, {
      commands: await adapter.commands(project?.directory),
    });
  }
  throw httpError(404, 'not found');
}

async function handleSessions({
  request,
  response,
  segments,
  store,
  registry,
  bus,
  activeRuns,
}) {
  const session = store.getSession(segments[1]);
  if (!session) throw httpError(404, 'session not found');

  if (segments.length === 2 && request.method === 'GET') {
    return sendJson(response, session);
  }
  if (segments.length === 2 && request.method === 'PATCH') {
    return sendJson(response, await store.updateSession(session.id, await readJson(request)));
  }
  if (segments.length === 2 && request.method === 'DELETE') {
    const run = activeRuns.get(session.id);
    if (run) run.abort();
    activeRuns.delete(session.id);
    const adapter = registry.get(session.agentId);
    if (adapter?.deleteSession) {
      await adapter.deleteSession(session).catch(() => false);
    }
    await store.deleteSession(session.id);
    bus.clearSession?.(session.id);
    return sendJson(response, { ok: true });
  }

  if (segments.length === 3 && segments[2] === 'messages') {
    if (request.method === 'GET') {
      const adapter = registry.get(session.agentId);
      if (adapter?.listMessages) {
        const messages = await adapter.listMessages(session).catch(() => null);
        if (Array.isArray(messages)) return sendJson(response, messages);
      }
      return sendJson(response, store.listMessages(session.id));
    }
    if (request.method === 'POST') {
      const body = await readJson(request);
      const text = typeof body.text === 'string' ? body.text : '';
      const parts = Array.isArray(body.parts) ? body.parts : [];
      if (!text.trim() && parts.length === 0) {
        throw httpError(400, 'text or parts are required');
      }
      // If session is already running, inject guidance instead of rejecting.
      const existingRun = activeRuns.get(session.id);
      if (existingRun) {
        const userMessage = createTextMessage({
          sessionId: session.id,
          role: 'user',
          text,
        });
        await store.appendMessage(session.id, userMessage);
        emit(bus, 'message.created', session, { message: userMessage }, userMessage);

        const adapter = registry.get(session.agentId);
        let injected = false;

        // Try stdin write (Codex).
        if (existingRun.write) {
          injected = existingRun.write(text);
        }
        // Try native API injection (OpenCode).
        if (!injected && adapter?.injectMessage) {
          await adapter.injectMessage(session, text, parts);
          injected = true;
        }
        console.log(`[inject] session=${session.id} agent=${session.agentId} injected=${injected} text=${text.slice(0,80)}`);
        return sendJson(response, { accepted: true, injected, sessionId: session.id }, 202);
      }
      await startTurn({
        session,
        text,
        parts,
        store,
        registry,
        bus,
        activeRuns,
      });
      return sendJson(response, { accepted: true, sessionId: session.id }, 202);
    }
  }

  // DELETE /sessions/:sessionId/messages/:messageId
  if (segments.length === 4 && segments[2] === 'messages' && request.method === 'DELETE') {
    const messageId = segments[3];
    const deleted = await store.deleteMessage(session.id, messageId);
    if (!deleted) throw httpError(404, 'message not found');
    emit(bus, 'message.deleted', session, { messageId }, { messageId });
    return sendJson(response, { ok: true });
  }

  if (segments.length === 3 && segments[2] === 'abort' && request.method === 'POST') {
    const run = activeRuns.get(session.id);
    if (run) run.abort();
    activeRuns.delete(session.id);
    const adapter = registry.get(session.agentId);
    if (!run && adapter?.abort) {
      await adapter.abort(session).catch(() => false);
    }
    const updated = await store.updateSession(session.id, {
      status: 'idle',
      raw: run ? { lastAborted: true } : {},
    });
    emit(bus, 'session.updated', updated, { session: updated });
    return sendJson(response, { ok: true });
  }

  if (segments.length === 3 && segments[2] === 'events' && request.method === 'GET') {
    response.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'X-Accel-Buffering': 'no',
    });
    const unsubscribe = bus.subscribe(session.id, response);
    request.on('close', unsubscribe);
    return;
  }

  // GET /sessions/:sessionId/export?format=markdown|json
  if (segments.length === 3 && segments[2] === 'export' && request.method === 'GET') {
    const format = url.searchParams.get('format') || 'markdown';
    const messages = store.listMessages(session.id);
    if (format === 'json') {
      return sendJson(response, {
        session: {
          id: session.id,
          title: session.title,
          agentId: session.agentId,
          directory: session.directory,
          createdAt: session.createdAt,
        },
        messages,
      });
    }
    // markdown
    let md = `# ${session.title}\n\n`;
    md += `**Agent:** ${session.agentId}  \n`;
    md += `**Directory:** ${session.directory || '—'}  \n`;
    md += `**Created:** ${session.createdAt || '—'}  \n\n---\n\n`;
    for (const msg of messages) {
      const role = (msg.role || 'unknown').toUpperCase();
      md += `### ${role}\n\n`;
      for (const part of msg.parts || []) {
        if (part.type === 'text' && part.text) {
          md += `${part.text}\n\n`;
        } else if (part.type === 'tool') {
          md += `> **Tool:** ${part.toolName || 'unknown'}`;
          if (part.output) md += `\n> \`\`\`\n> ${part.output.slice(0, 500)}\n> \`\`\``;
          md += '\n\n';
        }
      }
    }
    response.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8' });
    response.end(md);
    return;
  }

  // GET /sessions/:sessionId/diff  — git diff for this session's directory
  if (segments.length === 3 && segments[2] === 'diff' && request.method === 'GET') {
    const dir = session.directory;
    if (!dir) throw httpError(400, 'session has no directory');
    try {
      const { stdout: diffText } = await execFileAsync(
        'git', ['diff', '--no-color'], { cwd: dir, maxBuffer: 2 * 1024 * 1024 },
      );
      const { stdout: stagedText } = await execFileAsync(
        'git', ['diff', '--cached', '--no-color'], { cwd: dir, maxBuffer: 2 * 1024 * 1024 },
      ).catch(() => ({ stdout: '' }));
      const combined = (diffText + stagedText).trim();
      return sendJson(response, { diff: combined, directory: dir });
    } catch (err) {
      return sendJson(response, { diff: '', error: err.message, directory: dir });
    }
  }

  throw httpError(404, 'not found');
}

async function startTurn({ session, text, parts = [], store, registry, bus, activeRuns }) {
  if (activeRuns.has(session.id)) {
    throw httpError(409, 'session already running');
  }
  const adapter = registry.get(session.agentId);
  if (!adapter) throw httpError(400, `unknown agent: ${session.agentId}`);
  console.log(`[startTurn] agent=${session.agentId} model=${session.modelId} dir=${session.directory} prompt=${text.slice(0,80)}`);
  const canRunNative = Boolean(adapter.runNative && session.agentSessionId);

  // Auto-title from first user message when title is a default placeholder.
  const isDefaultTitle = /^(Codex|Claude Code|OpenCode)\s+session$/i.test(session.title);
  const autoTitle = isDefaultTitle && text.trim()
    ? text.trim().replace(/\s+/g, ' ').slice(0, 50) + (text.trim().length > 50 ? '…' : '')
    : null;
  const runPatch = { status: 'running' };
  if (autoTitle) runPatch.title = autoTitle;

  const running = await store.updateSession(session.id, runPatch);
  emit(bus, 'session.started', running, { session: running });
  emit(bus, 'session.updated', running, { session: running });

  let assistantMessage = null;
  let textWrite = Promise.resolve();
  let partId = null;
  let run = null;
  let aborted = false;

  if (canRunNative) {
    try {
      run = await adapter.runNative({
        session: running,
        prompt: text,
        parts,
        onEvent: ({ type, data, raw }) => emit(bus, type, running, data, raw),
        onExit: handleExit,
      });
    } catch (error) {
      emit(
        bus,
        'command.updated',
        running,
        {
          source: running.agentId,
          eventType: 'native-fallback',
          error: error.message,
        },
        { error: error.message },
      );
      run = null;
    }
  }

  if (!run) {
    const userMessage = createTextMessage({
      sessionId: session.id,
      role: 'user',
      text,
    });
    await store.appendMessage(session.id, userMessage);
    emit(bus, 'message.created', session, { message: userMessage }, userMessage);

    assistantMessage = createTextMessage({
      sessionId: session.id,
      role: 'assistant',
      text: '',
      status: 'running',
      modelId: session.modelId,
    });
    await store.appendMessage(session.id, assistantMessage);
    emit(bus, 'message.created', session, { message: assistantMessage }, assistantMessage);
    partId = assistantMessage.parts[0].id;

    run = adapter.run({
      session: running,
      prompt: text,
      onEvent: ({ type, data, raw }) => emit(bus, type, running, data, raw),
      onText: (delta) => {
        if (!delta) return;
        console.log(`[onText] delta(${delta.length}): ${delta.slice(0,100)}`);
        textWrite = textWrite.then(async () => {
          assistantMessage = appendTextToMessage(assistantMessage, delta);
          await store.updateMessage(session.id, assistantMessage.id, () => assistantMessage);
          emit(
            bus,
            'message.delta',
            running,
            {
              messageId: assistantMessage.id,
              partId,
              field: 'text',
              delta,
            },
            { delta },
          );
        });
        return textWrite;
      },
      onToolCall: (toolCall) => {
        console.log(`[onToolCall] name=${toolCall.name} status=${toolCall.status}`);
        textWrite = textWrite.then(async () => {
          assistantMessage = appendToolPartToMessage(assistantMessage, toolCall);
          await store.updateMessage(session.id, assistantMessage.id, () => assistantMessage);
          const toolPart = assistantMessage.parts.find(
            (p) => p.type === 'tool' && p.toolCallId === (toolCall.callId || toolCall.toolUseId),
          ) || assistantMessage.parts[assistantMessage.parts.length - 1];
          emit(bus, 'message.part.updated', running, { part: toolPart }, toolPart);
        });
        return textWrite;
      },
      onUsage: (usage) => {
        emit(bus, 'session.usage', running, { usage }, usage);
      },
      onAgentSessionId: async (agentSessionId, raw) => {
        if (agentSessionId && agentSessionId !== session.agentSessionId) {
          session.agentSessionId = agentSessionId;
          await store.updateSession(session.id, {
            agentSessionId,
            raw: { agentSession: raw },
          });
        }
      },
      onExit: handleExit,
    });
  }

  activeRuns.set(session.id, {
    ...run,
    abort() {
      aborted = true;
      run.abort();
    },
  });

  async function handleExit({ exitCode, error }) {
    console.log(`[handleExit] exitCode=${exitCode} error=${error || 'none'}`);
    activeRuns.delete(session.id);
    await textWrite;
    if (assistantMessage) {
      const finalStatus = exitCode === 0 || aborted ? 'completed' : 'error';
      const errorText = error || `agent exited with code ${exitCode}`;
      if (finalStatus === 'error' && !messageText(assistantMessage).trim()) {
        assistantMessage = appendTextToMessage(assistantMessage, errorText);
        await store.updateMessage(session.id, assistantMessage.id, () => assistantMessage);
        emit(
          bus,
          'message.delta',
          running,
          {
            messageId: assistantMessage.id,
            partId: assistantMessage.parts?.[0]?.id || partId,
            field: 'text',
            delta: errorText,
          },
          { delta: errorText },
        );
      }
      assistantMessage = completeMessage(assistantMessage, finalStatus);
      await store.updateMessage(session.id, assistantMessage.id, () => assistantMessage);
    }
    emit(
      bus,
      'message.completed',
      running,
      assistantMessage ? { message: assistantMessage } : {},
      assistantMessage || {},
    );

    const updated = await store.updateSession(session.id, {
      status: exitCode === 0 || aborted ? 'idle' : 'error',
      raw: {
        lastExitCode: exitCode,
        lastError: error || null,
        lastAborted: aborted || null,
      },
    });
    if (!updated) return;
    if (!aborted && exitCode === 0) {
      emit(bus, 'session.completed', updated, { session: updated });
    } else if (!aborted) {
      emit(
        bus,
        'session.error',
        updated,
        { error: error || `agent exited with code ${exitCode}` },
        { exitCode, error },
      );
    }
    emit(bus, 'session.updated', updated, { session: updated });
  }
}

function messageText(message) {
  return (message.parts || [])
    .map((part) => (typeof part.text === 'string' ? part.text : ''))
    .join('');
}

function emit(bus, type, session, data = {}, raw = {}) {
  bus.emit(
    makeEvent({
      type,
      sessionId: session.id,
      agentId: session.agentId,
      data,
      raw,
    }),
  );
}

function setCors(response) {
  response.setHeader('Access-Control-Allow-Origin', '*');
  response.setHeader('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS');
  response.setHeader('Access-Control-Allow-Headers', 'Content-Type,Authorization');
}

function sendJson(response, data, status = 200) {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(data));
}

async function readJson(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  if (chunks.length === 0) return {};
  const raw = Buffer.concat(chunks).toString('utf8');
  if (!raw.trim()) return {};
  try {
    return JSON.parse(raw);
  } catch (_) {
    throw httpError(400, 'invalid JSON body');
  }
}

function httpError(statusCode, message) {
  return Object.assign(new Error(message), { statusCode });
}

module.exports = {
  createGatewayServer,
};
