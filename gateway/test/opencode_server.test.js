'use strict';

const assert = require('node:assert/strict');
const http = require('node:http');
const test = require('node:test');

const { OpenCodeServerManager } = require('../src/opencode_server');

test('OpenCodeServerManager uses OpenCode Basic auth for external servers', async (t) => {
  let authorization = null;
  const server = http.createServer((request, response) => {
    authorization = request.headers.authorization || null;
    response.writeHead(200, { 'Content-Type': 'application/json' });
    response.end(JSON.stringify([]));
  });
  await listen(server);
  t.after(() => server.close());

  const manager = new OpenCodeServerManager({
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    password: 'secret',
    startTimeoutMs: 500,
  });
  await manager.request('/session');

  assert.equal(
    authorization,
    `Basic ${Buffer.from('opencode:secret', 'utf8').toString('base64')}`,
  );
});

test('OpenCodeServerManager fails fast on rejected credentials', async (t) => {
  const server = http.createServer((_, response) => {
    response.writeHead(401);
    response.end();
  });
  await listen(server);
  t.after(() => server.close());

  const manager = new OpenCodeServerManager({
    baseUrl: `http://127.0.0.1:${server.address().port}`,
    password: 'wrong',
    startTimeoutMs: 30000,
  });

  await assert.rejects(
    manager.request('/session'),
    /OpenCode server rejected gateway credentials/,
  );
});

function listen(server) {
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', resolve);
  });
}
