# Streaming Activity Timeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an inline activity timeline so Codex and Claude Code runs show status, commands, and collapsible output while keeping final assistant answers readable.

**Architecture:** The gateway remains the source of normalized agent execution events. `runJsonCli` emits additive `activity.updated` events alongside existing `command.updated`, text deltas, and tool parts. Flutter stores bounded activity rows separately from messages and renders them in a compact timeline above the input area.

**Tech Stack:** Node.js `node:test`, Flutter 3.27/Dart/Riverpod, Material 3 widgets.

---

## File Structure

- Modify `gateway/src/agents/json_cli.js`: derive activity events from JSONL and stderr/stdout.
- Modify `gateway/test/agents.test.js`: add failing tests for activity emission.
- Modify `lib/state/gateway_chat_store.dart`: add activity models and `activity.updated` handling.
- Modify `test/state/gateway_chat_store_test.dart`: add failing store tests.
- Create `lib/ui/widgets/activity_timeline.dart`: render activity rows, command previews, and expandable output.
- Modify `lib/ui/pages/gateway_chat_page.dart`: place the timeline near the bottom of chat while streaming/recently completed.
- Create `test/ui/activity_timeline_test.dart`: verify key rendering behavior.

## Task 1: Gateway activity events

**Files:**
- Modify: `gateway/src/agents/json_cli.js`
- Test: `gateway/test/agents.test.js`

- [ ] **Step 1: Write failing tests**

Add tests to `gateway/test/agents.test.js` that spawn small Node scripts and collect `activity.updated` events:

```js
test('runJsonCli emits activity for function call lifecycle', async () => {
  const script = [
    'console.log(JSON.stringify({type:"function_call",call_id:"call-1",name:"shell",arguments:JSON.stringify({command:"npm test"}),status:"running"}));',
    'console.log(JSON.stringify({type:"function_call_output",call_id:"call-1",output:"ok\\n"}));',
    'process.exit(0);',
  ].join('');
  const activities = [];
  const result = await new Promise((resolve) => {
    runJsonCli({
      command: { command: process.execPath },
      args: ['-e', script],
      cwd: process.cwd(),
      stdin: null,
      onEvent: (event) => {
        if (event.type === 'activity.updated') activities.push(event.data.activity);
      },
      onText: () => {},
      onExit: resolve,
    });
  });
  assert.equal(result.exitCode, 0);
  assert.equal(activities.length, 2);
  assert.equal(activities[0].id, 'call-1');
  assert.equal(activities[0].kind, 'command');
  assert.equal(activities[0].status, 'running');
  assert.equal(activities[0].command, 'npm test');
  assert.equal(activities[1].id, 'call-1');
  assert.equal(activities[1].status, 'completed');
  assert.equal(activities[1].outputDelta, 'ok\n');
});

test('runJsonCli emits activity for stderr lines', async () => {
  const script = 'console.error("warning line");process.exit(0);';
  const activities = [];
  const result = await new Promise((resolve) => {
    runJsonCli({
      command: { command: process.execPath },
      args: ['-e', script],
      cwd: process.cwd(),
      stdin: null,
      onEvent: (event) => {
        if (event.type === 'activity.updated') activities.push(event.data.activity);
      },
      onText: () => {},
      onExit: resolve,
    });
  });
  assert.equal(result.exitCode, 0);
  assert.equal(activities.length, 1);
  assert.equal(activities[0].kind, 'output');
  assert.equal(activities[0].status, 'info');
  assert.equal(activities[0].stream, 'stderr');
  assert.equal(activities[0].outputDelta, 'warning line\n');
});
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
npm test --prefix gateway -- test/agents.test.js
```

Expected: the two new tests fail because no `activity.updated` events are emitted.

- [ ] **Step 3: Implement minimal activity normalization**

In `gateway/src/agents/json_cli.js`, add per-run sequence state and helper functions:

```js
const activity = activityFromRaw(raw, state, eventType);
if (activity) {
  onEvent({
    type: 'activity.updated',
    data: { activity },
    raw,
  });
}
```

For stderr non-JSON lines, emit:

```js
onEvent({
  type: 'activity.updated',
  data: {
    activity: outputActivity('stderr', line, state),
  },
  raw: { line },
});
```

Implement helpers in the same file:

```js
function activityFromRaw(raw, state, eventType) {
  const tool = extractToolCall(raw);
  if (tool) return activityFromToolCall(tool, state);
  const text = extractStatusText(raw);
  if (text) {
    return {
      id: `status-${++state.activitySeq}`,
      kind: 'status',
      status: 'info',
      title: text,
      sequence: state.activitySeq,
    };
  }
  return null;
}
```

Keep this implementation conservative: extract shell command names from `input.command`, `input.cmd`, or string arguments, use call ids when present, and mark outputs as completed.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
npm test --prefix gateway -- test/agents.test.js
```

Expected: all tests in `agents.test.js` pass.

## Task 2: Flutter activity state

**Files:**
- Modify: `lib/state/gateway_chat_store.dart`
- Test: `test/state/gateway_chat_store_test.dart`

- [ ] **Step 1: Write failing tests**

Add tests to `test/state/gateway_chat_store_test.dart`:

```dart
test('activity.updated inserts a renderable activity item', () async {
  final controller = GatewayChatStore(
    client: _FakeGatewayClient(
      eventsStream: Stream<GatewayEvent>.fromIterable([
        const GatewayEvent(
          type: 'activity.updated',
          sessionId: 's1',
          agentId: 'codex',
          timestampMs: 1,
          data: <String, dynamic>{
            'activity': <String, dynamic>{
              'id': 'a1',
              'kind': 'command',
              'status': 'running',
              'title': 'Running npm test',
              'command': 'npm test',
              'sequence': 1,
            },
          },
          raw: <String, dynamic>{},
          sseEvent: 'message',
        ),
      ]),
    ),
    sessionId: 's1',
  );
  addTearDown(controller.dispose);

  await Future<void>.delayed(Duration.zero);

  expect(controller.state.activities, hasLength(1));
  expect(controller.state.activities.single.id, 'a1');
  expect(controller.state.activities.single.command, 'npm test');
  expect(controller.state.activeTool?.name, 'npm test');
});

test('activity.updated appends output and completes existing item', () async {
  final controller = GatewayChatStore(
    client: _FakeGatewayClient(
      eventsStream: Stream<GatewayEvent>.fromIterable([
        const GatewayEvent(
          type: 'activity.updated',
          sessionId: 's1',
          agentId: 'codex',
          timestampMs: 1,
          data: <String, dynamic>{
            'activity': <String, dynamic>{
              'id': 'a1',
              'kind': 'command',
              'status': 'running',
              'title': 'Running npm test',
              'command': 'npm test',
              'sequence': 1,
            },
          },
          raw: <String, dynamic>{},
          sseEvent: 'message',
        ),
        const GatewayEvent(
          type: 'activity.updated',
          sessionId: 's1',
          agentId: 'codex',
          timestampMs: 2,
          data: <String, dynamic>{
            'activity': <String, dynamic>{
              'id': 'a1',
              'kind': 'command',
              'status': 'completed',
              'outputDelta': 'ok\n',
              'sequence': 1,
            },
          },
          raw: <String, dynamic>{},
          sseEvent: 'message',
        ),
      ]),
    ),
    sessionId: 's1',
  );
  addTearDown(controller.dispose);

  await Future<void>.delayed(Duration.zero);

  final activity = controller.state.activities.single;
  expect(activity.status, ActivityStatus.completed);
  expect(activity.output, 'ok\n');
  expect(controller.state.activeTool, isNull);
});
```

- [ ] **Step 2: Verify RED**

Run in Docker:

```powershell
docker run --rm -v "D:\Code\WorkSpace\remote-multi-agent:/app" -w /app ghcr.io/cirruslabs/flutter:3.27.1 bash -c "flutter test test/state/gateway_chat_store_test.dart"
```

Expected: fails because `activities` and `ActivityStatus` do not exist.

- [ ] **Step 3: Implement activity models and store handling**

In `lib/state/gateway_chat_store.dart`, add immutable `ActivityItem`, `ActivityKind`, and `ActivityStatus` near `TerminalLine`.

Add fields to `GatewayChatState`:

```dart
final List<ActivityItem> activities;
```

Initialize with `const <ActivityItem>[]`, add `copyWith`, and handle `activity.updated` in `_onEvent`.

Implement `_onActivityUpdated`:

- Read `event.data['activity']`.
- Upsert by `id`.
- Append `outputDelta` to existing `output`.
- Keep max 80 activity items.
- Set `activeTool` for running command/tool rows.
- Clear `activeTool` when the updated item becomes completed/error.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
docker run --rm -v "D:\Code\WorkSpace\remote-multi-agent:/app" -w /app ghcr.io/cirruslabs/flutter:3.27.1 bash -c "flutter test test/state/gateway_chat_store_test.dart"
```

Expected: gateway chat store tests pass.

## Task 3: Activity timeline widget

**Files:**
- Create: `lib/ui/widgets/activity_timeline.dart`
- Create: `test/ui/activity_timeline_test.dart`

- [ ] **Step 1: Write failing widget test**

Create `test/ui/activity_timeline_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/state/gateway_chat_store.dart';
import 'package:remote_multi_agent/ui/widgets/activity_timeline.dart';

void main() {
  testWidgets('renders command activity with collapsed output', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityTimeline(
            activities: const [
              ActivityItem(
                id: 'a1',
                kind: ActivityKind.command,
                status: ActivityStatus.completed,
                title: 'Ran npm test',
                command: 'npm test',
                output: 'line 1\nline 2\nline 3\nline 4\n',
                sequence: 1,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('Ran npm test'), findsOneWidget);
    expect(find.textContaining('line 1'), findsOneWidget);
    expect(find.textContaining('line 4'), findsNothing);
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.textContaining('line 4'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Verify RED**

Run:

```powershell
docker run --rm -v "D:\Code\WorkSpace\remote-multi-agent:/app" -w /app ghcr.io/cirruslabs/flutter:3.27.1 bash -c "flutter test test/ui/activity_timeline_test.dart"
```

Expected: fails because `ActivityTimeline` does not exist.

- [ ] **Step 3: Implement widget**

Create `lib/ui/widgets/activity_timeline.dart` with:

- `ActivityTimeline` stateless shell that hides when activities are empty.
- `_ActivityRow` stateful row for expand/collapse.
- Running rows use a small spinner.
- Completed rows use check icon.
- Error rows use error icon.
- Output preview shows first three lines collapsed and all output expanded.

Use existing Material icons and restrained colors from `Theme.of(context).colorScheme`.

- [ ] **Step 4: Verify GREEN**

Run:

```powershell
docker run --rm -v "D:\Code\WorkSpace\remote-multi-agent:/app" -w /app ghcr.io/cirruslabs/flutter:3.27.1 bash -c "flutter test test/ui/activity_timeline_test.dart"
```

Expected: widget test passes.

## Task 4: Chat page integration

**Files:**
- Modify: `lib/ui/pages/gateway_chat_page.dart`
- Test: covered by `flutter analyze` and existing tests.

- [ ] **Step 1: Integrate timeline**

Import:

```dart
import '../widgets/activity_timeline.dart';
```

Place above `AgentActivityBar`:

```dart
if (chatState.activities.isNotEmpty)
  ActivityTimeline(activities: chatState.activities),
```

Keep `AgentActivityBar` for very compact current action status. If the timeline
is too visually heavy, let it show only the most recent bounded list from state.

- [ ] **Step 2: Run targeted Flutter checks**

Run:

```powershell
docker run --rm -v "D:\Code\WorkSpace\remote-multi-agent:/app" -w /app ghcr.io/cirruslabs/flutter:3.27.1 bash -c "flutter analyze && flutter test test/state/gateway_chat_store_test.dart test/ui/activity_timeline_test.dart"
```

Expected: no analyzer issues and targeted tests pass.

## Task 5: Full verification and gateway restart

**Files:**
- No new files.

- [ ] **Step 1: Run full gateway tests**

Run:

```powershell
npm test --prefix gateway
```

Expected: all gateway tests pass.

- [ ] **Step 2: Run full Flutter checks in Docker**

Run:

```powershell
docker run --rm -v "D:\Code\WorkSpace\remote-multi-agent:/app" -w /app ghcr.io/cirruslabs/flutter:3.27.1 bash -c "flutter pub get && flutter analyze && flutter test"
```

Expected: analyzer clean and all tests pass.

- [ ] **Step 3: Restart gateway**

Find and stop the listener on port 4096, then start gateway hidden:

```powershell
$listener = Get-NetTCPConnection -LocalPort 4096 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) { Stop-Process -Id $listener.OwningProcess -Force }
Start-Sleep -Milliseconds 500
$env:GATEWAY_HOST='0.0.0.0'
Start-Process -FilePath node -ArgumentList 'src/index.js' -WorkingDirectory 'D:\Code\WorkSpace\remote-multi-agent\gateway' -WindowStyle Hidden
Start-Sleep -Seconds 2
Get-NetTCPConnection -LocalPort 4096 -State Listen -ErrorAction SilentlyContinue | Select-Object LocalAddress,LocalPort,OwningProcess
```

Expected: port 4096 is listening with a new Node process.

## Self-Review

- Spec coverage: gateway normalization, Flutter activity state, UI rendering,
  tests, and restart are covered.
- Placeholder scan: no TBD/TODO placeholders remain.
- Type consistency: `ActivityItem`, `ActivityKind`, `ActivityStatus`, and
  `ActivityTimeline` are introduced before use.
