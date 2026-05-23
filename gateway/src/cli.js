'use strict';

const { spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

function resolveCodexCommand() {
  if (process.env.CODEX_BIN) return commandFromPath(process.env.CODEX_BIN);
  if (process.platform === 'win32') {
    const script = path.join(
      process.env.APPDATA || '',
      'npm',
      'node_modules',
      '@openai',
      'codex',
      'bin',
      'codex.js',
    );
    if (fs.existsSync(script)) {
      return { command: process.execPath, prefixArgs: [script], shell: false };
    }
  }
  return { command: 'codex', prefixArgs: [], shell: process.platform === 'win32' };
}

function resolveOpenCodeCommand() {
  if (process.env.OPENCODE_BIN) return commandFromPath(process.env.OPENCODE_BIN);
  if (process.platform === 'win32') {
    const exe = findGlobalNpmPackageBin('opencode-ai', ['bin', 'opencode.exe']);
    if (fs.existsSync(exe)) {
      return { command: exe, prefixArgs: [], shell: false };
    }
    const shim = path.join(process.env.APPDATA || '', 'npm', 'opencode.cmd');
    if (fs.existsSync(shim)) {
      return { command: shim, prefixArgs: [], shell: true };
    }
  }
  return {
    command: 'opencode',
    prefixArgs: [],
    shell: process.platform === 'win32',
  };
}

function resolveClaudeCommand() {
  if (process.env.CLAUDE_CODE_BIN) {
    return commandFromPath(process.env.CLAUDE_CODE_BIN);
  }
  if (process.platform === 'win32') {
    const exe = path.join(
      process.env.APPDATA || '',
      'npm',
      'node_modules',
      '@anthropic-ai',
      'claude-code',
      'bin',
      'claude.exe',
    );
    if (fs.existsSync(exe)) {
      return { command: exe, prefixArgs: [], shell: false };
    }
    const shim = path.join(process.env.APPDATA || '', 'npm', 'claude.cmd');
    if (fs.existsSync(shim)) {
      return { command: shim, prefixArgs: [], shell: true };
    }
  }
  return { command: 'claude', prefixArgs: [], shell: process.platform === 'win32' };
}

function commandFromPath(command) {
  const ext = path.extname(command).toLowerCase();
  if (process.platform === 'win32' && (ext === '.cmd' || ext === '.bat')) {
    return { command, prefixArgs: [], shell: true };
  }
  if (process.platform === 'win32' && ext === '.ps1') {
    return {
      command: 'powershell.exe',
      prefixArgs: ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', command],
      shell: false,
    };
  }
  return { command, prefixArgs: [], shell: false };
}

function findGlobalNpmPackageBin(packageName, relativeParts) {
  const nodeModules = path.join(process.env.APPDATA || '', 'npm', 'node_modules');
  const exact = path.join(nodeModules, packageName, ...relativeParts);
  if (fs.existsSync(exact)) return exact;

  let directories = [];
  try {
    directories = fs
      .readdirSync(nodeModules, { withFileTypes: true })
      .filter((entry) => (
        entry.isDirectory() &&
        entry.name.startsWith(`.${packageName}-`)
      ))
      .map((entry) => path.join(nodeModules, entry.name));
  } catch {
    return exact;
  }

  directories.sort((a, b) => {
    try {
      return fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs;
    } catch {
      return 0;
    }
  });

  for (const directory of directories) {
    const candidate = path.join(directory, ...relativeParts);
    if (fs.existsSync(candidate)) return candidate;
  }
  return exact;
}

function commandExists(spec) {
  if (spec.command === process.execPath) {
    return (spec.prefixArgs || []).every((arg) => fs.existsSync(arg));
  }
  if (path.isAbsolute(spec.command)) return fs.existsSync(spec.command);
  return findOnPath(spec.command) !== null;
}

function spawnCli(spec, args, options = {}) {
  const allArgs = [...(spec.prefixArgs || []), ...args];
  if (spec.shell && process.platform === 'win32') {
    return spawnWindowsShell(spec.command, allArgs, options);
  }
  return spawn(spec.command, allArgs, {
    cwd: options.cwd,
    env: { ...process.env, ...(options.env || {}) },
    stdio: ['pipe', 'pipe', 'pipe'],
  });
}

function spawnWindowsShell(command, args, options) {
  const line = [quoteWindowsArg(command), ...args.map(quoteWindowsArg)].join(' ');
  return spawn(process.env.ComSpec || 'cmd.exe', ['/d', '/s', '/c', line], {
    cwd: options.cwd,
    env: { ...process.env, ...(options.env || {}) },
    stdio: ['pipe', 'pipe', 'pipe'],
    windowsVerbatimArguments: false,
  });
}

function quoteWindowsArg(value) {
  const raw = String(value);
  if (raw.length === 0) return '""';
  return `"${raw.replace(/(["\\])/g, '\\$1')}"`;
}

function killProcessTree(child) {
  if (!child || child.killed) return;
  if (process.platform === 'win32' && child.pid) {
    spawn('taskkill', ['/pid', String(child.pid), '/t', '/f'], {
      stdio: 'ignore',
      windowsHide: true,
    });
    return;
  }
  child.kill('SIGTERM');
}

function readLines(stream, onLine, onChunk) {
  let buffer = '';
  stream.setEncoding('utf8');
  stream.on('data', (chunk) => {
    onChunk?.(chunk);
    buffer += chunk;
    const lines = buffer.split(/\r?\n/);
    buffer = lines.pop() || '';
    for (const line of lines) {
      if (line.trim().length > 0) onLine(line);
    }
  });
  stream.on('end', () => {
    if (buffer.trim().length > 0) onLine(buffer);
  });
}

async function runCapture(spec, args, options = {}) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawnCli(spec, args, options);
    } catch (error) {
      resolve({ exitCode: -1, stdout: '', stderr: error.message });
      return;
    }
    let stdout = '';
    let stderr = '';
    let settled = false;
    const timeoutMs = options.timeoutMs || 15000;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve(result);
    };
    const timer = setTimeout(() => {
      killProcessTree(child);
      finish({
        exitCode: -1,
        stdout,
        stderr: stderr || `command timed out after ${timeoutMs}ms`,
      });
    }, timeoutMs);
    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString('utf8');
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
    });
    child.on('error', (error) => {
      finish({ exitCode: -1, stdout, stderr: stderr || error.message });
    });
    child.on('close', (exitCode) => {
      finish({ exitCode, stdout, stderr });
    });
    child.stdin.end();
  });
}

function findOnPath(command) {
  const directories = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  const names = candidateNames(command);
  for (const directory of directories) {
    for (const name of names) {
      const candidate = path.join(directory, name);
      if (fs.existsSync(candidate)) return candidate;
    }
  }
  return null;
}

function candidateNames(command) {
  if (process.platform !== 'win32' || path.extname(command)) return [command];
  const extensions = (process.env.PATHEXT || '.EXE;.CMD;.BAT;.COM')
    .split(';')
    .filter(Boolean);
  return extensions.flatMap((ext) => [
    `${command}${ext.toLowerCase()}`,
    `${command}${ext.toUpperCase()}`,
  ]);
}

module.exports = {
  commandExists,
  killProcessTree,
  readLines,
  resolveClaudeCommand,
  resolveCodexCommand,
  resolveOpenCodeCommand,
  runCapture,
  spawnCli,
};
