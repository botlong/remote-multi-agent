import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/api/gateway_client.dart';
import 'package:remote_multi_agent/models/gateway_event.dart';
import 'package:remote_multi_agent/models/gateway_session.dart';
import 'package:remote_multi_agent/models/message.dart';
import 'package:remote_multi_agent/state/gateway_chat_store.dart';

void main() {
  test('message.delta appends gateway text into a renderable message',
      () async {
    final controller = GatewayChatStore(
      client: _FakeGatewayClient(
        eventsStream: Stream<GatewayEvent>.fromIterable([
          const GatewayEvent(
            type: 'message.delta',
            sessionId: 's1',
            agentId: 'codex',
            timestampMs: 1,
            data: <String, dynamic>{
              'messageId': 'm1',
              'delta': 'hello',
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

    final message = controller.state.messages['m1'];
    expect(message, isNotNull);
    expect(message!.orderedParts.single.id, 'm1_text');
  });

  test('REST reload updates message status even when part count is unchanged',
      () async {
    final client = _FakeGatewayClient(
      eventsStream: Stream<GatewayEvent>.fromIterable([
        const GatewayEvent(
          type: 'message.created',
          sessionId: 's1',
          agentId: 'codex',
          timestampMs: 1,
          data: <String, dynamic>{
            'message': <String, dynamic>{
              'id': 'm1',
              'sessionID': 's1',
              'role': 'assistant',
              'status': 'running',
              'time': <String, dynamic>{'created': 1},
              'parts': [
                <String, dynamic>{
                  'id': 'm1_text',
                  'messageID': 'm1',
                  'sessionID': 's1',
                  'type': 'text',
                  'text': 'hello',
                },
              ],
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
              'text': 'hello',
            },
          ],
        },
      ],
    );
    final controller = GatewayChatStore(
      client: client,
      sessionId: 's1',
    );
    addTearDown(controller.dispose);

    await Future<void>.delayed(Duration.zero);
    await controller.reconnect();

    expect(controller.state.messages['m1']?.status, MessageStatus.completed);
    expect(controller.state.messages['m1']?.completedAtMs, 2);
  });
}

class _FakeGatewayClient extends GatewayClient {
  _FakeGatewayClient({
    required this.eventsStream,
    this.messages = const [],
  })
      : super(baseUrl: Uri.parse('http://gateway.test'));

  final Stream<GatewayEvent> eventsStream;
  final List<Map<String, dynamic>> messages;

  @override
  Future<GatewaySession> getSession(String sessionId) async {
    return GatewaySession(
      id: sessionId,
      projectId: 'p1',
      directory: '/tmp/project',
      agentId: 'codex',
      title: 'Test',
      status: GatewaySessionStatus.idle,
      createdAtMs: 1,
      updatedAtMs: 1,
      raw: const <String, dynamic>{},
    );
  }

  @override
  Future<List<Map<String, dynamic>>> listMessages(String sessionId) async {
    return messages;
  }

  @override
  Stream<GatewayEvent> events(String sessionId) {
    return eventsStream;
  }

  @override
  void close() {}
}
