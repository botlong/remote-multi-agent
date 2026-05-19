import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/api/gateway_client.dart';
import 'package:remote_multi_agent/models/gateway_event.dart';
import 'package:remote_multi_agent/models/gateway_session.dart';
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
}

class _FakeGatewayClient extends GatewayClient {
  _FakeGatewayClient({required this.eventsStream})
      : super(baseUrl: Uri.parse('http://gateway.test'));

  final Stream<GatewayEvent> eventsStream;

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
    return const [];
  }

  @override
  Stream<GatewayEvent> events(String sessionId) {
    return eventsStream;
  }

  @override
  void close() {}
}
