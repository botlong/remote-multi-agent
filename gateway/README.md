# Remote Multi Agent Gateway

Local HTTP/SSE gateway for the Flutter client. It owns filesystem access and
agent execution; the app only talks to this server.

## Supported Agents

- Codex: `codex exec --json`
- Claude Code: `claude -p --output-format stream-json --verbose`
- OpenCode: `opencode run --format json`

The gateway uses the CLI login state already configured on this machine.

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

The first gateway version has no authentication, matching
`docs/development-spec.md`. Bind to `127.0.0.1` by default, and expose
`0.0.0.0` only behind a trusted network such as Tailscale.

## Configuration

| Variable | Purpose |
| --- | --- |
| `GATEWAY_HOST` | Bind host, default `127.0.0.1`. |
| `GATEWAY_PORT` | Bind port, default `4096`. |
| `GATEWAY_DATA_FILE` | JSON store path, default `gateway/.data/store.json`. |
| `GATEWAY_DIRECTORIES` | Extra roots returned by `GET /directories`, separated by OS path delimiter. |
| `CODEX_BIN` | Override Codex executable path. |
| `CODEX_SANDBOX` | Codex sandbox mode, default `workspace-write`. |
| `CODEX_APPROVAL_POLICY` | Codex approval policy, default `never`. |
| `CLAUDE_CODE_BIN` | Override Claude Code executable path. |
| `CLAUDE_CODE_MODELS` | Comma-separated Claude model aliases to show in the picker. |
| `CLAUDE_CODE_PERMISSION_MODE` | Optional Claude permission mode, for example `acceptEdits` or `dontAsk`. |
| `OPENCODE_BIN` | Override OpenCode executable path. |

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
