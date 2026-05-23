# Remote Multi Agent Gateway

Local HTTP/SSE gateway for the Flutter mobile client. It owns filesystem
access, project directories, git operations, credentials, and agent execution;
the app only talks to this server.

## Supported Agents

- Codex: `codex exec --json`
- Claude Code: `claude -p --output-format stream-json --verbose`
- OpenCode: `opencode serve` HTTP/SSE proxy, with `opencode run --format json`
  fallback when server mode is unavailable

The gateway holds all API credentials itself in `~/.gateway/profiles.json`.
There is no implicit fallback to environment variables, CC-Switch, or
`~/.claude/settings.json` at agent run time; credentials must be explicitly
imported through the settings UI or the `/settings/profiles*` endpoints
documented below.

Multiple profiles are supported; exactly one is active at a time.

## Run

```powershell
cd gateway
npm start
```

Default URL:

```text
http://127.0.0.1:4096
```

For LAN or Tailscale access:

```powershell
$env:GATEWAY_HOST='0.0.0.0'
$env:GATEWAY_PORT='4096'
npm start
```

The first gateway version has no authentication. This is intentional for v1:
the gateway is meant to run on the user's machine and be reachable only from a
trusted LAN or Tailscale network. Keep the default `127.0.0.1` bind for local
testing. Use `GATEWAY_HOST=0.0.0.0` only when a trusted phone needs LAN access.

## Configuration

| Variable | Purpose |
| --- | --- |
| `GATEWAY_HOST` | Bind host, default `127.0.0.1`. |
| `GATEWAY_PORT` | Bind port, default `4096`. |
| `GATEWAY_DATA_FILE` | JSON store path, default `gateway/.data/store.json`. |
| `GATEWAY_DIRECTORIES` | Extra roots returned by `GET /directories`, separated by OS path delimiter. |
| `CODEX_BIN` | Override Codex executable path. |
| `CODEX_SANDBOX` | Codex sandbox mode, default `workspace-write`. |
| `CLAUDE_CODE_BIN` | Override Claude Code executable path. |
| `CLAUDE_CODE_MODELS` | Comma-separated Claude model aliases to show in the picker. |
| `CLAUDE_CODE_PERMISSION_MODE` | Optional Claude permission mode, for example `acceptEdits` or `dontAsk`. |
| `OPENCODE_BIN` | Override OpenCode executable path. |
| `OPENCODE_SERVER_URL` | Use an existing OpenCode server instead of starting `opencode serve`. |
| `OPENCODE_SERVER_PASSWORD` | Password for an existing OpenCode server, sent with OpenCode's Basic auth scheme. |
| `OPENCODE_SERVER_HOST` | Host for gateway-started OpenCode server, default `127.0.0.1`. |
| `OPENCODE_SERVER_PORT` | Port for gateway-started OpenCode server, default is a free port. |
| `OPENCODE_SERVER_START_TIMEOUT_MS` | Startup wait for `opencode serve`, default `45000`. |
| `OPENCODE_DEFAULT_MODEL` | Fallback model id when the app did not choose one, default `opencode/big-pickle`. |
| `OPENCODE_MODE` | OpenCode message mode, default `build`. |

## Agent Adapter Layout

Gateway agent adapters are split by agent:

```text
gateway/src/agents/
  index.js
  claude_code.js
  codex.js
  opencode.js
  common.js
```

Shared helpers live under `gateway/src/agents/`. The registry exposes the
normalized metadata, model lists, command lists, and message execution contract
used by the app.

For OpenCode, the gateway creates a native OpenCode session through
`POST /session?directory=...`, stores that id as `agentSessionId`, sends turns
through `POST /session/:id/message`, and bridges the global `/event` SSE stream
back into the gateway's per-session event endpoint.

## API

The gateway implements the app contract from `docs/development-spec.md`:

```text
GET  /health
GET  /projects
POST /projects
GET  /projects/:projectId
DELETE /projects/:projectId
GET  /directories
GET  /files/dirs?path=<path>
POST /files/mkdir
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

### Credentials

```text
GET  /settings/active-profile
GET  /settings/profiles
POST /settings/profiles
PATCH /settings/profiles/:profileId
DELETE /settings/profiles/:profileId
POST /settings/profiles/:profileId/activate
POST /settings/profiles/import
GET  /settings/credential-sources/official
GET  /settings/credential-sources/cc-switch
```

- `/settings/profiles`: CRUD over the gateway-owned credential store. Keys are
  returned masked.
- `/settings/credential-sources/official`: preview entries discoverable in
  known per-provider config files. Currently Claude uses
  `~/.claude/settings.json` and Codex uses `~/.codex/auth.json`.
- `/settings/credential-sources/cc-switch`: preview entries discoverable in
  `~/.cc-switch/cc-switch.db`. Returns `[]` if `node:sqlite` is unavailable.
- `/settings/profiles/import`: body
  `{ name, source, sourceId?, makeActive? }`, where `source` is `"official"` or
  `"cc-switch"`.

`/sessions/:sessionId/events` is SSE. Each event uses the normalized envelope:

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

## Test

```powershell
npm test --prefix gateway
```
