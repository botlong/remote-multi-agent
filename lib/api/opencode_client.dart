/// HTTP client for the small slice of OpenCode's API we actually need.
///
/// Endpoints used:
///   GET  /session                  → list sessions
///   POST /session                  → create session
///   POST /session/{id}/message     → send prompt
///   GET  /provider                 → enumerate models (settings page picker)
///   GET  /agent                    → enumerate agents
///   GET  /event                    → SSE  (handled by SseClient, not here)
///
/// Auth: when [bearerToken] is non-empty we attach `Authorization: Bearer ...`,
/// matching `OPENCODE_SERVER_PASSWORD` on the server side.
library;

import 'package:dio/dio.dart';

import '../models/session.dart';

class OpencodeClient {
  OpencodeClient({required Uri baseUrl, String? bearerToken})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl.toString().replaceAll(RegExp(r'/$'), ''),
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 300),
            sendTimeout: const Duration(seconds: 30),
            headers: {
              'Accept': 'application/json',
              if (bearerToken != null && bearerToken.isNotEmpty)
                'Authorization': 'Bearer $bearerToken',
            },
          ),
        );

  final Dio _dio;

  Future<List<Session>> listSessions() async {
    final res = await _dio.get<List<dynamic>>('/session');
    final data = res.data ?? const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map(Session.fromJson)
        .toList(growable: false);
  }

  Future<Session> createSession({String? directory}) async {
    final query = <String, dynamic>{};
    if (directory != null && directory.isNotEmpty) {
      query['directory'] = directory;
    }
    final res = await _dio.post<Map<String, dynamic>>(
      '/session',
      data: const <String, Object?>{},
      queryParameters: query,
    );
    return Session.fromJson(res.data ?? const {});
  }

  /// Send a user prompt. The actual streamed response is delivered through
  /// [SseClient] to whichever subscriber owns the chat screen.
  Future<void> sendMessage({
    required String sessionId,
    required String text,
    required String providerId,
    required String modelId,
    String mode = 'build',
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/session/$sessionId/message',
      data: {
        'providerID': providerId,
        'modelID': modelId,
        'mode': mode,
        'parts': [
          {'type': 'text', 'text': text},
        ],
      },
    );
  }

  /// Send a user prompt with optional file/image attachments.
  /// Each attachment is serialized as an additional part in the message.
  Future<void> sendMessageWithAttachments({
    required String sessionId,
    required String text,
    required String providerId,
    required String modelId,
    String mode = 'build',
    List<dynamic> attachments = const [],
    String? directory,
  }) async {
    final parts = <Map<String, dynamic>>[];

    // Add text part if non-empty
    if (text.isNotEmpty) {
      parts.add({'type': 'text', 'text': text});
    }

    // Add attachment parts
    for (final attachment in attachments) {
      // Attachment objects have a toPartJson() method
      if (attachment is Map<String, dynamic>) {
        parts.add(attachment);
      } else {
        // Assume it has toPartJson() — duck-typed from Attachment class
        parts.add((attachment as dynamic).toPartJson() as Map<String, dynamic>);
      }
    }

    if (parts.isEmpty) return;

    final query = <String, dynamic>{};
    if (directory != null && directory.isNotEmpty) {
      query['directory'] = directory;
    }

    await _dio.post<Map<String, dynamic>>(
      '/session/$sessionId/message',
      data: {
        'providerID': providerId,
        'modelID': modelId,
        'mode': mode,
        'parts': parts,
      },
      queryParameters: query,
    );
  }

  /// Lightweight summary used in the settings model picker.
  Future<List<({String providerId, String modelId, String label})>>
      listProviderModels() async {
    final res = await _dio.get<Map<String, dynamic>>('/provider');
    final all = (res.data?['all'] as List<dynamic>?) ?? const [];
    final out = <({String providerId, String modelId, String label})>[];
    for (final p in all.whereType<Map<String, dynamic>>()) {
      final providerId = p['id'] as String? ?? '';
      final providerName = p['name'] as String? ?? providerId;
      final models = (p['models'] as Map?)?.cast<String, dynamic>() ?? const {};
      for (final entry in models.entries) {
        out.add(
          (
            providerId: providerId,
            modelId: entry.key,
            label: '$providerName · ${entry.key}',
          ),
        );
      }
    }
    return out;
  }

  Future<List<String>> listAgents() async {
    final res = await _dio.get<List<dynamic>>('/agent');
    final list = res.data ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map((e) => e['name'] as String? ?? '')
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<bool> ping() async {
    try {
      final res = await _dio.get<dynamic>('/session');
      return res.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  /// Load existing messages for a session. Returns an empty list on failure
  /// (the endpoint may 502 for some sessions).
  Future<List<Map<String, dynamic>>> listMessages(String sessionId) async {
    try {
      final res = await _dio.get<List<dynamic>>('/session/$sessionId/message');
      return (res.data ?? []).whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  /// Abort an in-flight agent run for the given session.
  /// Server returns 200 + boolean. We don't surface the bool — caller treats
  /// any non-throw as "abort acknowledged".
  Future<void> abortSession(String sessionId, {String? directory}) async {
    final query = <String, dynamic>{};
    if (directory != null && directory.isNotEmpty) {
      query['directory'] = directory;
    }
    await _dio.post<dynamic>(
      '/session/$sessionId/abort',
      queryParameters: query,
    );
  }

  /// Rename a session.
  Future<void> renameSession(String sessionId, String newTitle) async {
    await _dio.patch<dynamic>(
      '/session/$sessionId',
      data: {'title': newTitle},
    );
  }

  /// Delete a session.
  Future<void> deleteSession(String sessionId) async {
    await _dio.delete<dynamic>('/session/$sessionId');
  }

  void close() => _dio.close(force: true);
}
