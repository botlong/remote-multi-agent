'use strict';

const { CodexAdapter } = require('./codex');
const { ClaudeCodeAdapter } = require('./claude_code');
const { OpenCodeAdapter } = require('./opencode');

class AgentRegistry {
  constructor({ openCodeServer, profileStore } = {}) {
    this.profileStore = profileStore || null;
    this.adapters = new Map(
      [
        new CodexAdapter({ profileStore }),
        new ClaudeCodeAdapter({ profileStore }),
        new OpenCodeAdapter({ server: openCodeServer, profileStore }),
      ].map((adapter) => [adapter.id, adapter]),
    );
  }

  get(agentId) {
    return this.adapters.get(agentId) || null;
  }

  async list(projectDirectory) {
    return Promise.all(
      [...this.adapters.values()].map((adapter) => adapter.metadata(projectDirectory)),
    );
  }

  close() {
    for (const adapter of this.adapters.values()) {
      adapter.close?.();
    }
  }
}

module.exports = { AgentRegistry };
