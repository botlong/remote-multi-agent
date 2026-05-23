'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const { createGatewayServer } = require('../src/server');
const { configurePaths } = require('../src/credential_sources');

test('credential-sources + import end-to-end flow (Claude + Codex)', async (t) => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-import-'));
  const dataFile = path.join(root, 'store.json');
  const profilesFile = path.join(root, 'profiles.json');
  const claudeFile = path.join(root, 'claude.json');
  const codexFile = path.join(root, 'codex.json');

  await fs.writeFile(
    claudeFile,
    JSON.stringify({
      env: {
        ANTHROPIC_AUTH_TOKEN: 'sk-ant-test-token-aaaaa',
        ANTHROPIC_BASE_URL: 'https://api.anthropic.com',
      },
    }),
  );
  await fs.writeFile(
    codexFile,
    JSON.stringify({ OPENAI_API_KEY: 'sk-openai-test-bbbbb' }),
  );

  configurePaths({
    claudePath: claudeFile,
    codexPath: codexFile,
    ccSwitchPath: path.join(root, 'no-cc.db'),
  });

  const server = await createGatewayServer({ dataFile, profilesFile });
  await listen(server);
  t.after(async () => {
    server.closeAllRuns?.();
    server.close();
    configurePaths();
    await fs.rm(root, { recursive: true, force: true });
  });

  const base = `http://127.0.0.1:${server.address().port}`;

  // 1. Empty profile list on first launch.
  const initial = await getJson(`${base}/settings/profiles`);
  assert.deepEqual(initial, []);

  // 2. List official source — should preview both Claude and Codex.
  const official = await getJson(`${base}/settings/credential-sources/official`);
  assert.equal(official.length, 2);
  const providers = official.map((e) => e.provider).sort();
  assert.deepEqual(providers, ['anthropic', 'openai']);
  for (const entry of official) {
    assert.equal(entry.authToken, undefined, 'token must be masked');
    assert.ok(entry.tokenPreview);
  }

  // 3. CC-Switch source is unavailable in this env.
  const ccSwitch = await getJson(`${base}/settings/credential-sources/cc-switch`);
  assert.deepEqual(ccSwitch, []);

  // 4. Import the Claude credential — lands under keys.anthropic.
  const importedClaude = await postJson(`${base}/settings/profiles/import`, {
    name: 'Claude Official',
    source: 'official',
    sourceId: 'claude',
    makeActive: true,
  });
  assert.equal(importedClaude.name, 'Claude Official');
  assert.equal(importedClaude.isCurrent, true);
  assert.ok(importedClaude.keys.anthropic);
  assert.equal(importedClaude.keys.anthropic.baseUrl, 'https://api.anthropic.com');
  assert.notEqual(importedClaude.keys.anthropic.key, 'sk-ant-test-token-aaaaa', 'key must be masked');

  // 5. Import the Codex credential — lands under keys.openai.
  const importedCodex = await postJson(`${base}/settings/profiles/import`, {
    name: 'Codex Official',
    source: 'official',
    sourceId: 'codex',
  });
  assert.ok(importedCodex.keys.openai);
  assert.equal(importedCodex.keys.openai.key.length > 0, true);
  assert.equal(importedCodex.isCurrent, false, 'second import without makeActive stays inactive');

  // 6. Profile list now contains both entries.
  const after = await getJson(`${base}/settings/profiles`);
  assert.equal(after.length, 2);
  assert.equal(after.filter((p) => p.isCurrent).length, 1);

  // 7. Active profile endpoint reflects the first import.
  const active = await getJson(`${base}/settings/active-profile`);
  assert.equal(active.id, importedClaude.id);

  // 8. Validation errors.
  const noName = await postJsonExpectError(
    `${base}/settings/profiles/import`,
    { source: 'official' },
    400,
  );
  assert.match(noName.error, /name is required/);

  const badSource = await postJsonExpectError(
    `${base}/settings/profiles/import`,
    { name: 'X', source: 'invalid' },
    400,
  );
  assert.match(badSource.error, /source must be/);

  const missingCred = await postJsonExpectError(
    `${base}/settings/profiles/import`,
    { name: 'X', source: 'cc-switch' },
    404,
  );
  assert.match(missingCred.error, /no credential found/);

  // 9. Delete the imported profiles.
  for (const profileId of [importedClaude.id, importedCodex.id]) {
    const del = await deleteJson(`${base}/settings/profiles/${profileId}`);
    assert.equal(del.ok, true);
  }
  const empty = await getJson(`${base}/settings/profiles`);
  assert.deepEqual(empty, []);
});

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
}

async function getJson(url) {
  const response = await fetch(url);
  const text = await response.text();
  assert.equal(response.ok, true, text);
  if (!text) return null;
  return JSON.parse(text);
}

async function postJson(url, body) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  assert.equal(response.ok, true, `${response.status}: ${text}`);
  return JSON.parse(text);
}

async function postJsonExpectError(url, body, expectedStatus) {
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  assert.equal(response.status, expectedStatus, `expected ${expectedStatus}, got ${response.status}`);
  return JSON.parse(await response.text());
}

async function deleteJson(url) {
  const response = await fetch(url, { method: 'DELETE' });
  const text = await response.text();
  assert.equal(response.ok, true, text);
  return JSON.parse(text);
}
