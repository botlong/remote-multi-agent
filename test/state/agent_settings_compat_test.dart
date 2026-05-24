import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/state/agent_settings_compat.dart';

void main() {
  test('recognizes legacy gateways without agent settings routes', () {
    final error = DioException(
      requestOptions: RequestOptions(path: '/settings/agents/codex'),
      response: Response<dynamic>(
        requestOptions: RequestOptions(path: '/settings/agents/codex'),
        statusCode: 404,
      ),
    );

    expect(isAgentSettingsUnsupported(error), isTrue);
  });
}
