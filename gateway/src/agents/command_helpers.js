'use strict';

const fs = require('node:fs/promises');
const path = require('node:path');

function commands(items) {
  const seen = new Set();
  const out = [];
  for (const item of items) {
    const name = typeof item === 'string' ? item : item.name;
    if (!name) continue;
    const normalized =
      name.startsWith('/') || name.startsWith('$') || name.startsWith('@')
        ? name
        : `/${name}`;
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

async function skillCommands({
  codexHome,
  agentsHome,
  pluginCache,
} = {}) {
  const out = [];
  const skillRoots = [
    codexHome ? path.join(codexHome, 'skills') : null,
    agentsHome ? path.join(agentsHome, 'skills') : null,
    pluginCache || null,
  ].filter(Boolean);

  for (const root of skillRoots) {
    const files = await findNamedFiles(root, 'SKILL.md', { maxDepth: 9, maxCount: 500 });
    for (const file of files) {
      const meta = await readSkillMeta(file);
      const skillName = sanitizeCommandName(meta.name || path.basename(path.dirname(file)));
      if (skillName) {
        out.push({
          name: `$${skillName}`,
          description: meta.description || 'Use Codex skill',
        });
      }

      const pluginName = pluginNameForSkill(file, pluginCache);
      if (pluginName) {
        out.push({
          name: `$${pluginName}`,
          description: 'Use Codex plugin',
        });
      }
    }
  }
  return out;
}

async function pluginMarkdownCommands(pluginCache) {
  if (!pluginCache) return [];
  const dirs = await findNamedDirectories(pluginCache, 'commands', {
    maxDepth: 6,
    maxCount: 100,
  });
  const out = [];
  for (const dir of dirs) {
    out.push(...(await markdownCommands(dir)));
  }
  return out;
}

function publicCommand(command) {
  return {
    command: command.command,
    prefixArgs: command.prefixArgs || [],
    shell: Boolean(command.shell),
  };
}

async function findNamedFiles(root, filename, { maxDepth, maxCount }) {
  const out = [];
  await walk(root, 0, async (entryPath, entry, depth) => {
    if (out.length >= maxCount) return false;
    if (entry.isFile() && entry.name === filename) out.push(entryPath);
    return depth < maxDepth;
  });
  return out;
}

async function findNamedDirectories(root, dirname, { maxDepth, maxCount }) {
  const out = [];
  await walk(root, 0, async (entryPath, entry, depth) => {
    if (out.length >= maxCount) return false;
    if (entry.isDirectory() && entry.name === dirname) {
      out.push(entryPath);
      return false;
    }
    return depth < maxDepth;
  });
  return out;
}

async function walk(directory, depth, visitor) {
  const entries = await fs.readdir(directory, { withFileTypes: true }).catch(() => []);
  for (const entry of entries) {
    const entryPath = path.join(directory, entry.name);
    const shouldDescend = await visitor(entryPath, entry, depth);
    if (shouldDescend !== false && entry.isDirectory()) {
      await walk(entryPath, depth + 1, visitor);
    }
  }
}

async function readSkillMeta(file) {
  try {
    const text = await fs.readFile(file, 'utf8');
    const frontmatter = text.match(/^---\s*([\s\S]*?)\s*---/);
    const block = frontmatter ? frontmatter[1] : text.slice(0, 2000);
    return {
      name: yamlScalar(block, 'name'),
      description: yamlScalar(block, 'description'),
    };
  } catch (_) {
    return {};
  }
}

function yamlScalar(text, key) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = text.match(new RegExp(`^\\s*${escaped}\\s*:\\s*["']?([^"'\\r\\n]+)`, 'm'));
  return match ? match[1].trim() : '';
}

function sanitizeCommandName(name) {
  return String(name || '')
    .trim()
    .replace(/^\$+/, '')
    .replace(/\s+/g, '-');
}

function pluginNameForSkill(file, pluginCache) {
  if (!pluginCache) return '';
  const relative = path.relative(pluginCache, file);
  if (relative.startsWith('..') || path.isAbsolute(relative)) return '';
  const parts = relative.split(path.sep).filter(Boolean);
  if (parts.length < 5 || parts[2] === 'skills') return '';
  if (parts[2] && parts[3] === 'skills') return sanitizeCommandName(parts[1]);
  return '';
}

module.exports = {
  commands,
  markdownCommands,
  opencodeJsonCommands,
  pluginMarkdownCommands,
  publicCommand,
  skillCommands,
};
