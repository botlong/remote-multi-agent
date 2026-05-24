# Streaming Activity Timeline Design

Reference date: 2026-05-24

## Problem

Codex and Claude Code runs currently feel opaque in the Flutter app. The gateway
does forward JSONL records from the CLIs as `command.updated`, but most of those
events contain only structured `eventType` and `raw` payloads. The Flutter store
only appends `command.updated` entries when `data.text` exists, so structured
status, tool, and reasoning events are dropped from the user-facing UI.

The assistant message also mixes final answer text, tool cards, and stream state
inside one bubble. Long streaming text becomes cramped, while command progress is
either missing or hidden on the separate terminal screen.

## Goals

- Show an inline run timeline for the active turn, similar to Codex CLI output.
- Keep the final assistant answer readable and separate from command/status logs.
- Normalize Codex and Claude Code JSONL events enough for the app to render
  stable activity rows, while preserving raw payloads for debugging.
- Reuse existing terminal and tool rendering concepts where practical.
- Keep the implementation testable at the gateway event layer and Flutter store
  layer.

## Non-Goals

- Do not fully emulate official Codex or Claude CLI internals.
- Do not replace the terminal page; it remains the full raw log view.
- Do not persist every activity row as a message part in the conversation
  history. Activity rows are operational run state, not assistant content.
- Do not change agent credentials, model listing, or sandbox behavior in this
  work.

## Considered Approaches

### A. Inline activity timeline plus clean answer

The gateway emits normalized activity events. Flutter stores them separately
from messages and renders a compact timeline above the composer / near the
current assistant turn. Command output is collapsed with a preview. Final answer
text remains in the normal assistant message.

This is the recommended approach. It matches the requested CLI-like experience
without polluting final answers or exports.

### B. Terminal-first panel

Use the existing terminal page and add a compact live preview bar in chat. This
is smaller but still requires the user to switch screens to understand what the
agent is doing.

### C. Convert activity into message parts

Represent every status and command as `ToolPart` or new part types inside the
assistant bubble. This is easy to persist, but it keeps the current cramped
reading problem and makes exported conversations noisy.

## Event Design

Add normalized `activity.updated` events:

```json
{
  "type": "activity.updated",
  "sessionId": "s1",
  "agentId": "codex",
  "timestamp": 1779600000000,
  "data": {
    "activity": {
      "id": "codex-call-1",
      "kind": "command",
      "status": "running",
      "title": "Running npm test",
      "command": "npm test",
      "stream": "stdout",
      "outputDelta": "",
      "preview": "",
      "sequence": 3
    }
  },
  "raw": {}
}
```

Activity kinds:

- `status`: short agent status, reasoning summary, or phase update.
- `command`: shell or CLI command execution.
- `tool`: non-shell tool call.
- `output`: raw stdout/stderr that cannot be attached to a command.
- `checklist`: plan/checklist item state when the agent exposes it.

Activity statuses:

- `running`
- `completed`
- `error`
- `info`

Gateway behavior:

- `runJsonCli` continues to emit raw `command.updated` events.
- It additionally derives best-effort activity records from JSONL events and
  non-JSON stderr/stdout.
- Stable ids are based on call ids when present; otherwise they use a bounded
  per-run sequence.
- Tool calls are still emitted through `onToolCall` for compatibility.

Flutter behavior:

- `GatewayChatState` gains a bounded `activities` list.
- `activity.updated` upserts by id, appends output deltas, and updates status.
- `command.updated` with `data.text` still feeds the terminal page.
- Structured `command.updated` without text can also become terminal metadata if
  no normalized activity exists.

## UI Design

The chat screen shows:

- Normal message list as today.
- A compact live activity timeline while a run is active and for the most recent
  completed run.
- The timeline uses rows like:
  - `Running npm test -- test/agents.test.js`
  - `Ran npm test -- test/agents.test.js`
  - collapsed output preview with an expand control.
  - checklist rows with completed/pending/running state.
- Long output is collapsed by default, with a short preview and a full expanded
  monospaced block.
- The terminal page still shows raw stdout/stderr for full diagnostics.

Visual constraints:

- Dense operational UI, not a marketing layout.
- No nested cards. The timeline is a surface panel with individual rows.
- Stable row heights for collapsed output to avoid jumpy streaming.
- Monospace only for commands/output, not for normal assistant prose.

## Testing

Gateway tests:

- `runJsonCli` emits activity for JSON tool/function call start and output.
- `runJsonCli` emits activity for plain stderr/stdout lines.
- Existing text delta and tool extraction tests keep passing.

Flutter state tests:

- `activity.updated` inserts a new activity item.
- A second update with the same id appends output and updates status.
- Existing `command.updated` terminal behavior is preserved.

Widget tests:

- Timeline renders running/completed rows and collapses long output.

## Rollout

This is additive. Older gateway events still work, and the app can ignore
`activity.updated` if absent. Raw terminal logging remains available for
diagnosis.

## Self-Review

- No placeholders or TBD items remain.
- The design keeps activity state separate from persisted assistant content.
- Gateway and Flutter responsibilities are explicit.
- The scope is focused on streaming visibility and readability only.
