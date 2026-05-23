# remote_multi_agent

A Flutter mobile client for local coding agents. Connects to a Node.js gateway
on your laptop, streams normalized agent events via SSE, and renders Claude Code,
Codex, and OpenCode sessions in one unified project workspace.

## Architecture

```text
Phone (Flutter app)
    │  HTTPS / SSE
    ▼
Gateway (Node.js · localhost:4096)
    │
    ├── Claude Code CLI
    ├── Codex CLI
    └── OpenCode CLI
```

The gateway owns local project directories, sessions, CLI processes, event
normalization, and filesystem/git operations. The Flutter app is a **thin
client** — no model keys, no shell commands, no direct filesystem access.

Credentials live in **gateway profiles** (`~/.gateway/profiles.json`). Multiple
profiles are supported, one active at a time. On first launch nothing is
auto-discovered — the user explicitly imports a credential (Anthropic / OpenAI)
from one of three sources via the settings page:

1. **Local config files** — `~/.claude/settings.json` (Claude) or
   `~/.codex/auth.json` (Codex)
2. **CC-Switch** — pick any Claude or Codex provider from
   `~/.cc-switch/cc-switch.db`
3. **Manual** — paste API key + base URL for any provider

## Features

- **Multi-agent chat** — Claude Code, Codex, OpenCode in one app
- **Real-time streaming** — SSE event stream with tool use, reasoning, diffs
- **Project workspace** — multiple projects, each with multiple sessions
- **Git operations** — status, diff, commit, pull, push from the app
- **File browser** — recursive file tree with syntax-highlighted viewer
- **Attachment support** — send images/files with messages
- **Model discovery** — auto-fetch available models from API provider
- **Material 3 UI** — monochrome theme, dark/light mode, haptic feedback

## Tech stack

| Layer | Stack |
|-------|-------|
| App | Flutter 3.27+, Dart ^3.5.0 |
| State | Riverpod |
| Networking | Dio + http (SSE) |
| UI | Material 3, flutter_markdown_plus, flutter_highlight |
| Gateway | Node.js (plain JS), JSON file-based store |

## Quick start

### Gateway

```bash
cd gateway
npm install    # no external deps beyond Node 20+
GATEWAY_HOST=0.0.0.0 node src/index.js
# Listening on http://0.0.0.0:4096
```

### Flutter app (development)

```bash
flutter pub get
flutter run -d chrome     # or connect a device
```

### iOS build (CI)

```bash
git push                              # triggers .github/workflows/ios.yml
gh run watch                          # tail the build log
gh run download --name ios-ipa        # pull the unsigned .ipa
# → Sideloadly / AltStore → install to iPhone
```

## Project layout

```
lib/
├── main.dart
├── api/
│   ├── gateway_client.dart          # REST + SSE client for the gateway
│   ├── git_client.dart              # Git operations via gateway
│   └── sse_stream.dart              # SSE subscriber with auto-reconnect
├── models/
│   ├── project.dart                 # Gateway project (working directory)
│   ├── gateway_session.dart         # Session within a project
│   ├── gateway_event.dart           # SSE event types
│   ├── message.dart                 # Chat message
│   ├── part.dart                    # text / reasoning / tool / step / image
│   ├── agent.dart                   # Agent metadata
│   └── session.dart                 # Legacy session model (used by file viewer)
├── state/
│   ├── settings_store.dart          # SharedPreferences-backed config
│   ├── project_store.dart           # Project list controller
│   ├── gateway_session_store.dart   # Session list per project
│   ├── gateway_chat_store.dart      # SSE → ChatState reducer
│   ├── gateway_client_provider.dart # Riverpod client provider
│   ├── gateway_providers.dart       # Riverpod glue for gateway stores
│   ├── agent_catalog_store.dart     # Available agents & models
│   └── notification_service.dart    # In-app notifications
├── ui/
│   ├── app.dart
│   ├── pages/
│   │   ├── home_page.dart           # Bottom nav: Projects / Git / Files / Settings
│   │   ├── project_list_page.dart   # All projects
│   │   ├── project_detail_page.dart # Sessions within a project
│   │   ├── gateway_chat_page.dart   # Chat with streaming + attachments
│   │   ├── agent_group_page.dart    # Create session with agent/model picker
│   │   ├── git_page.dart            # Git status, diff, commit, pull, push
│   │   ├── files_page.dart          # File tree browser + viewer
│   │   ├── diff_page.dart           # Side-by-side diff viewer
│   │   ├── search_page.dart         # Full-text search across sessions
│   │   └── settings_page.dart       # Server URL, theme, connection test
│   └── widgets/
│       ├── message_bubble.dart      # Chat bubble with context menu
│       ├── attachment_picker.dart   # Image/file picker + preview strip
│       ├── agent_badge.dart         # Monochrome agent label
│       ├── session_status_chip.dart # Animated status indicator
│       ├── model_picker.dart        # Model selection dropdown
│       ├── directory_picker.dart    # Remote directory browser
│       ├── shimmer_skeleton.dart    # Loading skeleton animation
│       └── parts/                   # Message part renderers
│           ├── text_part_view.dart
│           ├── reasoning_part_view.dart
│           ├── tool_part_view.dart
│           ├── step_part_view.dart
│           └── image_part_view.dart
└── theme.dart                       # Material 3 monochrome light/dark themes

gateway/
└── src/
    ├── index.js                     # Entry point
    ├── server.js                    # HTTP server + route handlers
    ├── agents.js                    # Agent adapters (Claude Code, Codex, OpenCode)
    ├── store.js                     # JSON file-based session/message store
    ├── cli.js                       # CLI process spawner
    ├── events.js                    # SSE event bus
    ├── fs_routes.js                 # /git/* and /files/* endpoints
    └── opencode_server.js           # OpenCode-specific server adapter
```

## App settings

| Field | Example | Notes |
|-------|---------|-------|
| Server URL | `http://10.x.x.x:4096` | Gateway address (LAN / Tailscale) |
| Bearer token | *(optional)* | For gateway auth if configured |

The app never holds upstream API keys — they are stored in the gateway's
profile store (`~/.gateway/profiles.json`) and imported on demand from one of
the three sources described above.

## Gateway API

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Server status + available agents |
| GET | `/projects` | List projects |
| POST | `/projects` | Create project |
| GET | `/projects/:id/sessions` | List sessions |
| POST | `/sessions` | Create session |
| POST | `/sessions/:id/message` | Send message (starts SSE stream) |
| GET | `/sessions/:id/events` | SSE event stream |
| GET | `/agents` | List available agents |
| GET | `/agents/:id/models` | List models for agent |
| GET | `/git/status?path=...` | Git status |
| GET | `/git/diff?path=...` | Git diff |
| POST | `/git/commit` | Git add + commit |
| POST | `/git/pull` | Git pull |
| POST | `/git/push` | Git push |
| GET | `/files?path=...` | Recursive file tree |
| GET | `/files/read?path=...` | Read file content |
| GET | `/search?q=...` | Full-text search |
| GET | `/settings/profiles` | List credential profiles (keys masked) |
| POST | `/settings/profiles` | Create profile manually |
| PATCH | `/settings/profiles/:id` | Update profile |
| DELETE | `/settings/profiles/:id` | Delete profile |
| POST | `/settings/profiles/:id/activate` | Make profile active |
| POST | `/settings/profiles/import` | Import from `official` or `cc-switch` |
| GET | `/settings/credential-sources/official` | Preview `~/.claude/settings.json` |
| GET | `/settings/credential-sources/cc-switch` | List CC-Switch Claude providers |
