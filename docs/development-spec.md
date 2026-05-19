# Development Spec

Reference date: 2026-05-19

This document describes the intended full product scope. Do not treat it as a reduced MVP.

## Product Goal

Build an iOS client for coding agents that can work with multiple project directories and multiple official agent backends:

- OpenCode
- Claude Code
- Codex

The app should feel like one product, but each agent must keep its own official behavior, command model, session model, and feature surface.

## Core Architecture

The system is split into two separately developed and separately deployed parts:

- iOS app
- Server gateway

The app is closed-source and can be distributed as a paid product.

The gateway can be open-source to increase user trust because it is the only component that talks to local files, project directories, shells, and official agent CLIs.

First gateway version does not need authentication.

## Security Boundary

The app must not execute code.

The app is responsible for:

- Selecting project directories exposed by the gateway.
- Selecting agent and model.
- Creating sessions.
- Sending user messages and slash commands.
- Receiving events.
- Rendering messages, tool calls, diffs, status, errors, and agent-specific UI.

The gateway is responsible for:

- Running agent CLIs.
- Reading and writing project files.
- Managing working directories.
- Managing sessions.
- Translating official CLI output into app events.
- Handling command execution, tool execution, permissions, MCP, hooks, skills, plugins, and other agent-specific features.

## Navigation Model

The app home route starts from project directories.

Target hierarchy:

`directory -> agent -> optional model -> session`

Recommended screens:

- Project list
- Project detail
- Agent group
- Session list
- Session chat
- Settings

Project detail should show all sessions grouped by agent, then by model if the agent exposes model selection.

## Project Model

A project represents a working directory on the gateway host.

Minimum project fields:

```json
{
  "id": "project-id",
  "name": "remote-multi-agent",
  "directory": "D:\\Code\\WorkSpace\\remote-multi-agent",
  "updatedAt": 1779177600000
}
```

The gateway should own project directory validation. The app should only select from gateway-provided directories or request a directory through a gateway directory picker endpoint.

## Agent Model

Each supported agent should be described by metadata returned from the gateway.

Minimum agent fields:

```json
{
  "id": "codex",
  "displayName": "Codex",
  "supportsModels": true,
  "supportsSlashCommands": true,
  "supportsAttachments": false,
  "supportsPermissions": true,
  "sessionKind": "thread",
  "commands": []
}
```

Initial agent ids:

- `opencode`
- `claude-code`
- `codex`

The app should not hard-code all capabilities. It can ship known UI defaults, but the gateway should return current capabilities so official CLI changes can be supported without an app release where possible.

## Session Model

Sessions belong to one project, one agent, and optionally one model.

Minimum session fields:

```json
{
  "id": "session-id",
  "projectId": "project-id",
  "directory": "D:\\Code\\WorkSpace\\remote-multi-agent",
  "agentId": "codex",
  "modelId": "gpt-5.1-codex",
  "title": "Implement project routing",
  "status": "idle",
  "createdAt": 1779177600000,
  "updatedAt": 1779178600000
}
```

Status values should include:

- `idle`
- `running`
- `waiting-for-approval`
- `error`
- `completed`

## New Session Flow

Flow:

1. User opens home.
2. User selects or adds a project directory.
3. User taps new conversation.
4. App asks gateway for available agents.
5. User selects agent.
6. App asks gateway for models and capabilities for that agent.
7. User selects model if supported or required.
8. App creates a session.
9. App opens the agent-specific chat screen.

The session must persist the selected directory, agent, and model.

## Chat UI Principle

Do not flatten all agents into one generic chat implementation.

Use a shared message rendering foundation, but each agent needs its own adapter and UI extensions.

Shared chat foundation:

- Message list
- Text messages
- Streaming assistant output
- Tool call cards
- File diff cards
- Error states
- Abort/stop action
- Attachment strip if supported

Agent-specific extensions:

- Slash command suggestions
- Command palette actions
- Permission prompts
- Model switching
- Compact/clear/status flows
- Agent-specific running status
- Agent-specific session resume semantics
- Agent-specific custom command discovery

## Agent Command Compatibility

Official command references are recorded in `docs/agent-commands.md`.

The app should support commands in three layers:

- Discover commands from gateway metadata.
- Provide agent-specific suggestions and shortcuts in the input UI.
- Send the raw slash command to the gateway unless the command requires app-side UX.

The app should not emulate official CLI internals.

If a command changes execution state, the gateway should execute it through the official CLI or equivalent official API and emit resulting events.

## Claude Code Requirements

Claude Code support should account for:

- Built-in slash commands.
- Project custom commands in `.claude/commands/*.md`.
- User custom commands in `~/.claude/commands/*.md`.
- Skills and skill frontmatter.
- MCP prompts.
- File references with `@path`.
- Permission workflows.
- Model switching.
- Session status and cost/status surfaces.

The app should expose Claude Code commands and features only when the gateway reports they are available.

## Codex Requirements

Codex support should account for:

- Built-in slash commands, including `/fast`.
- Reasoning effort and model switching.
- Permission and approval flows.
- Sandbox readable directory additions.
- Plans, goals, side/fork flows, running process list, and stop behavior.
- Skills, plugins, hooks, MCP, memories, and mentions when available.

`/fast` is feature-dependent and should be shown only when the gateway reports it for the active model.

## OpenCode Requirements

OpenCode support should account for:

- Built-in slash commands.
- Command aliases.
- `.opencode/commands/` custom commands.
- `opencode.json` configured commands.
- Agent and model frontmatter on custom commands.
- Session sharing and unsharing if supported by the gateway.
- Undo and redo where the official CLI/session supports it.

Existing OpenCode behavior in the current app should be preserved during the migration.

## Gateway API Shape

The exact API can evolve, but it should be organized around projects, agents, sessions, messages, and events.

Suggested endpoints:

```text
GET  /health

GET  /projects
POST /projects
GET  /projects/:projectId
DELETE /projects/:projectId

GET  /directories

GET  /agents
GET  /agents/:agentId
GET  /agents/:agentId/models
GET  /agents/:agentId/commands

GET  /projects/:projectId/sessions
POST /projects/:projectId/sessions

GET  /sessions/:sessionId
PATCH /sessions/:sessionId
DELETE /sessions/:sessionId

GET  /sessions/:sessionId/messages
POST /sessions/:sessionId/messages
POST /sessions/:sessionId/abort

GET  /sessions/:sessionId/events
```

`GET /sessions/:sessionId/events` should use SSE or WebSocket. SSE is simpler and already matches the existing code style.

## Gateway Event Shape

The gateway should normalize events enough for the app to render them, while still preserving raw agent-specific payloads.

Suggested event envelope:

```json
{
  "type": "message.delta",
  "sessionId": "session-id",
  "agentId": "codex",
  "timestamp": 1779177600000,
  "data": {},
  "raw": {}
}
```

Recommended event types:

- `session.started`
- `session.updated`
- `session.completed`
- `session.error`
- `message.created`
- `message.delta`
- `message.completed`
- `tool.started`
- `tool.updated`
- `tool.completed`
- `file.changed`
- `diff.created`
- `approval.requested`
- `approval.resolved`
- `command.started`
- `command.completed`
- `status.updated`

The `raw` field should preserve original CLI output or parsed official event payloads for debugging and future compatibility.

## App Implementation Direction

Recommended app modules:

- `ProjectStore`
- `AgentCatalogStore`
- `SessionStore`
- `ChatStore`
- `GatewayClient`
- `AgentChatAdapter`
- `OpenCodeChatAdapter`
- `ClaudeCodeChatAdapter`
- `CodexChatAdapter`

The current `CodexChatPage`, `CodexThreadStore`, `SessionListPage`, and OpenCode stores should be migrated toward this unified project/session model instead of remaining separate top-level chat experiences.

## Agent Chat Adapter Contract

Each adapter should define:

- How to create a session.
- How to send a message.
- How to send or execute a slash command.
- How to abort/stop a run.
- How to render extra session actions.
- Which command suggestions to expose.
- Which message parts it supports.
- How to interpret gateway events.

The shared chat page should delegate agent-specific decisions to the adapter.

## Non-Goals

These are explicit boundaries, not scope reductions:

- The app must not run official CLIs directly.
- The app must not read local project files directly.
- The app must not execute shell commands.
- The app must not hard-code behavior that belongs to a specific official CLI when the gateway can report it dynamically.

## Implementation Priority

Keep the full scope, but implement in dependency order:

1. Gateway/app protocol.
2. Project directory model.
3. Agent capability model.
4. Unified session model.
5. OpenCode migration into unified model.
6. Codex migration into unified model.
7. Claude Code adapter.
8. Agent-specific command palettes and chat actions.
9. Advanced permissions, MCP, skills, hooks, plugins, custom commands, and share/export surfaces.

