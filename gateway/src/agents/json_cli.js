'use strict';

const {
  killProcessTree,
  readLines,
  spawnCli,
} = require('../cli');

function runJsonCli({
  command,
  args,
  cwd,
  env,
  stdin,
  keepStdinOpen = false,
  agentId,
  onEvent,
  onText,
  onToolCall,
  onUsage,
  onAgentSessionId,
  onExit,
}) {
  let child;
  try {
    child = spawnCli(command, args, { cwd, env });
  } catch (error) {
    onExit({
      exitCode: -1,
      error: error.message,
    });
    return {
      pid: null,
      abort() {},
    };
  }
  const state = {
    lastFullTextByKey: new Map(),
    sawText: false,
    stderrLines: [],
  };
  readLines(child.stdout, (line) => {
    const raw = parseJsonLine(line);
    if (!raw) {
      onText(line.endsWith('\n') ? line : `${line}\n`);
      return;
    }
    const eventType = raw.type || raw.event || 'cli.event';
    onEvent({
      type: 'command.updated',
      data: { stream: 'stdout', eventType },
      raw,
    });
    const agentSessionId = extractAgentSessionId(raw);
    if (agentSessionId) onAgentSessionId(agentSessionId, raw);
    const delta = extractTextDelta(raw, state);
    if (delta) {
      state.sawText = true;
      onText(delta);
    }
    if (onToolCall) {
      const toolCall = extractToolCall(raw);
      if (toolCall) onToolCall(toolCall);
    }
    if (onUsage) {
      const usage = extractUsage(raw);
      if (usage) onUsage(usage);
    }
  });
  readLines(child.stderr, (line) => {
    state.stderrLines.push(line);
    if (state.stderrLines.length > 80) state.stderrLines.shift();
    onEvent({
      type: 'command.updated',
      data: { stream: 'stderr', text: line },
      raw: { line },
    });
  });
  if (stdin !== null && stdin !== undefined) {
    child.stdin.write(stdin + '\n');
  }
  // Close stdin unless the adapter wants to keep it open for later injection
  // (e.g. Codex which reads more lines from stdin as the user types).
  // Otherwise CLIs like Claude/OpenCode wait for EOF and emit
  // 'no stdin data received in 3s' warnings.
  if (!keepStdinOpen && child.stdin.writable) {
    child.stdin.end();
  }
  let settled = false;
  const finish = (result) => {
    if (settled) return;
    settled = true;
    onExit(result);
  };
  child.on('error', (error) => {
    finish({
      exitCode: -1,
      error: error.message,
    });
  });
  child.on('close', (exitCode) => {
    const stderr = state.stderrLines.join('\n').trim();
    finish({
      exitCode,
      error: exitCode === 0 ? null : stderr || `agent exited with code ${exitCode}`,
    });
  });
  return {
    pid: child.pid,
    write(text) {
      if (!settled && child.stdin.writable) {
        child.stdin.write(text + '\n');
        return true;
      }
      return false;
    },
    abort() {
      killProcessTree(child);
    },
  };
}

function extractTextDelta(raw, state) {
  if (typeof raw.delta === 'string') {
    rememberEmittedText(raw.delta, state);
    return raw.delta;
  }
  if (typeof raw.text_delta === 'string') {
    rememberEmittedText(raw.text_delta, state);
    return raw.text_delta;
  }
  if (typeof raw.content_delta === 'string') {
    rememberEmittedText(raw.content_delta, state);
    return raw.content_delta;
  }

  const properties = raw.properties || raw.data || {};
  const part = properties.part || raw.part;
  if (part && typeof part.text === 'string') {
    return suffixDelta(`part:${part.id || raw.type || 'text'}`, part.text, state);
  }

  if (raw.type === 'assistant' && raw.message) {
    const text = contentArrayText(raw.message.content);
    if (text) return suffixDelta('assistant', text, state);
  }

  if (raw.item && raw.item.role === 'assistant') {
    const text = contentArrayText(raw.item.content);
    if (text) return suffixDelta(`item:${raw.item.id || raw.type || 'assistant'}`, text, state);
  }

  if (raw.item && typeof raw.item.text === 'string' && raw.item.text) {
    return suffixDelta(`item:${raw.item.id || raw.type || 'agent_message'}`, raw.item.text, state);
  }

  if (raw.message && raw.message.role === 'assistant') {
    const text =
      typeof raw.message.content === 'string'
        ? raw.message.content
        : contentArrayText(raw.message.content);
    if (text) return suffixDelta(`message:${raw.message.id || raw.type || 'assistant'}`, text, state);
  }

  if (raw.role === 'assistant') {
    const text =
      typeof raw.content === 'string' ? raw.content : contentArrayText(raw.content);
    if (text) return suffixDelta(`assistant:${raw.id || raw.type || 'content'}`, text, state);
  }

  if (!state.sawText && typeof raw.result === 'string') return raw.result;
  return '';
}

function rememberEmittedText(delta, state) {
  const previous = state.lastFullTextByKey.get('assistant') || '';
  state.lastFullTextByKey.set('assistant', previous + delta);
}

function suffixDelta(key, fullText, state) {
  const previous = state.lastFullTextByKey.get(key) || '';
  state.lastFullTextByKey.set(key, fullText);
  if (!previous) return fullText;
  if (fullText.startsWith(previous)) return fullText.slice(previous.length);
  // Non-prefix case: agent sent reformatted/reset text. Skip to avoid
  // emitting the entire text as a delta (which would duplicate content).
  return '';
}

function contentArrayText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .map((item) => {
      if (typeof item === 'string') return item;
      if (!item || typeof item !== 'object') return '';
      if (typeof item.text === 'string') return item.text;
      if (typeof item.content === 'string') return item.content;
      return '';
    })
    .join('');
}

/**
 * Extract tool call info from agent JSON events.
 *
 * Codex:   { type: 'function_call', name: '...', arguments: '...' }
 *          or item.content[].type === 'function_call'
 * Claude:  { type: 'tool_use', name: '...', input: { ... } }
 *          or content[].type === 'tool_use'
 * OpenCode: handled natively via SSE part events.
 */
function extractToolCall(raw) {
  // Codex function_call at top level
  if (raw.type === 'function_call' && raw.name) {
    return {
      name: raw.name,
      input: tryParseJson(raw.arguments) || raw.arguments || '',
      status: raw.status || 'running',
      callId: raw.call_id,
    };
  }
  // Codex function_call_output
  if (raw.type === 'function_call_output') {
    return {
      name: raw.name || 'function_call',
      output: raw.output,
      status: 'completed',
      callId: raw.call_id,
    };
  }
  // Claude tool_use in content array
  if (raw.type === 'content_block_start' && raw.content_block?.type === 'tool_use') {
    return {
      name: raw.content_block.name,
      input: '',
      status: 'running',
      toolUseId: raw.content_block.id,
    };
  }
  if (raw.type === 'tool_use' && raw.name) {
    return {
      name: raw.name,
      input: raw.input || {},
      status: 'running',
      toolUseId: raw.id,
    };
  }
  if (raw.type === 'tool_result') {
    return {
      name: raw.name || 'tool',
      output: raw.content,
      status: raw.is_error ? 'error' : 'completed',
      toolUseId: raw.tool_use_id,
    };
  }
  // Codex item-level tool calls
  if (raw.item && Array.isArray(raw.item.content)) {
    for (const block of raw.item.content) {
      if (block.type === 'function_call' && block.name) {
        return {
          name: block.name,
          input: block.arguments || '',
          status: block.status || 'completed',
          callId: block.call_id,
        };
      }
    }
  }
  return null;
}

/**
 * Extract token usage info from agent JSON events.
 * Returns { inputTokens, outputTokens, totalTokens } or null.
 */
function extractUsage(raw) {
  // OpenAI / Codex: { usage: { input_tokens, output_tokens, total_tokens } }
  const usage = raw.usage || raw.token_usage;
  if (usage && typeof usage === 'object') {
    const input = usage.input_tokens || usage.prompt_tokens || 0;
    const output = usage.output_tokens || usage.completion_tokens || 0;
    const total = usage.total_tokens || input + output;
    if (total > 0) return { inputTokens: input, outputTokens: output, totalTokens: total };
  }
  // Claude: { message: { usage: ... } }
  if (raw.message?.usage) {
    const u = raw.message.usage;
    const input = u.input_tokens || 0;
    const output = u.output_tokens || 0;
    return { inputTokens: input, outputTokens: output, totalTokens: input + output };
  }
  // response.completed with usage at top level
  if (raw.type === 'response.completed' && raw.response?.usage) {
    const u = raw.response.usage;
    const input = u.input_tokens || u.prompt_tokens || 0;
    const output = u.output_tokens || u.completion_tokens || 0;
    return { inputTokens: input, outputTokens: output, totalTokens: input + output };
  }
  return null;
}

function extractAgentSessionId(raw) {
  if (raw.thread_id) return raw.thread_id;
  if (raw.threadId) return raw.threadId;
  if (raw.session_id) return raw.session_id;
  if (raw.sessionId) return raw.sessionId;
  if (raw.conversation_id) return raw.conversation_id;
  if (raw.conversationId) return raw.conversationId;
  if (raw.id && /session|thread|conversation/.test(String(raw.type || ''))) {
    return raw.id;
  }
  return null;
}

function parseJsonLine(line) {
  try {
    const parsed = JSON.parse(line);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch (_) {
    return null;
  }
}

function tryParseJson(value) {
  if (typeof value !== 'string') return null;
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch (_) {
    return null;
  }
}

module.exports = {
  runJsonCli,
  extractTextDelta,
  extractToolCall,
  extractUsage,
  extractAgentSessionId,
  parseJsonLine,
  tryParseJson,
};
