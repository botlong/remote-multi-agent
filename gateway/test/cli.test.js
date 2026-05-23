'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  commandExists,
  resolveOpenCodeCommand,
} = require('../src/cli');

test(
  'resolveOpenCodeCommand finds npm temp package installs on Windows',
  { skip: process.platform !== 'win32' },
  async (t) => {
    const root = await fs.mkdtemp(path.join(os.tmpdir(), 'rma-cli-'));
    const oldAppData = process.env.APPDATA;
    const oldBin = process.env.OPENCODE_BIN;
    t.after(async () => {
      if (oldAppData === undefined) delete process.env.APPDATA;
      else process.env.APPDATA = oldAppData;
      if (oldBin === undefined) delete process.env.OPENCODE_BIN;
      else process.env.OPENCODE_BIN = oldBin;
      await fs.rm(root, { recursive: true, force: true });
    });

    delete process.env.OPENCODE_BIN;
    process.env.APPDATA = root;

    const exe = path.join(
      root,
      'npm',
      'node_modules',
      '.opencode-ai-AbCdEf',
      'bin',
      'opencode.exe',
    );
    await fs.mkdir(path.dirname(exe), { recursive: true });
    await fs.writeFile(exe, '');

    const command = resolveOpenCodeCommand();

    assert.equal(command.command, exe);
    assert.deepEqual(command.prefixArgs, []);
    assert.equal(command.shell, false);
    assert.equal(commandExists(command), true);
  },
);
