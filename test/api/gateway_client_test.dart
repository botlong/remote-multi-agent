import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:remote_multi_agent/api/gateway_client.dart';

void main() {
  group('GatewayClient.events', () {
    test('parses SSE event/data envelope including multiline data', () async {
      final client = GatewayClient(
        baseUrl: Uri.parse('http://gateway.test'),
        httpClient: _StreamingClient((request) async {
          expect(request.url.path, '/sessions/s1/events');
          expect(request.headers['Accept'], 'text/event-stream');
          return http.StreamedResponse(
            Stream<List<int>>.fromIterable(<List<int>>[
              utf8.encode('event: gateway\n'),
              utf8.encode('data: {"type":"message.delta",'),
              utf8.encode('"sessionId":"s1",'),
              utf8.encode('"data":{"text":"hello"}}\n\n'),
            ]),
            200,
            headers: const <String, String>{
              'content-type': 'text/event-stream',
            },
          );
        }),
      );
      addTearDown(client.close);

      final event = await client.events('s1').single;

      expect(event.sseEvent, 'gateway');
      expect(event.type, 'message.delta');
      expect(event.sessionId, 's1');
      expect(event.data['text'], 'hello');
      expect(event.raw['type'], 'message.delta');
    });

    test('throws on non-success SSE handshake', () async {
      final client = GatewayClient(
        baseUrl: Uri.parse('http://gateway.test'),
        httpClient: _StreamingClient((request) async {
          return http.StreamedResponse(const Stream<List<int>>.empty(), 500);
        }),
      );
      addTearDown(client.close);

      expect(client.events('s1').drain<void>(), throwsStateError);
    });
  });
}

class _StreamingClient extends http.BaseClient {
  _StreamingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }
}
