import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/api/gateway_client.dart';

// GatewayClient.events() now delegates to the self-reconnecting SseClient
// (which uses dart:io HttpClient for true chunked streaming on iOS). That
// layer isn't reachable through package:http injection, so the old
// http.Client-based stream tests no longer apply. SSE protocol parsing is
// exercised end-to-end by the gateway integration tests in
// gateway/test/server.test.js.

void main() {
  test('GatewayClient instantiates without error', () {
    final client = GatewayClient(baseUrl: Uri.parse('http://gateway.test'));
    addTearDown(client.close);
    expect(client, isNotNull);
  });
}
