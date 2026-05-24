library;

import 'package:dio/dio.dart';

bool isAgentSettingsUnsupported(Object error) {
  return error is DioException &&
      error.response?.statusCode == 404 &&
      error.requestOptions.path.contains('/settings/agents');
}
