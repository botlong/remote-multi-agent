'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');

function commands(items) {
  const seen = new Set();
  const out = [];
  for (const item of items) {
    const name = typeof item === 'string' ? item : item.name;
    if (!name) continue;
    const normalized = name.startsWith('/') || name.startsWith('$') ? name : `/${name}`;
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    out.push({
      name: normalized,
      description: typeof item === 'object' ? item.description || '' : '',
    });
  }
  return out;
}

async function markdownCommands(directory) {
  if (!directory) return [];
  const entries = await fs.readdir(directory, { withFileTypes: true }).catch(() => []);
  const out = [];
  for (const entry of entries) {
    if (entry.isDirectory()) {
      const nested = await markdownCommands(path.join(directory, entry.name));
      out.push(...nested.map((command) => `${entry.name}:${command}`));
      continue;
    }
    if (!entry.name.endsWith('.md')) continue;
    out.push(entry.name.slice(0, -3));
  }
  return out;
}

async function opencodeJsonCommands(projectDirectory) {
  if (!projectDirectory) return [];
  const file = path.join(projectDirectory, 'opencode.json');
  try {
    const parsed = JSON.parse(await fs.readFile(file, 'utf8'));
    if (Array.isArray(parsed.commands)) {
      return parsed.commands.map((command) =>
        typeof command === 'string' ? command : command.name || command.id || '',
      );
    }
    if (parsed.commands && typeof parsed.commands === 'object') {
      return Object.keys(parsed.commands);
    }
  } catch (_) {
    // Ignore invalid or missing project config.
  }
  return [];
}

function publicCommand(command) {
  return {
    command: command.command,
    prefixArgs: command.prefixArgs || [],
    shell: Boolean(command.shell),
  };
}

module.exports = {
  commands,
  markdownCommands,
  opencodeJsonCommands,
  publicCommand,
};
