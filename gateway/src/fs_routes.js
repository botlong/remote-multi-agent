'use strict';

/**
 * Filesystem & Git helper routes.
 *
 * Endpoints:
 *   GET  /git/status?path=<dir>       → git status --porcelain
 *   GET  /git/diff?path=<dir>         → git diff
 *   POST /git/commit {path, message}  → git add -A && git commit -m "..."
 *   POST /git/pull   {path}           → git pull
 *   POST /git/push   {path}           → git push
 *   GET  /files?path=<dir>            → recursive file tree (JSON)
 *   GET  /files/read?path=<file>      → file content
 */

const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const fs = require('node:fs/promises');
const path = require('node:path');

const execFileAsync = promisify(execFile);

const MIME_TYPES = new Map([
  ['.png', 'image/png'],
  ['.jpg', 'image/jpeg'],
  ['.jpeg', 'image/jpeg'],
  ['.gif', 'image/gif'],
  ['.webp', 'image/webp'],
  ['.svg', 'image/svg+xml'],
  ['.bmp', 'image/bmp'],
  ['.ico', 'image/x-icon'],
]);

// Max depth for recursive file listing
const MAX_DEPTH = 6;
// Max total nodes returned
const MAX_NODES = 2000;
// Max file size to read (1MB)
const MAX_READ_SIZE = 1024 * 1024;

// Directories/files to skip
const SKIP_NAMES = new Set([
  'node_modules', '.git', '.dart_tool', '.idea', '.vscode',
  '__pycache__', '.next', 'build', '.build', 'dist',
  '.gradle', '.pub-cache', 'coverage',
]);

// ---------------------------------------------------------------------------
// Git helpers
// ---------------------------------------------------------------------------

async function gitExec(args, cwd) {
  try {
    const { stdout } = await execFileAsync('git', args, {
      cwd,
      timeout: 30_000,
      maxBuffer: 5 * 1024 * 1024,
    });
    return stdout;
  } catch (err) {
    // If git command fails, still return stderr/stdout
    if (err.stdout || err.stderr) {
      return err.stderr || err.stdout || err.message;
    }
    throw err;
  }
}

async function handleGit(method, pathname, searchParams, body) {
  const dir = (method === 'GET')
    ? searchParams.get('path') || ''
    : (body && body.path) || '';

  if (!dir) {
    return { status: 400, data: { error: 'path is required' } };
  }

  // Security: basic path traversal guard
  const resolved = path.resolve(dir);

  switch (pathname) {
    case '/git/status': {
      if (method !== 'GET') return null;
      const output = await gitExec(['status', '--porcelain'], resolved);
      return { status: 200, data: { output } };
    }
    case '/git/diff': {
      if (method !== 'GET') return null;
      const output = await gitExec(['diff'], resolved);
      return { status: 200, data: { output } };
    }
    case '/git/commit': {
      if (method !== 'POST') return null;
      const message = (body && body.message) || 'auto-commit';
      await gitExec(['add', '-A'], resolved);
      const output = await gitExec(['commit', '-m', message], resolved);
      return { status: 200, data: { output } };
    }
    case '/git/pull': {
      if (method !== 'POST') return null;
      const output = await gitExec(['pull'], resolved);
      return { status: 200, data: { output } };
    }
    case '/git/push': {
      if (method !== 'POST') return null;
      const output = await gitExec(['push'], resolved);
      return { status: 200, data: { output } };
    }
    default:
      return null;
  }
}

// ---------------------------------------------------------------------------
// File tree helpers
// ---------------------------------------------------------------------------

async function listFilesRecursive(dirPath, depth, counter) {
  if (depth > MAX_DEPTH || counter.count > MAX_NODES) return [];
  let entries;
  try {
    entries = await fs.readdir(dirPath, { withFileTypes: true });
  } catch {
    return [];
  }

  // Sort: directories first, then alphabetical
  entries.sort((a, b) => {
    const ad = a.isDirectory() ? 0 : 1;
    const bd = b.isDirectory() ? 0 : 1;
    if (ad !== bd) return ad - bd;
    return a.name.localeCompare(b.name);
  });

  const nodes = [];
  for (const entry of entries) {
    if (counter.count > MAX_NODES) break;
    if (SKIP_NAMES.has(entry.name)) continue;
    // Skip hidden files/dirs (except common ones like .env)
    if (entry.name.startsWith('.') && entry.name !== '.env') continue;

    const fullPath = path.join(dirPath, entry.name);
    counter.count++;

    if (entry.isDirectory()) {
      const children = await listFilesRecursive(fullPath, depth + 1, counter);
      nodes.push({
        name: entry.name,
        path: fullPath,
        isDirectory: true,
        children,
      });
    } else {
      nodes.push({
        name: entry.name,
        path: fullPath,
        isDirectory: false,
        children: [],
      });
    }
  }
  return nodes;
}

async function handleFiles(method, pathname, searchParams, body) {
  if (pathname === '/files' && method === 'GET') {
    const dir = searchParams.get('path') || '';
    if (!dir) return { status: 400, data: { error: 'path is required' } };
    const resolved = path.resolve(dir);
    const counter = { count: 0 };
    const tree = await listFilesRecursive(resolved, 0, counter);
    return { status: 200, data: tree };
  }

  if (pathname === '/files/read' && method === 'GET') {
    const filePath = searchParams.get('path') || '';
    if (!filePath) return { status: 400, data: { error: 'path is required' } };
    const resolved = path.resolve(filePath);

    // Check file size before reading
    let stat;
    try {
      stat = await fs.stat(resolved);
    } catch {
      return { status: 404, data: { error: 'file not found' } };
    }
    if (stat.isDirectory()) {
      return { status: 400, data: { error: 'path is a directory' } };
    }
    if (stat.size > MAX_READ_SIZE) {
      return { status: 413, data: { error: 'file too large (>1MB)' } };
    }

    const content = await fs.readFile(resolved, 'utf-8');
    return { status: 200, data: { content } };
  }

  if (pathname === '/files/raw' && method === 'GET') {
    const filePath = searchParams.get('path') || '';
    if (!filePath) return { status: 400, data: { error: 'path is required' } };
    const resolved = path.resolve(filePath);

    let stat;
    try {
      stat = await fs.stat(resolved);
    } catch {
      return { status: 404, data: { error: 'file not found' } };
    }
    if (stat.isDirectory()) {
      return { status: 400, data: { error: 'path is a directory' } };
    }
    if (stat.size > MAX_READ_SIZE) {
      return { status: 413, data: { error: 'file too large (>1MB)' } };
    }

    const body = await fs.readFile(resolved);
    return {
      status: 200,
      body,
      headers: {
        'Content-Type': contentTypeForFile(resolved),
        'Content-Length': String(body.length),
      },
    };
  }

  return null;
}

function contentTypeForFile(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  return MIME_TYPES.get(ext) || 'application/octet-stream';
}

// ---------------------------------------------------------------------------
// Exports
// ---------------------------------------------------------------------------

module.exports = { handleGit, handleFiles };
