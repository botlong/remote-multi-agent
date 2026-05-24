import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/api/gateway_client.dart';
import 'package:remote_multi_agent/models/gateway_event.dart';
import 'package:remote_multi_agent/models/gateway_session.dart';
import 'package:remote_multi_agent/state/gateway_client_provider.dart';
import 'package:remote_multi_agent/state/settings_store.dart';
import 'package:remote_multi_agent/ui/pages/gateway_chat_page.dart';
import 'package:remote_multi_agent/ui/pages/gateway_ui_adapters.dart';
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
}

class _FakeGatewayClient extends GatewayClient {
  _FakeGatewayClient({
    required this.eventsStream,
    required this.messages,
  }) : super(baseUrl: Uri.parse('http://gateway.test'));

  final Stream<GatewayEvent> eventsStream;
  final List<Map<String, dynamic>> messages;

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
