'use strict';

const net = require('node:net');

const { killProcessTree, spawnCli } = require('./cli');

class OpenCodeServerManager {
  constructor({ command, baseUrl, password, startTimeoutMs, extraEnv } = {}) {
    this.command = command;
    this.externalBaseUrl = normalizeBaseUrl(
      baseUrl || process.env.OPENCODE_SERVER_URL || '',
    );
    this.baseUrl = this.externalBaseUrl || null;
    this.password =
      password ?? (this.externalBaseUrl ? process.env.OPENCODE_SERVER_PASSWORD || '' : '');
    this.startTimeoutMs =
      startTimeoutMs ?? (Number(process.env.OPENCODE_SERVER_START_TIMEOUT_MS) || 45000);
    this.extraEnv = extraEnv || {};
    this.child = null;
    this.ensurePromise = null;
    this.logs = '';
  }

  async ensure() {
    if (this.ensurePromise) return this.ensurePromise;
    this.ensurePromise = this.baseUrl ? this.waitUntilReady() : this.start();
    try {
      return await this.ensurePromise;
    } catch (error) {
      this.ensurePromise = null;
      throw error;
    }
  }

  async start() {
    if (!this.command) throw new Error('OpenCode command is not configured');
    const hostname = process.env.OPENCODE_SERVER_HOST || '127.0.0.1';
    const port = Number(process.env.OPENCODE_SERVER_PORT) || (await getFreePort());
    this.baseUrl = `http://${hostname}:${port}`;

    const args = [
      'serve',
      '--hostname',
      hostname,
      '--port',
      String(port),
      '--log-level',
      process.env.OPENCODE_LOG_LEVEL || 'ERROR',
    ];
    if (process.env.OPENCODE_PURE === '1') args.push('--pure');

    try {
      this.child = spawnCli(this.command, args, {
        env: {
          ...this.extraEnv,
          ...(this.password ? { OPENCODE_SERVER_PASSWORD: this.password } : {}),
        },
      });
    } catch (error) {
      this.baseUrl = this.externalBaseUrl || null;
      throw error;
    }
    captureLogs(this.child.stdout, (chunk) => this.appendLog(chunk));
    captureLogs(this.child.stderr, (chunk) => this.appendLog(chunk));
    this.child.once('exit', (code) => {
      if (code !== 0) this.appendLog(`OpenCode server exited with code ${code}`);
    });

    try {
      return await this.waitUntilReady();
    } catch (error) {
      this.close();
      this.baseUrl = null;
      throw error;
    }
  }

  async waitUntilReady() {
    const startedAt = Date.now();
    let lastError = null;
    while (Date.now() - startedAt < this.startTimeoutMs) {
      try {
        const response = await fetch(new URL('/session', this.baseUrl), {
          headers: this.headers({ Accept: 'application/json' }),
          signal: AbortSignal.timeout(1500),
        });
        if (response.ok) return this.baseUrl;
        if (response.status === 401 || response.status === 403) {
          throw Object.assign(
            new Error(`OpenCode server rejected gateway credentials: HTTP ${response.status}`),
            { nonRetryable: true },
          );
        }
        lastError = new Error(`HTTP ${response.status}`);
      } catch (error) {
        if (error.nonRetryable) throw error;
        lastError = error;
      }
      await delay(150);
    }
    const suffix = this.logs ? `\n${this.logs}` : lastError ? `: ${lastError.message}` : '';
    throw new Error(`OpenCode server did not become ready at ${this.baseUrl}${suffix}`);
  }

  async request(route, { method = 'GET', body, signal, headers = {} } = {}) {
    const baseUrl = await this.ensure();
    const response = await fetch(new URL(route, ensureTrailingSlash(baseUrl)), {
      method,
      headers: this.headers({
        Accept: 'application/json',
        ...(body === undefined ? {} : { 'Content-Type': 'application/json' }),
        ...headers,
      }),
      body: body === undefined ? undefined : JSON.stringify(body),
      signal,
    });
    const text = await response.text();
    if (!response.ok) {
      throw new Error(
        `OpenCode ${method} ${route} failed: HTTP ${response.status}${text ? ` ${trim(text)}` : ''}`,
      );
    }
    if (!text.trim()) return null;
    try {
      return JSON.parse(text);
    } catch (_) {
      return text;
    }
  }

  openEventStream({ signal, onEvent }) {
    const opened = {};
    opened.promise = new Promise((resolve, reject) => {
      opened.resolve = resolve;
      opened.reject = reject;
    });

    const done = (async () => {
      const baseUrl = await this.ensure();
      const response = await fetch(new URL('/event', ensureTrailingSlash(baseUrl)), {
        headers: this.headers({ Accept: 'text/event-stream' }),
        signal,
      });
      if (!response.ok) {
        throw new Error(`OpenCode event stream failed: HTTP ${response.status}`);
      }
      opened.resolve();
      await parseSse(response, signal, onEvent);
    })();

    done.catch((error) => opened.reject(error));
    return { opened: opened.promise, done };
  }

  headers(extra = {}) {
    return {
      ...extra,
      ...(this.password ? { Authorization: `Basic ${basicPassword(this.password)}` } : {}),
    };
  }

  appendLog(chunk) {
    this.logs = `${this.logs}${chunk.toString('utf8')}`;
    if (this.logs.length > 4000) this.logs = this.logs.slice(-4000);
  }

  close() {
    if (this.child) {
      killProcessTree(this.child);
      this.child = null;
    }
  }
}

async function parseSse(response, signal, onEvent) {
  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let eventName = 'message';
  const dataLines = [];

  const abort = () => {
    reader.cancel().catch(() => {});
  };
  signal?.addEventListener('abort', abort, { once: true });

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let newline;
      while ((newline = buffer.search(/\r?\n/)) !== -1) {
        const rawLine = buffer.slice(0, newline);
        buffer = buffer.slice(buffer[newline] === '\r' ? newline + 2 : newline + 1);
        if (rawLine === '') {
          dispatchSseEvent(eventName, dataLines, onEvent);
          eventName = 'message';
          dataLines.length = 0;
          continue;
        }
        if (rawLine.startsWith(':')) continue;
        const colon = rawLine.indexOf(':');
        const field = colon === -1 ? rawLine : rawLine.slice(0, colon);
        const fieldValue =
          colon === -1
            ? ''
            : rawLine[colon + 1] === ' '
              ? rawLine.slice(colon + 2)
              : rawLine.slice(colon + 1);
        if (field === 'event') eventName = fieldValue || 'message';
        if (field === 'data') dataLines.push(fieldValue);
      }
    }
    dispatchSseEvent(eventName, dataLines, onEvent);
  } finally {
    signal?.removeEventListener('abort', abort);
  }
}

function dispatchSseEvent(eventName, dataLines, onEvent) {
  if (dataLines.length === 0) return;
  const data = dataLines.join('\n');
  let parsed;
  try {
    parsed = JSON.parse(data);
  } catch (_) {
    parsed = { type: eventName, _raw: data };
  }
  onEvent(parsed, eventName);
}

function captureLogs(stream, onChunk) {
  stream.setEncoding('utf8');
  stream.on('data', onChunk);
}

function getFreePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      server.close(() => resolve(address.port));
    });
  });
}

function normalizeBaseUrl(value) {
  const text = String(value || '').trim();
  if (!text) return '';
  return text.replace(/\/+$/, '');
}

function ensureTrailingSlash(value) {
  return value.endsWith('/') ? value : `${value}/`;
}

function trim(value) {
  const text = String(value).replace(/\s+/g, ' ').trim();
  return text.length > 500 ? `${text.slice(0, 500)}...` : text;
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function basicPassword(password) {
  return Buffer.from(`opencode:${password}`, 'utf8').toString('base64');
}

module.exports = {
  OpenCodeServerManager,
};
