# remote_multi_agent

A Flutter mobile client for local coding agents. It connects to a Node.js
gateway on your laptop, streams normalized agent events via SSE, and renders
Claude Code, Codex, and OpenCode sessions in one unified project workspace.

## Architecture

```text
Phone (Flutter mobile app)
  |  HTTP / SSE
  v
Gateway (Node.js, localhost:4096 by default)
  |
  +-- Claude Code CLI
  +-- Codex CLI
  +-- OpenCode CLI / server
```

The gateway owns local project directories, sessions, CLI processes, event
normalization, and filesystem/git operations. The Flutter app is a thin client:
no model keys, no shell commands, and no direct filesystem access.

Credentials live in gateway profiles (`~/.gateway/profiles.json`). Multiple
profiles are supported, one active at a time. On first launch nothing is
auto-discovered; the user explicitly imports a credential from the settings
page or gateway settings endpoints.

## Gateway Access Model

The first version has no gateway authentication. Run the gateway on a trusted
LAN or Tailscale network only. The default bind host is `127.0.0.1`; use
`GATEWAY_HOST=0.0.0.0` only when the phone must reach the laptop over a trusted
network.

Web is not a supported target in v1. The app uses native/mobile-only APIs for
streaming and attachments.

## Features

- Multi-agent chat: Claude Code, Codex, and OpenCode in one app.
- Real-time streaming: SSE event stream with tool use, reasoning, diffs, and
  status updates.
- Project workspace: multiple projects, each with multiple sessions.
- Git operations: status, diff, commit, pull, and push from the app.
- File browser: recursive file tree with syntax-highlighted viewer.
- Attachment support: send images/files with messages when the agent supports
  them.
- Model discovery: fetch available models from the gateway.
- Material 3 UI: monochrome theme, dark/light mode, and haptic feedback.

## Tech Stack

| Layer | Stack |
| --- | --- |
| App | Flutter 3.27+, Dart ^3.5.0 |
| State | Riverpod |
| Networking | Dio + http (SSE) |
| UI | Material 3, flutter_markdown_plus, flutter_highlight |
| Gateway | Node.js, JSON file-based store |

## Quick Start

### Gateway

```bash
cd gateway
npm install
GATEWAY_HOST=0.0.0.0 node src/index.js
# Listening on http://0.0.0.0:4096
```

Use `GATEWAY_HOST=0.0.0.0` only on a trusted LAN or Tailscale network. For local
testing, keep the default `127.0.0.1` bind.

### Flutter app

```bash
flutter pub get
flutter test
```

Build and device runs target mobile platforms. iOS packaging is handled by CI.

### iOS build (CI)

```bash
git push
gh run watch
gh run download --name ios-ipa
```

Install the unsigned IPA with Sideloadly or AltStore.

## Project Layout

```text
lib/
  main.dart
  api/
    gateway_client.dart          # REST + SSE client for the gateway
    git_client.dart              # Git operations via gateway
    sse_stream.dart              # SSE subscriber with auto-reconnect
  models/
    project.dart                 # Gateway project
    gateway_session.dart         # Session within a project
    gateway_event.dart           # SSE event types
    message.dart                 # Chat message
    part.dart                    # text / reasoning / tool / step / image
    agent.dart                   # Agent metadata
    session.dart                 # Legacy session model used by file viewer
  state/
    settings_store.dart
    project_store.dart
    gateway_session_store.dart
    gateway_chat_store.dart
    gateway_client_provider.dart
    gateway_providers.dart
    agent_catalog_store.dart
    notification_service.dart
  ui/
    app.dart
    pages/
      home_page.dart
      project_list_page.dart
      project_detail_page.dart
      gateway_chat_page.dart
      agent_group_page.dart
      git_page.dart
      files_page.dart
      diff_page.dart
      search_page.dart
      settings_page.dart
    widgets/
      message_bubble.dart
      attachment_picker.dart
      agent_badge.dart
      session_status_chip.dart
      model_picker.dart
      directory_picker.dart
      shimmer_skeleton.dart
      parts/
        text_part_view.dart
        reasoning_part_view.dart
        tool_part_view.dart
        step_part_view.dart
        image_part_view.dart
  theme.dart

gateway/
  src/
    index.js                     # Entry point
    server.js                    # HTTP server + route handlers
    agents/
      index.js                   # Agent adapter registry
      registry.js                # Registry composition
      claude_code.js             # Claude Code adapter
      codex.js                   # Codex adapter
      opencode.js                # OpenCode adapter
      command_helpers.js         # Command metadata and discovery helpers
      json_cli.js                # JSON CLI runner and parsing helpers
      model_cache.js             # Shared model-list cache
      opencode_helpers.js        # OpenCode event/model normalization helpers
    store.js                     # JSON file-based session/message store
    cli.js                       # CLI process spawner
    events.js                    # SSE event bus
    fs_routes.js                 # /git/* and /files/* endpoints
    opencode_server.js           # OpenCode server adapter
```

Agent helpers handle command metadata/discovery, JSON CLI parsing, model-list
caching, and OpenCode event/model normalization.

## App Settings

| Field | Example | Notes |
| --- | --- | --- |
| Server URL | `http://10.x.x.x:4096` | Gateway address on trusted LAN or Tailscale |

The app never holds upstream API keys. They are stored in the gateway profile
store (`~/.gateway/profiles.json`) and imported on demand.

## Gateway API

| Method | Endpoint | Description |
| --- | --- | --- |
| GET | `/health` | Server status + available agents |
| GET | `/projects` | List projects |
| POST | `/projects` | Create project |
| GET | `/projects/:projectId` | Get project |
| DELETE | `/projects/:projectId` | Delete project |
| GET | `/projects/:projectId/sessions` | List sessions |
| POST | `/projects/:projectId/sessions` | Create session |
| GET | `/sessions/:sessionId` | Get session |
| PATCH | `/sessions/:sessionId` | Update session |
| DELETE | `/sessions/:sessionId` | Delete session |
| GET | `/sessions/:sessionId/messages` | List messages |
| POST | `/sessions/:sessionId/messages` | Send message |
| DELETE | `/sessions/:sessionId/messages/:messageId` | Delete message |
| POST | `/sessions/:sessionId/abort` | Abort running session |
| GET | `/sessions/:sessionId/events` | SSE event stream |
| GET | `/sessions/:sessionId/export?format=markdown|json` | Export messages |
| GET | `/sessions/:sessionId/diff` | Git diff for session directory |
| GET | `/agents` | List available agents |
| GET | `/agents/:id/models` | List models for agent |
| GET | `/agents/:id/commands` | List commands for agent |
| GET | `/git/status?path=...` | Git status |
| GET | `/git/diff?path=...` | Git diff |
| POST | `/git/commit` | Git add + commit |
| POST | `/git/pull` | Git pull |
| POST | `/git/push` | Git push |
| GET | `/files?path=...` | Recursive file tree |
| GET | `/files/read?path=...` | Read file content |
| GET | `/search?q=...` | Full-text search |
| GET | `/settings/profiles` | List credential profiles |
| POST | `/settings/profiles` | Create profile manually |
| PATCH | `/settings/profiles/:id` | Update profile |
| DELETE | `/settings/profiles/:id` | Delete profile |
| POST | `/settings/profiles/:id/activate` | Make profile active |
| POST | `/settings/profiles/import` | Import from official config or CC-Switch |
