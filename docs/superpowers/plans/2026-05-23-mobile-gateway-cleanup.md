# Mobile-Only Gateway Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the app explicitly mobile/iOS-only for v1, keep the gateway LAN-only with no authentication, split the gateway agent adapters into one file per agent, and repair the project documentation.

**Architecture:** Keep the current Flutter app plus Node gateway architecture. Remove Web-facing project promises and unused gateway-auth UI, but do not add authentication. Split `gateway/src/agents.js` into a small facade plus focused modules under `gateway/src/agents/`, with `codex.js`, `claude_code.js`, and `opencode.js` each owning one adapter.

**Tech Stack:** Flutter 3.27/Dart, Riverpod, Node.js CommonJS, Node built-in test runner, PowerShell verification commands.

---

## Scope Check

This plan covers four tightly related cleanup tasks:

- Product target cleanup: v1 is mobile/iOS-oriented, not Web.
- Gateway access model cleanup: v1 is unauthenticated and intended for trusted LAN/Tailscale use.
- Gateway code organization: each agent adapter gets its own file.
- Documentation cleanup: docs must match those decisions and remove mojibake.

Authentication is a non-goal for this plan. Web compatibility is a non-goal for this plan. New agent features such as handoff, approve, or reject endpoints are outside this cleanup and should be planned separately.

## File Structure

Create:

- `gateway/src/agents/index.js` - public exports for the gateway agent module.
- `gateway/src/agents/registry.js` - `AgentRegistry` composition only.
- `gateway/src/agents/model_cache.js` - shared model cache helper.
- `gateway/src/agents/command_helpers.js` - shared command list and custom command helpers.
- `gateway/src/agents/json_cli.js` - shared JSON CLI runner and parsing helpers.
- `gateway/src/agents/codex.js` - Codex adapter and Codex argument builder.
- `gateway/src/agents/claude_code.js` - Claude Code adapter.
- `gateway/src/agents/opencode.js` - OpenCode adapter.
- `gateway/src/agents/opencode_helpers.js` - OpenCode event/model normalization helpers.
- `gateway/test/agents_split.test.js` - regression tests for new module boundaries.

Modify:

- `gateway/src/agents.js` - replace with compatibility facade.
- `lib/state/settings_store.dart` - remove gateway bearer-token state from v1 settings.
- `lib/state/gateway_client_provider.dart` - stop passing a bearer token from app settings.
- `lib/ui/pages/git_page.dart` - stop passing a bearer token from app settings.
- `lib/ui/pages/project_list_page.dart` - stop passing a bearer token to the directory picker.
- `lib/ui/pages/gateway_chat_page.dart` - stop passing a bearer token to the directory picker.
- `lib/ui/widgets/directory_picker.dart` - remove the bearer-token parameter and Authorization header.
- `lib/ui/pages/settings_page.dart` - remove the gateway bearer-token text field and controller wiring.
- `pubspec.yaml` - update description to mobile/iOS client.
- `README.md` - remove Web run instructions and document trusted LAN v1.
- `gateway/README.md` - clarify no gateway auth in v1 and trusted LAN/Tailscale operation.
- `docs/requirements.md` - clarify mobile-only v1 and no gateway auth.
- `docs/development-spec.md` - align target and security notes.
- `docs/workflow.md` - rewrite corrupted text as readable Chinese.
- `TODO.md` - rewrite corrupted roadmap as readable Chinese.
- `docs/optimization-plan.md` - rewrite or replace corrupted optimization plan with readable text.

Delete:

- `web/` - remove Flutter Web target files because Web is unsupported in v1.

Do not modify:

- `gateway/src/server.js` authentication behavior. It remains unauthenticated in this plan.
- `lib/api/gateway_client.dart`, `lib/api/git_client.dart`, and `lib/api/sse_stream.dart` bearer-token constructor support. Those optional parameters can remain as dormant client capability, but app settings should not expose or pass tokens in v1.

---

### Task 1: Remove Web Target and Gateway Auth UI From App Settings

**Files:**

- Delete: `web/**`
- Modify: `pubspec.yaml`
- Modify: `lib/state/settings_store.dart`
- Modify: `lib/state/gateway_client_provider.dart`
- Modify: `lib/ui/pages/git_page.dart`
- Modify: `lib/ui/pages/project_list_page.dart`
- Modify: `lib/ui/pages/gateway_chat_page.dart`
- Modify: `lib/ui/widgets/directory_picker.dart`
- Modify: `lib/ui/pages/settings_page.dart`

- [ ] **Step 1: Write the failing verification commands**

Run these before changing code. They should fail because Web files and bearer-token UI still exist.

```powershell
if (Test-Path web) {
  throw 'web directory still exists'
}
```

Expected: FAIL with `web directory still exists`.

```powershell
$matches = rg -n "_tokenCtrl|legacy gateway credential-setting wording|settings\.bearerToken|bearerToken:" lib/state lib/ui
if ($LASTEXITCODE -eq 0) {
  throw "gateway auth UI/settings references still exist`n$matches"
}
```

Expected: FAIL with matches in `settings_store.dart`, `settings_page.dart`, `git_page.dart`, `gateway_chat_page.dart`, `project_list_page.dart`, and `directory_picker.dart`.

- [ ] **Step 2: Delete the Flutter Web target files**

Run:

```powershell
git rm -r web
```

Expected: Git stages deletion of `web/index.html`, `web/manifest.json`, icons, and favicon files.

- [ ] **Step 3: Update `pubspec.yaml` description**

Replace the current description with:

```yaml
description: A mobile client for local coding agents through a trusted LAN gateway.
```

- [ ] **Step 4: Remove `bearerToken` from `AppSettings`**

In `lib/state/settings_store.dart`, change the settings model and persistence code to this shape:

```dart
@immutable
class AppSettings {
  const AppSettings({
    required this.baseUrl,
    required this.providerId,
    required this.modelId,
    this.themeMode = ThemeMode.system,
    this.lastAgentId = '',
    this.lastModelId = '',
    this.lastSessionId = '',
    this.lastProjectId = '',
  });

  final String baseUrl;
  final String providerId;
  final String modelId;
  final ThemeMode themeMode;
  final String lastAgentId;
  final String lastModelId;
  final String lastSessionId;
  final String lastProjectId;

  bool get isConfigured =>
      baseUrl.isNotEmpty && providerId.isNotEmpty && modelId.isNotEmpty;

  AppSettings copyWith({
    String? baseUrl,
    String? providerId,
    String? modelId,
    ThemeMode? themeMode,
    String? lastAgentId,
    String? lastModelId,
    String? lastSessionId,
    String? lastProjectId,
  }) =>
      AppSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        providerId: providerId ?? this.providerId,
        modelId: modelId ?? this.modelId,
        themeMode: themeMode ?? this.themeMode,
        lastAgentId: lastAgentId ?? this.lastAgentId,
        lastModelId: lastModelId ?? this.lastModelId,
        lastSessionId: lastSessionId ?? this.lastSessionId,
        lastProjectId: lastProjectId ?? this.lastProjectId,
      );

  static const empty = AppSettings(
    baseUrl: 'http://127.0.0.1:4096',
    providerId: 'opencode',
    modelId: 'big-pickle',
  );
}
```

Update `_load` and `update` so they no longer read or write `_kToken`:

```dart
static AppSettings _load(SharedPreferences p) {
  final themeModeIndex = p.getInt(_kThemeMode);
  return AppSettings(
    baseUrl: p.getString(_kBaseUrl) ?? AppSettings.empty.baseUrl,
    providerId: p.getString(_kProvider) ?? AppSettings.empty.providerId,
    modelId: p.getString(_kModel) ?? AppSettings.empty.modelId,
    themeMode: themeModeIndex != null && themeModeIndex < ThemeMode.values.length
        ? ThemeMode.values[themeModeIndex]
        : ThemeMode.system,
    lastAgentId: p.getString(_kLastAgent) ?? '',
    lastModelId: p.getString(_kLastModel) ?? '',
    lastSessionId: p.getString(_kLastSession) ?? '',
    lastProjectId: p.getString(_kLastProject) ?? '',
  );
}

Future<void> update(AppSettings next) async {
  state = next;
  await Future.wait([
    _prefs.setString(_kBaseUrl, next.baseUrl),
    _prefs.setString(_kProvider, next.providerId),
    _prefs.setString(_kModel, next.modelId),
    _prefs.setInt(_kThemeMode, next.themeMode.index),
    _prefs.setString(_kLastAgent, next.lastAgentId),
    _prefs.setString(_kLastModel, next.lastModelId),
    _prefs.setString(_kLastSession, next.lastSessionId),
    _prefs.setString(_kLastProject, next.lastProjectId),
  ]);
}
```

Remove this constant:

```dart
static const _kToken = 'oc.bearerToken';
```

Also update the file header to:

```dart
/// Persistent connection settings for the trusted LAN gateway.
///
/// Stored in SharedPreferences so the app remembers them across launches.
```

- [ ] **Step 5: Stop passing bearer tokens from providers and pages**

Replace `lib/state/gateway_client_provider.dart` with:

```dart
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gateway_client.dart';
import 'settings_store.dart';

final gatewayClientProvider = Provider<GatewayClient>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  final client = GatewayClient(
    baseUrl: Uri.parse(settings.baseUrl),
  );
  ref.onDispose(client.close);
  return client;
});
```

In `lib/ui/pages/git_page.dart`, update the provider to:

```dart
final gitClientProvider = Provider<GitClient>((ref) {
  final s = ref.watch(settingsControllerProvider);
  final client = GitClient(baseUrl: Uri.parse(s.baseUrl));
  ref.onDispose(client.close);
  return client;
});
```

In `lib/ui/pages/project_list_page.dart`, update the directory picker call to:

```dart
final directory = await showDirectoryPicker(
  context,
  gatewayBaseUrl: settings.baseUrl,
  initialPath: 'D:\\',
);
```

In `lib/ui/pages/gateway_chat_page.dart`, update the directory picker call to:

```dart
final path = await showDirectoryPicker(
  context,
  gatewayBaseUrl: settings.baseUrl,
  initialPath: widget.project.directory,
);
```

- [ ] **Step 6: Remove bearer-token support from `directory_picker.dart` UI plumbing**

Update the public function signature to:

```dart
Future<String?> showDirectoryPicker(
  BuildContext context, {
  required String gatewayBaseUrl,
  String? initialPath,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _DirectoryPickerSheet(
      gatewayBaseUrl: gatewayBaseUrl,
      initialPath: initialPath ?? 'D:\\',
    ),
  );
}
```

Update `_DirectoryPickerSheet` to remove `bearerToken`:

```dart
class _DirectoryPickerSheet extends StatefulWidget {
  const _DirectoryPickerSheet({
    required this.gatewayBaseUrl,
    required this.initialPath,
  });

  final String gatewayBaseUrl;
  final String initialPath;

  @override
  State<_DirectoryPickerSheet> createState() => _DirectoryPickerSheetState();
}
```

Update the `Dio` initialization to:

```dart
_dio = Dio(
  BaseOptions(
    baseUrl: widget.gatewayBaseUrl.replaceAll(RegExp(r'/$'), ''),
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ),
);
```

- [ ] **Step 7: Remove bearer-token UI from `settings_page.dart`**

Make these edits:

- Remove the `_tokenCtrl` field.
- Remove `_tokenCtrl = TextEditingController(...)` from `initState`.
- Remove `_tokenCtrl.dispose()` from `dispose`.
- Remove every `bearerToken: _tokenCtrl.text.trim(),` argument.
- Remove the `TextField` whose label is the legacy gateway token setting.
- Remove `bearerToken` from `_ProfileEditorPage` constructor and usages if it is only passed through from the old settings field.

After editing, this command should print no matches:

```powershell
rg -n "_tokenCtrl|legacy gateway credential-setting wording|settings\.bearerToken|bearerToken:" lib/state lib/ui
```

- [ ] **Step 8: Run verification for Task 1**

Run:

```powershell
if (Test-Path web) {
  throw 'web directory still exists'
}
```

Expected: PASS with no output.

Run:

```powershell
rg -n "_tokenCtrl|legacy gateway credential-setting wording|settings\.bearerToken|bearerToken:" lib/state lib/ui
```

Expected: no matches and exit code 1.

Run:

```powershell
MSYS_NO_PATHCONV=1 docker run --rm -v "D:\Code\WorkSpace\remote-multi-agent:/app" -w /app ghcr.io/cirruslabs/flutter:3.27.1 bash -lc "flutter pub get && flutter test"
```

Expected: Flutter tests pass. If Docker is unavailable, run `flutter test` in a Flutter 3.27+ environment and record that Docker was unavailable.

- [ ] **Step 9: Commit Task 1**

```powershell
git add pubspec.yaml lib/state/settings_store.dart lib/state/gateway_client_provider.dart lib/ui/pages/git_page.dart lib/ui/pages/project_list_page.dart lib/ui/pages/gateway_chat_page.dart lib/ui/widgets/directory_picker.dart lib/ui/pages/settings_page.dart web
git commit -m "chore: make v1 mobile-only and remove gateway auth UI"
```

---

### Task 2: Add Module-Boundary Tests for Agent Split

**Files:**

- Create: `gateway/test/agents_split.test.js`

- [ ] **Step 1: Write the failing tests**

Create `gateway/test/agents_split.test.js`:

```javascript
'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');

test('agent facade exports registry and adapter utilities', () => {
  const agents = require('../src/agents');

  assert.equal(typeof agents.AgentRegistry, 'function');
  assert.equal(typeof agents.CodexAdapter, 'function');
  assert.equal(typeof agents.ClaudeCodeAdapter, 'function');
  assert.equal(typeof agents.OpenCodeAdapter, 'function');
  assert.equal(typeof agents.buildCodexArgs, 'function');
  assert.equal(typeof agents.normalizeOpenCodeEvent, 'function');
  assert.equal(typeof agents.runJsonCli, 'function');
});

test('each agent adapter is importable from its dedicated file', () => {
  const { CodexAdapter, buildCodexArgs } = require('../src/agents/codex');
  const { ClaudeCodeAdapter } = require('../src/agents/claude_code');
  const { OpenCodeAdapter } = require('../src/agents/opencode');

  assert.equal(new CodexAdapter().id, 'codex');
  assert.equal(new ClaudeCodeAdapter().id, 'claude-code');
  assert.equal(new OpenCodeAdapter({
    server: {
      externalBaseUrl: 'http://127.0.0.1:1234',
      baseUrl: null,
      request() {
        throw new Error('not used');
      },
      close() {},
    },
  }).id, 'opencode');

  assert.deepEqual(
    buildCodexArgs({
      directory: 'D:\\Code\\WorkSpace\\remote-multi-agent',
      modelId: 'gpt-5.3-codex',
      agentSessionId: null,
      raw: { sandbox: 'workspace-write' },
    }),
    [
      'exec',
      '--json',
      '--color',
      'never',
      '--cd',
      'D:\\Code\\WorkSpace\\remote-multi-agent',
      '--sandbox',
      'workspace-write',
      '--skip-git-repo-check',
      '--model',
      'gpt-5.3-codex',
      '-',
    ],
  );
});
```

- [ ] **Step 2: Run the tests and verify they fail**

```powershell
npm test --prefix gateway -- agents_split.test.js
```

Expected: FAIL because `../src/agents/codex`, `../src/agents/claude_code`, and `../src/agents/opencode` do not exist yet.

- [ ] **Step 3: Commit the failing tests**

```powershell
git add gateway/test/agents_split.test.js
git commit -m "test: cover gateway agent module boundaries"
```

---

### Task 3: Extract Shared Gateway Agent Helpers

**Files:**

- Create: `gateway/src/agents/model_cache.js`
- Create: `gateway/src/agents/command_helpers.js`
- Create: `gateway/src/agents/json_cli.js`
- Create: `gateway/src/agents/opencode_helpers.js`
- Modify: `gateway/src/agents.js`

- [ ] **Step 1: Create `model_cache.js`**

Create `gateway/src/agents/model_cache.js`:

```javascript
'use strict';

const MODEL_CACHE_TTL = 5 * 60 * 1000;
const modelCache = new Map();

function cachedModels(key, fetchFn) {
  const entry = modelCache.get(key);
  if (entry && Date.now() - entry.ts < MODEL_CACHE_TTL) return entry.promise;
  const promise = fetchFn().then((models) => {
    modelCache.set(key, { ts: Date.now(), promise: Promise.resolve(models) });
    return models;
  }).catch((err) => {
    modelCache.delete(key);
    throw err;
  });
  modelCache.set(key, { ts: Date.now(), promise });
  return promise;
}

module.exports = { cachedModels, modelCache };
```

- [ ] **Step 2: Create `command_helpers.js`**

Move `commands`, `markdownCommands`, `opencodeJsonCommands`, and `publicCommand` from `gateway/src/agents.js` into `gateway/src/agents/command_helpers.js`.

The file must export exactly:

```javascript
module.exports = {
  commands,
  markdownCommands,
  opencodeJsonCommands,
  publicCommand,
};
```

The moved implementations must keep the same behavior:

- `commands(items)` deduplicates slash commands.
- `markdownCommands(directory)` recursively reads `.md` command files.
- `opencodeJsonCommands(projectDirectory)` reads `opencode.json`.
- `publicCommand(command)` returns `{ command, prefixArgs, shell }`.

- [ ] **Step 3: Create `json_cli.js`**

Move these functions from `gateway/src/agents.js` into `gateway/src/agents/json_cli.js`:

- `runJsonCli`
- `extractTextDelta`
- `rememberEmittedText`
- `suffixDelta`
- `contentArrayText`
- `extractToolCall`
- `extractUsage`
- `extractAgentSessionId`
- `parseJsonLine`
- `tryParseJson`

At the top of the new file, import the CLI helpers:

```javascript
'use strict';

const {
  killProcessTree,
  readLines,
  spawnCli,
} = require('../cli');
```

The file must export:

```javascript
module.exports = {
  runJsonCli,
  extractTextDelta,
  extractToolCall,
  extractUsage,
  extractAgentSessionId,
  parseJsonLine,
  tryParseJson,
};
```

- [ ] **Step 4: Create `opencode_helpers.js`**

Move these functions from `gateway/src/agents.js` into `gateway/src/agents/opencode_helpers.js`:

- `providerModels`
- `compactOpenCodeModel`
- `splitOpenCodeModel`
- `normalizeOpenCodeEvent`
- `openCodeEventSessionId`
- `openCodeTerminalResult`
- `openCodeErrorMessage`

The file must export:

```javascript
module.exports = {
  providerModels,
  splitOpenCodeModel,
  normalizeOpenCodeEvent,
  openCodeEventSessionId,
  openCodeTerminalResult,
};
```

- [ ] **Step 5: Run gateway tests**

```powershell
npm test --prefix gateway
```

Expected: Existing tests still pass or fail only because adapter files have not been created. If syntax errors appear in the new helper modules, fix those before continuing.

- [ ] **Step 6: Commit shared helper extraction**

```powershell
git add gateway/src/agents/model_cache.js gateway/src/agents/command_helpers.js gateway/src/agents/json_cli.js gateway/src/agents/opencode_helpers.js
git commit -m "refactor: extract shared gateway agent helpers"
```

---

### Task 4: Move Each Agent Adapter Into Its Own File

**Files:**

- Create: `gateway/src/agents/codex.js`
- Create: `gateway/src/agents/claude_code.js`
- Create: `gateway/src/agents/opencode.js`
- Create: `gateway/src/agents/registry.js`
- Create: `gateway/src/agents/index.js`
- Modify: `gateway/src/agents.js`

- [ ] **Step 1: Create `codex.js`**

Move `CODEX_COMMANDS`, `CodexAdapter`, `buildCodexArgs`, and `compactCodexModel` from `gateway/src/agents.js` into `gateway/src/agents/codex.js`.

Use these imports:

```javascript
'use strict';

const {
  commandExists,
  resolveCodexCommand,
  runCapture,
} = require('../cli');
const { cachedModels } = require('./model_cache');
const { commands, publicCommand } = require('./command_helpers');
const { runJsonCli } = require('./json_cli');
```

The file must end with:

```javascript
module.exports = {
  CodexAdapter,
  CODEX_COMMANDS,
  buildCodexArgs,
};
```

- [ ] **Step 2: Create `claude_code.js`**

Move `CLAUDE_COMMANDS` and `ClaudeCodeAdapter` from `gateway/src/agents.js` into `gateway/src/agents/claude_code.js`.

Use these imports:

```javascript
'use strict';

const os = require('node:os');
const path = require('node:path');

const {
  commandExists,
  resolveClaudeCommand,
} = require('../cli');
const { cachedModels } = require('./model_cache');
const { commands, markdownCommands, publicCommand } = require('./command_helpers');
const { runJsonCli } = require('./json_cli');
```

The file must end with:

```javascript
module.exports = {
  ClaudeCodeAdapter,
  CLAUDE_COMMANDS,
};
```

- [ ] **Step 3: Create `opencode.js`**

Move `OPENCODE_COMMANDS` and `OpenCodeAdapter` from `gateway/src/agents.js` into `gateway/src/agents/opencode.js`.

Use these imports:

```javascript
'use strict';

const path = require('node:path');

const {
  commandExists,
  resolveOpenCodeCommand,
  runCapture,
} = require('../cli');
const { OpenCodeServerManager } = require('../opencode_server');
const { cachedModels } = require('./model_cache');
const { commands, markdownCommands, opencodeJsonCommands, publicCommand } = require('./command_helpers');
const { runJsonCli } = require('./json_cli');
const {
  providerModels,
  splitOpenCodeModel,
  normalizeOpenCodeEvent,
  openCodeEventSessionId,
  openCodeTerminalResult,
} = require('./opencode_helpers');
```

The file must end with:

```javascript
module.exports = {
  OpenCodeAdapter,
  OPENCODE_COMMANDS,
  normalizeOpenCodeEvent,
};
```

- [ ] **Step 4: Create `registry.js`**

Create `gateway/src/agents/registry.js`:

```javascript
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
```

- [ ] **Step 5: Create `index.js` and facade**

Create `gateway/src/agents/index.js`:

```javascript
'use strict';

const { AgentRegistry } = require('./registry');
const { CodexAdapter, buildCodexArgs } = require('./codex');
const { ClaudeCodeAdapter } = require('./claude_code');
const { OpenCodeAdapter, normalizeOpenCodeEvent } = require('./opencode');
const { runJsonCli } = require('./json_cli');

module.exports = {
  AgentRegistry,
  CodexAdapter,
  ClaudeCodeAdapter,
  OpenCodeAdapter,
  buildCodexArgs,
  normalizeOpenCodeEvent,
  runJsonCli,
};
```

Replace `gateway/src/agents.js` with:

```javascript
'use strict';

module.exports = require('./agents/index');
```

- [ ] **Step 6: Run split tests**

```powershell
npm test --prefix gateway -- agents_split.test.js
```

Expected: PASS.

- [ ] **Step 7: Run all gateway tests**

```powershell
npm test --prefix gateway
```

Expected: PASS.

- [ ] **Step 8: Commit adapter split**

```powershell
git add gateway/src/agents.js gateway/src/agents gateway/test/agents_split.test.js
git commit -m "refactor: split gateway agent adapters"
```

---

### Task 5: Repair Documentation and Align Product Boundaries

**Files:**

- Modify: `README.md`
- Modify: `gateway/README.md`
- Modify: `docs/requirements.md`
- Modify: `docs/development-spec.md`
- Modify: `docs/workflow.md`
- Modify: `TODO.md`
- Modify: `docs/optimization-plan.md`

- [ ] **Step 1: Write the failing mojibake check**

Run:

```powershell
$matches = rg -n "encoding check pattern" README.md TODO.md docs gateway/README.md
if ($LASTEXITCODE -eq 0) {
  throw "encoding issues remain`n$matches"
}
```

Expected: FAIL with matches in existing documentation.

- [ ] **Step 2: Update `README.md` product target and quick start**

Make these concrete content changes:

- Replace the architecture diagram with an ASCII-only diagram.
- Replace "Phone (Flutter app) HTTPS / SSE" with "iPhone / mobile Flutter app HTTP(S) / SSE".
- Remove the obsolete mobile-target command text.
- Add this v1 access note:

```markdown
## Gateway Access Model

The first version has no gateway authentication. Run the gateway on a trusted
LAN or Tailscale network only. The default bind host is `127.0.0.1`; use
`GATEWAY_HOST=0.0.0.0` only when the phone must reach the laptop over a trusted
network.

Web is not a supported target in v1. The Flutter Web scaffold has been removed,
and the app uses native/mobile-only APIs for streaming and attachments.
```

Replace the Flutter development section with:

```markdown
### Flutter app

```bash
flutter pub get
flutter test
```

Build and device runs target mobile platforms. iOS packaging is handled by CI.
```
```

- [ ] **Step 3: Update `gateway/README.md` access wording**

Replace the current no-auth paragraph with:

```markdown
The first gateway version has no authentication. This is intentional for v1:
the gateway is meant to run on the user's machine and be reachable only from a
trusted LAN or Tailscale network. Keep the default `127.0.0.1` bind for local
testing. Use `GATEWAY_HOST=0.0.0.0` only when a trusted phone needs LAN access.
```

Remove any statement that implies a bearer token can protect the gateway in v1.

- [ ] **Step 4: Update `docs/requirements.md`**

Add these bullets under "App and gateway split":

```markdown
- V1 targets mobile/iOS. Flutter Web is not supported.
- V1 gateway access is trusted-network only. It does not require or validate a
  bearer token.
- Authentication remains outside the v1 implementation scope.
```

- [ ] **Step 5: Update `docs/development-spec.md`**

In "Core Architecture", replace `iOS app` with `mobile/iOS app`.

In "Security Boundary", add:

```markdown
The first version intentionally does not implement gateway authentication.
The supported deployment model is trusted LAN or Tailscale access. The app UI
must not present a bearer-token field until the gateway validates such tokens.
```

In "Non-Goals", add:

```markdown
- Flutter Web support for v1.
- Gateway authentication for v1.
```

- [ ] **Step 6: Rewrite corrupted `docs/workflow.md`**

Replace the file with readable Chinese content that covers:

- 项目结构
- Node gateway 本地运行
- Flutter 测试和分析方式
- iOS CI 打包方式
- 常用命令

Use this exact top section:

```markdown
# 开发工作流

## 项目结构概览

```text
lib/
  api/        REST、SSE、Git 客户端
  models/     消息、Part、会话、项目、Agent 数据模型
  state/      Riverpod 状态管理
  ui/         页面与组件
gateway/src/  Node.js gateway
docs/         产品和开发文档
test/         Flutter 单元测试
gateway/test/ Node.js gateway 测试
```

## 本地运行 gateway

```powershell
cd gateway
npm install
$env:GATEWAY_HOST='0.0.0.0'
npm start
```

第一版 gateway 不做认证，只应在可信局域网或 Tailscale 中暴露。
```
```

- [ ] **Step 7: Rewrite corrupted `TODO.md`**

Replace the file with a readable roadmap. Include these sections:

```markdown
# Remote Multi-Agent Roadmap

## V1 Boundary

- Mobile/iOS app only; Web is unsupported.
- Gateway has no authentication; use trusted LAN or Tailscale.
- App does not execute code and does not read project files directly.
- Gateway owns project directories, agent CLIs, filesystem, git, and credentials.

## Near-Term Cleanup

- Split gateway agent adapters into one file per agent.
- Keep command discovery dynamic through gateway metadata.
- Remove UI controls that imply unsupported gateway authentication.
- Keep documentation free of mojibake and aligned with the current product.

## Functional Follow-Up

- Decide whether approve/reject/handoff should be implemented or hidden.
- Add contract tests for any API endpoint surfaced in the app.
- Add CI checks for docs encoding and mobile test commands.
```
```

- [ ] **Step 8: Rewrite `docs/optimization-plan.md`**

Replace the corrupted text with a concise optimization plan:

```markdown
# Optimization Plan

## Current Priorities

1. Keep v1 mobile-only and remove Web-facing expectations.
2. Keep gateway access limited to trusted LAN/Tailscale without adding auth.
3. Split `gateway/src/agents.js` into focused modules.
4. Align app UI with implemented gateway capabilities.
5. Add focused tests around streaming, agent adapters, and endpoint contracts.

## Code Health Targets

- One adapter file per agent: Codex, Claude Code, OpenCode.
- Shared helpers live under `gateway/src/agents/`.
- UI pages should delegate command routing and sheets to smaller widgets or
  controllers when they are next modified.
- Documentation should be readable UTF-8 and describe the actual v1 boundary.
```
```

- [ ] **Step 9: Run documentation verification**

```powershell
$matches = rg -n "encoding check pattern" README.md TODO.md docs gateway/README.md
if ($LASTEXITCODE -eq 0) {
  throw "encoding issues remain`n$matches"
}
```

Expected: PASS with no output.

Run:

```powershell
rg -n "obsolete mobile-target command text|Flutter Web|web scaffold|legacy gateway credential-setting wording" README.md gateway/README.md docs TODO.md
```

Expected: no matches, except a permitted sentence that says Web is unsupported without naming a Web scaffold.

- [ ] **Step 10: Commit documentation updates**

```powershell
git add README.md gateway/README.md docs/requirements.md docs/development-spec.md docs/workflow.md TODO.md docs/optimization-plan.md
git commit -m "docs: align v1 mobile and trusted LAN scope"
```

---

### Task 6: Final Verification

**Files:**

- No new files.

- [ ] **Step 1: Run gateway tests**

```powershell
npm test --prefix gateway
```

Expected: all Node gateway tests pass.

- [ ] **Step 2: Run Flutter tests**

```powershell
MSYS_NO_PATHCONV=1 docker run --rm -v "D:\Code\WorkSpace\remote-multi-agent:/app" -w /app ghcr.io/cirruslabs/flutter:3.27.1 bash -lc "flutter pub get && flutter test"
```

Expected: all Flutter tests pass. If Docker is unavailable, run `flutter test` in a Flutter 3.27+ environment.

- [ ] **Step 3: Run static analysis**

```powershell
MSYS_NO_PATHCONV=1 docker run --rm -v "D:\Code\WorkSpace\remote-multi-agent:/app" -w /app ghcr.io/cirruslabs/flutter:3.27.1 bash -lc "flutter pub get && flutter analyze"
```

Expected: analysis succeeds with no errors.

- [ ] **Step 4: Check final repository state**

```powershell
git status --short
```

Expected: no uncommitted files after the task commits, or only intentional files awaiting the final integration commit.

```powershell
rg -n "_tokenCtrl|legacy gateway credential-setting wording|settings\.bearerToken|bearerToken:" lib/state lib/ui
```

Expected: no matches.

```powershell
if (Test-Path web) {
  throw 'web directory still exists'
}
```

Expected: PASS with no output.

```powershell
rg -n "encoding check pattern" README.md TODO.md docs gateway/README.md
```

Expected: no matches.

- [ ] **Step 5: Final integration commit if needed**

If the previous tasks were not committed individually, make one final commit:

```powershell
git add .
git commit -m "chore: clean up mobile v1 gateway structure"
```

---

## Self-Review

Spec coverage:

- Mobile-only v1 is covered by Task 1 and Task 5.
- No gateway authentication in v1 is covered by Task 1 and Task 5.
- LAN/Tailscale-only access guidance is covered by Task 5.
- One agent per file is covered by Task 2, Task 3, and Task 4.
- Existing documentation updates are covered by Task 5.

Placeholder scan:

- No undecided implementation sections remain.
- The root roadmap file name contains the word `TODO`, but no plan step uses it as an unfinished placeholder.

Type consistency:

- `AgentRegistry`, `CodexAdapter`, `ClaudeCodeAdapter`, `OpenCodeAdapter`, `buildCodexArgs`, `normalizeOpenCodeEvent`, and `runJsonCli` are exported consistently from `gateway/src/agents/index.js`.
- App settings remove `bearerToken` from `AppSettings`; optional bearer-token constructor arguments remain only in lower-level API clients.
