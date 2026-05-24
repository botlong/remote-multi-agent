import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/api/gateway_client.dart';
import 'package:remote_multi_agent/models/gateway_event.dart';
import 'package:remote_multi_agent/models/gateway_session.dart';
import 'package:remote_multi_agent/models/agent.dart';
import 'package:remote_multi_agent/state/gateway_client_provider.dart';
import 'package:remote_multi_agent/state/settings_store.dart';
import 'package:remote_multi_agent/ui/pages/gateway_chat_page.dart';
import 'package:remote_multi_agent/ui/pages/gateway_ui_adapters.dart';
import 'package:remote_multi_agent/ui/widgets/agent_activity_bar.dart';
import 'package:remote_multi_agent/ui/widgets/activity_timeline.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('does not render a duplicate activity timeline below chat',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = _FakeGatewayClient(
      eventsStream: Stream<GatewayEvent>.fromIterable([
        const GatewayEvent(
          type: 'activity.updated',
          sessionId: 's1',
          agentId: 'codex',
          timestampMs: 3,
          data: <String, dynamic>{
            'activity': <String, dynamic>{
              'id': 'tool_1',
              'kind': 'command',
              'status': 'completed',
              'title': 'Ran npm test',
              'command': 'npm test',
              'outputDelta': 'ok\n',
              'sequence': 1,
            },
          },
          raw: <String, dynamic>{},
          sseEvent: 'message',
        ),
      ]),
      messages: const [
        <String, dynamic>{
          'id': 'm1',
          'sessionID': 's1',
          'role': 'assistant',
          'status': 'completed',
          'time': <String, dynamic>{'created': 1, 'completed': 2},
          'parts': [
            <String, dynamic>{
              'id': 'm1_text',
              'messageID': 'm1',
              'sessionID': 's1',
              'type': 'text',
              'text': 'done',
            },
            <String, dynamic>{
              'id': 'm1_tool_tool_1',
              'messageID': 'm1',
              'sessionID': 's1',
              'type': 'tool',
              'tool': 'shell',
              'status': 'completed',
              'input': <String, dynamic>{'command': 'npm test'},
              'output': 'ok\n',
            },
          ],
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gatewayClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(
            (ref) => SettingsController(prefs),
          ),
          sharedPreferencesProvider.overrideWith((ref) async => prefs),
        ],
        child: const MaterialApp(
          home: GatewayChatPage(
            session: GatewaySessionView(
              id: 's1',
              projectId: 'p1',
              directory: '/tmp/project',
              agentId: 'codex',
              modelId: 'gpt-5.5',
              title: 'Codex session',
              status: 'idle',
              createdAtMs: 1,
              updatedAtMs: 2,
            ),
            project: GatewayProjectView(
              id: 'p1',
              name: 'project',
              directory: '/tmp/project',
              updatedAtMs: 2,
            ),
            agent: GatewayAgentView(
              id: 'codex',
              displayName: 'Codex',
              supportsModels: true,
              supportsSlashCommands: true,
              commands: [],
              models: [],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ActivityTimeline), findsNothing);
  });

  testWidgets('does not render a transient active tool bar above input',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final client = _FakeGatewayClient(
      eventsStream: Stream<GatewayEvent>.fromIterable([
        const GatewayEvent(
          type: 'activity.updated',
          sessionId: 's1',
          agentId: 'codex',
          timestampMs: 3,
          data: <String, dynamic>{
            'activity': <String, dynamic>{
              'id': 'tool_1',
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
      messages: const [
        <String, dynamic>{
          'id': 'm1',
          'sessionID': 's1',
          'role': 'assistant',
          'status': 'running',
          'time': <String, dynamic>{'created': 1},
          'parts': [
            <String, dynamic>{
              'id': 'm1_tool_tool_1',
              'messageID': 'm1',
              'sessionID': 's1',
              'type': 'tool',
              'tool': 'shell',
              'status': 'running',
              'input': <String, dynamic>{'command': 'npm test'},
            },
          ],
        },
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gatewayClientProvider.overrideWithValue(client),
          settingsControllerProvider.overrideWith(
            (ref) => SettingsController(prefs),
          ),
          sharedPreferencesProvider.overrideWith((ref) async => prefs),
        ],
        child: const MaterialApp(
          home: GatewayChatPage(
            session: GatewaySessionView(
              id: 's1',
              projectId: 'p1',
              directory: '/tmp/project',
              agentId: 'codex',
              modelId: 'gpt-5.5',
              title: 'Codex session',
              status: 'running',
              createdAtMs: 1,
              updatedAtMs: 2,
            ),
            project: GatewayProjectView(
              id: 'p1',
              name: 'project',
              directory: '/tmp/project',
              updatedAtMs: 2,
            ),
            agent: GatewayAgentView(
              id: 'codex',
              displayName: 'Codex',
              supportsModels: true,
              supportsSlashCommands: true,
              commands: [],
              models: [],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AgentActivityBar), findsNothing);
  });

  testWidgets('filters command suggestions by active prefix', (tester) async {
    final client = _FakeGatewayClient(
      eventsStream: const Stream<GatewayEvent>.empty(),
      messages: const [],
      commands: const [
        AgentCommand(name: '/model', description: 'Switch model', raw: {}),
        AgentCommand(name: '/mcp', description: 'MCP status', raw: {}),
        AgentCommand(name: '/permissions', description: 'Permissions', raw: {}),
      ],
    );

    await _pumpChatPage(tester, client);
    await tester.enterText(find.byType(TextField), '/m');
    await tester.pumpAndSettle();

    expect(find.text('/model'), findsOneWidget);
    expect(find.text('/mcp'), findsOneWidget);
    expect(find.text('/permissions'), findsNothing);
  });

  testWidgets('tapping a slash command executes it immediately',
      (tester) async {
    final client = _FakeGatewayClient(
      eventsStream: const Stream<GatewayEvent>.empty(),
      messages: const [],
      commands: const [
        AgentCommand(name: '/mcp', description: 'MCP status', raw: {}),
      ],
    );

    await _pumpChatPage(tester, client);
    await tester.enterText(find.byType(TextField), '/mc');
    await tester.pumpAndSettle();
    await tester.tap(find.text('/mcp'));
    await tester.pump();

    expect(client.sentSlashCommands, const ['/mcp']);
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, isEmpty);
  });

  testWidgets('tapping a skill suggestion sends it as a message',
      (tester) async {
    final client = _FakeGatewayClient(
      eventsStream: const Stream<GatewayEvent>.empty(),
      messages: const [],
      commands: const [
        AgentCommand(name: r'$', description: 'Run shell command', raw: {}),
        AgentCommand(name: r'$superpowers', description: 'Use skill', raw: {}),
        AgentCommand(name: r'$playwright', description: 'Use skill', raw: {}),
      ],
    );

    await _pumpChatPage(tester, client);
    await tester.enterText(find.byType(TextField), r'$s');
    await tester.pumpAndSettle();

    expect(find.text(r'$superpowers'), findsOneWidget);
    expect(find.text(r'$playwright'), findsNothing);

    await tester.tap(find.text(r'$superpowers'));
    await tester.pump();

    expect(client.sentMessages, const [r'$superpowers']);
    expect(client.sentSlashCommands, isEmpty);
  });

  testWidgets('shows file mention candidates for the active @ token',
      (tester) async {
    final client = _FakeGatewayClient(
      eventsStream: const Stream<GatewayEvent>.empty(),
      messages: const [],
      fileTree: const [
        <String, dynamic>{
          'name': 'lib',
          'path': '/tmp/project/lib',
          'isDirectory': true,
          'children': [
            <String, dynamic>{
              'name': 'main.dart',
              'path': '/tmp/project/lib/main.dart',
              'isDirectory': false,
              'children': <Map<String, dynamic>>[],
            },
          ],
        },
        <String, dynamic>{
          'name': 'README.md',
          'path': '/tmp/project/README.md',
          'isDirectory': false,
          'children': <Map<String, dynamic>>[],
        },
      ],
    );

    await _pumpChatPage(tester, client);
    await tester.enterText(find.byType(TextField), 'check @lib');
    await tester.pumpAndSettle();

    expect(find.text('@lib/main.dart'), findsOneWidget);
    expect(find.text('@README.md'), findsNothing);

    await tester.tap(find.text('@lib/main.dart'));
    await tester.pump();

    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.controller?.text, 'check @lib/main.dart ');
    expect(client.sentMessages, isEmpty);
  });
}

Future<void> _pumpChatPage(
  WidgetTester tester,
  _FakeGatewayClient client,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        gatewayClientProvider.overrideWithValue(client),
        settingsControllerProvider.overrideWith(
          (ref) => SettingsController(prefs),
        ),
        sharedPreferencesProvider.overrideWith((ref) async => prefs),
      ],
      child: const MaterialApp(
        home: GatewayChatPage(
          session: GatewaySessionView(
            id: 's1',
            projectId: 'p1',
            directory: '/tmp/project',
            agentId: 'codex',
            modelId: 'gpt-5.5',
            title: 'Codex session',
            status: 'idle',
            createdAtMs: 1,
            updatedAtMs: 2,
          ),
          project: GatewayProjectView(
            id: 'p1',
            name: 'project',
            directory: '/tmp/project',
            updatedAtMs: 2,
          ),
          agent: GatewayAgentView(
            id: 'codex',
            displayName: 'Codex',
            supportsModels: true,
            supportsSlashCommands: true,
            commands: [],
            models: [],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeGatewayClient extends GatewayClient {
  _FakeGatewayClient({
    required this.eventsStream,
    required this.messages,
    this.commands = const [],
    this.fileTree = const [],
  }) : super(baseUrl: Uri.parse('http://gateway.test'));

  final Stream<GatewayEvent> eventsStream;
  final List<Map<String, dynamic>> messages;
  final List<AgentCommand> commands;
  final List<Map<String, dynamic>> fileTree;
  final List<String> sentMessages = [];
  final List<String> sentSlashCommands = [];

  @override
  Future<GatewaySession> getSession(String sessionId) async {
    return GatewaySession(
      id: sessionId,
      projectId: 'p1',
      directory: '/tmp/project',
      agentId: 'codex',
      title: 'Codex session',
      status: GatewaySessionStatus.idle,
      createdAtMs: 1,
      updatedAtMs: 2,
      raw: const <String, dynamic>{},
      modelId: 'gpt-5.5',
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listMessages(String sessionId) async {
    return messages;
  }

  @override
  Future<List<AgentCommand>> listAgentCommands(
    String agentId, {
    String? projectId,
  }) async {
    return commands;
  }

  @override
  Future<List<Map<String, dynamic>>> listFiles(String path) async {
    return fileTree;
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    required String sessionId,
    String? text,
    List<Map<String, dynamic>> parts = const <Map<String, dynamic>>[],
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    if (text != null) sentMessages.add(text);
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> sendSlashCommand({
    required String sessionId,
    required String command,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    sentSlashCommands.add(command);
    return const <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>?> getActiveProfile() async {
    return null;
  }

  @override
  Stream<GatewayEvent> events(String sessionId) {
    return eventsStream;
  }

  @override
  void close() {}
}
