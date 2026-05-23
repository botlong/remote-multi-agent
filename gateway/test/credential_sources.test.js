'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  configurePaths,
  listOfficialCredentials,
  listCcSwitchCredentials,
  loadCredential,
  maskCredentialEntry,
} = require('../src/credential_sources');

// Each test below isolates discovery to disposable paths so the host's real
// ~/.claude/, ~/.codex/, and ~/.cc-switch/ never participate.

async function withTempPaths(t, { claude, codex, ccSwitch } = {}) {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-cred-'));
  configurePaths({
    claudePath: claude ?? path.join(root, 'no-claude.json'),
    codexPath: codex ?? path.join(root, 'no-codex.json'),
    ccSwitchPath: ccSwitch ?? path.join(root, 'no-ccswitch.db'),
  });
  t.after(async () => {
    configurePaths();
    await fs.rm(root, { recursive: true, force: true });
  });
  return root;
}

test('listOfficialCredentials returns [] when no provider files exist', async (t) => {
  await withTempPaths(t);
  assert.deepEqual(await listOfficialCredentials(), []);
});

test('listOfficialCredentials parses ANTHROPIC_AUTH_TOKEN under provider=anthropic', async (t) => {
  const root = await withTempPaths(t);
  const file = path.join(root, 'claude.json');
  await fs.writeFile(
    file,
    JSON.stringify({
      env: {
        ANTHROPIC_AUTH_TOKEN: 'sk-ant-test-1234567890',
        ANTHROPIC_BASE_URL: 'https://api.anthropic.com',
      },
    }),
  );
  configurePaths({ claudePath: file });

  const result = await listOfficialCredentials();
  assert.equal(result.length, 1);
  assert.equal(result[0].provider, 'anthropic');
  assert.equal(result[0].source, 'official');
  assert.equal(result[0].id, 'claude');
  assert.equal(result[0].authToken, 'sk-ant-test-1234567890');
  assert.equal(result[0].baseUrl, 'https://api.anthropic.com');
});

test('listOfficialCredentials parses Codex auth.json under provider=openai', async (t) => {
  const root = await withTempPaths(t);
  const file = path.join(root, 'codex-auth.json');
  await fs.writeFile(
    file,
    JSON.stringify({
      OPENAI_API_KEY: 'sk-codex-test-abcdefghij',
    }),
  );
  configurePaths({ codexPath: file });

  const result = await listOfficialCredentials();
  assert.equal(result.length, 1);
  assert.equal(result[0].provider, 'openai');
  assert.equal(result[0].source, 'official');
  assert.equal(result[0].id, 'codex');
  assert.equal(result[0].authToken, 'sk-codex-test-abcdefghij');
});

test('listOfficialCredentials returns Claude AND Codex when both are configured', async (t) => {
  const root = await withTempPaths(t);
  const claudeFile = path.join(root, 'claude.json');
  const codexFile = path.join(root, 'codex.json');
  await fs.writeFile(claudeFile, JSON.stringify({ env: { ANTHROPIC_AUTH_TOKEN: 'sk-ant-1234567890ab' } }));
  await fs.writeFile(codexFile, JSON.stringify({ OPENAI_API_KEY: 'sk-openai-1234567890' }));
  configurePaths({ claudePath: claudeFile, codexPath: codexFile });

  const result = await listOfficialCredentials();
  assert.equal(result.length, 2);
  const providers = result.map((e) => e.provider).sort();
  assert.deepEqual(providers, ['anthropic', 'openai']);
});

test('listOfficialCredentials skips PROXY_MANAGED Claude tokens', async (t) => {
  const root = await withTempPaths(t);
  const file = path.join(root, 'claude.json');
  await fs.writeFile(
    file,
    JSON.stringify({ env: { ANTHROPIC_AUTH_TOKEN: 'PROXY_MANAGED' } }),
  );
  configurePaths({ claudePath: file });

  assert.deepEqual(await listOfficialCredentials(), []);
});

test('listOfficialCredentials skips local proxy baseUrl on Claude', async (t) => {
  const root = await withTempPaths(t);
  const file = path.join(root, 'claude.json');
  await fs.writeFile(
    file,
    JSON.stringify({
      env: {
        ANTHROPIC_AUTH_TOKEN: 'sk-ant-something-1234',
        ANTHROPIC_BASE_URL: 'http://127.0.0.1:8080',
      },
    }),
  );
  configurePaths({ claudePath: file });

  assert.deepEqual(await listOfficialCredentials(), []);
});

test('listOfficialCredentials handles invalid JSON gracefully', async (t) => {
  const root = await withTempPaths(t);
  const file = path.join(root, 'claude.json');
  await fs.writeFile(file, '{ not json');
  configurePaths({ claudePath: file });

  assert.deepEqual(await listOfficialCredentials(), []);
});

test('listCcSwitchCredentials returns [] when db does not exist', async (t) => {
  await withTempPaths(t);
  assert.deepEqual(await listCcSwitchCredentials(), []);
});

let sqliteAvailable = false;
try {
  require('node:sqlite');
  sqliteAvailable = true;
} catch {
  /* skip below */
}

test(
  'listCcSwitchCredentials reads Claude AND Codex providers',
  { skip: !sqliteAvailable },
  async (t) => {
    const { DatabaseSync } = require('node:sqlite');
    const root = await withTempPaths(t);
    const dbPath = path.join(root, 'cc-switch.db');

    const db = new DatabaseSync(dbPath);
    db.exec(`
      CREATE TABLE providers (
        id INTEGER PRIMARY KEY,
        app_type TEXT NOT NULL,
        name TEXT,
        settings_config TEXT,
        auth_config TEXT,
        is_current INTEGER DEFAULT 0
      );
    `);
    const insert = db.prepare(
      'INSERT INTO providers (id, app_type, name, settings_config, auth_config, is_current) VALUES (?, ?, ?, ?, ?, ?)',
    );
    insert.run(
      1, 'claude', 'Anthropic Prod',
      JSON.stringify({ env: { ANTHROPIC_AUTH_TOKEN: 'sk-ant-prod-aaaaaaaaaa', ANTHROPIC_BASE_URL: 'https://api.anthropic.com' } }),
      null, 1,
    );
    insert.run(
      2, 'claude', 'Anthropic Dev',
      JSON.stringify({ env: { ANTHROPIC_AUTH_TOKEN: 'sk-ant-dev-bbbbbbbbbb' } }),
      null, 0,
    );
    insert.run(
      3, 'codex', 'OpenAI Prod',
      '[model_provider]\nbase_url = "https://api.openai.com/v1"',
      JSON.stringify({ OPENAI_API_KEY: 'sk-openai-prod-cccc' }),
      1,
    );
    insert.run(4, 'gemini', 'Gemini (unsupported)', '{}', null, 0);
    db.close();

    configurePaths({ ccSwitchPath: dbPath });

    const result = await listCcSwitchCredentials();
    assert.equal(result.length, 3, 'should drop unsupported app_types');

    const claude = result.filter((e) => e.provider === 'anthropic');
    const openai = result.filter((e) => e.provider === 'openai');
    assert.equal(claude.length, 2);
    assert.equal(openai.length, 1);

    const prodClaude = claude.find((e) => e.label === 'Anthropic Prod');
    assert.equal(prodClaude.isCurrent, true);
    assert.equal(prodClaude.authToken, 'sk-ant-prod-aaaaaaaaaa');
    assert.equal(prodClaude.baseUrl, 'https://api.anthropic.com');

    assert.equal(openai[0].label, 'OpenAI Prod');
    assert.equal(openai[0].authToken, 'sk-openai-prod-cccc');
    assert.equal(openai[0].baseUrl, 'https://api.openai.com/v1');
  },
);

test(
  'loadCredential resolves cc-switch by id across providers',
  { skip: !sqliteAvailable },
  async (t) => {
    const { DatabaseSync } = require('node:sqlite');
    const root = await withTempPaths(t);
    const dbPath = path.join(root, 'cc-switch.db');
    const db = new DatabaseSync(dbPath);
    db.exec(
      'CREATE TABLE providers (id INTEGER PRIMARY KEY, app_type TEXT, name TEXT, settings_config TEXT, auth_config TEXT, is_current INTEGER)',
    );
    const insert = db.prepare(
      'INSERT INTO providers (id, app_type, name, settings_config, auth_config, is_current) VALUES (?, ?, ?, ?, ?, ?)',
    );
    insert.run(10, 'claude', 'Active', JSON.stringify({ env: { ANTHROPIC_AUTH_TOKEN: 'sk-active-1234567890' } }), null, 1);
    insert.run(11, 'codex', 'Other', '', JSON.stringify({ OPENAI_API_KEY: 'sk-other-9876543210' }), 0);
    db.close();

    configurePaths({ ccSwitchPath: dbPath });

    const explicit = await loadCredential({ source: 'cc-switch', sourceId: '11' });
    assert.equal(explicit.authToken, 'sk-other-9876543210');
    assert.equal(explicit.provider, 'openai');

    const fallback = await loadCredential({ source: 'cc-switch' });
    assert.equal(fallback.authToken, 'sk-active-1234567890');
    assert.equal(fallback.provider, 'anthropic');

    const missing = await loadCredential({ source: 'cc-switch', sourceId: '999' });
    assert.equal(missing, null);
  },
);

test('loadCredential resolves official by id across providers', async (t) => {
  const root = await withTempPaths(t);
  const claudeFile = path.join(root, 'claude.json');
  const codexFile = path.join(root, 'codex.json');
  await fs.writeFile(claudeFile, JSON.stringify({ env: { ANTHROPIC_AUTH_TOKEN: 'sk-ant-1234567890ab' } }));
  await fs.writeFile(codexFile, JSON.stringify({ OPENAI_API_KEY: 'sk-openai-1234567890' }));
  configurePaths({ claudePath: claudeFile, codexPath: codexFile });

  const claude = await loadCredential({ source: 'official', sourceId: 'claude' });
  assert.equal(claude.provider, 'anthropic');
  assert.equal(claude.authToken, 'sk-ant-1234567890ab');

  const codex = await loadCredential({ source: 'official', sourceId: 'codex' });
  assert.equal(codex.provider, 'openai');
  assert.equal(codex.authToken, 'sk-openai-1234567890');

  const first = await loadCredential({ source: 'official' });
  assert.ok(first, 'no sourceId returns first available');
});

test('maskCredentialEntry hides the raw token', () => {
  const masked = maskCredentialEntry({
    id: 'x',
    source: 'official',
    provider: 'anthropic',
    label: 'L',
    hasToken: true,
    authToken: 'sk-ant-supersecret-token-1234',
    baseUrl: null,
  });
  assert.equal(masked.authToken, undefined);
  assert.equal(masked.tokenPreview.startsWith('sk-ant-'), true);
  assert.equal(masked.tokenPreview.endsWith('234'), true);
  assert.equal(masked.provider, 'anthropic');
  assert.equal(masked.hasToken, true);
});

test('cache invalidates on configurePaths', async (t) => {
  const root = await withTempPaths(t);
  const fileA = path.join(root, 'a.json');
  const fileB = path.join(root, 'b.json');
  await fs.writeFile(fileA, JSON.stringify({ env: { ANTHROPIC_AUTH_TOKEN: 'sk-aaa-1234567890' } }));
  await fs.writeFile(fileB, JSON.stringify({ env: { ANTHROPIC_AUTH_TOKEN: 'sk-bbb-1234567890' } }));

  configurePaths({ claudePath: fileA });
  const a = await listOfficialCredentials();
  assert.equal(a[0].authToken, 'sk-aaa-1234567890');

  configurePaths({ claudePath: fileB });
  const b = await listOfficialCredentials();
  assert.equal(b[0].authToken, 'sk-bbb-1234567890');
});
