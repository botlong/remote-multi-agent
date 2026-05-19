/// Unified gateway protocol client.
library;

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../models/agent.dart';
import '../models/gateway_event.dart';
import '../models/gateway_session.dart';
import '../models/project.dart';

class GatewayClient {
  GatewayClient({
    required Uri baseUrl,
    String? bearerToken,
    Dio? dio,
    http.Client? httpClient,
  })  : _base = baseUrl.toString().replaceAll(RegExp(r'/$'), ''),
        _bearerToken = bearerToken,
        _ownsDio = dio == null,
        _ownsHttpClient = httpClient == null,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl.toString().replaceAll(RegExp(r'/$'), ''),
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 300),
                sendTimeout: const Duration(seconds: 30),
                headers: <String, dynamic>{
                  'Accept': 'application/json',
                  if (bearerToken != null && bearerToken.isNotEmpty)
                    'Authorization': 'Bearer $bearerToken',
                },
              ),
            ),
        _httpClient = httpClient ?? http.Client();

  final String _base;
  final String? _bearerToken;
  final Dio _dio;
  final http.Client _httpClient;
  final bool _ownsDio;
  final bool _ownsHttpClient;

  Future<bool> health() async {
    try {
      final res = await _dio.get<dynamic>('/health');
      final status = res.statusCode ?? 0;
      return status >= 200 && status < 300;
    } on DioException {
      return false;
    }
  }

  Future<List<Project>> listProjects() async {
    final res = await _dio.get<List<dynamic>>('/projects');
    return _readList(res.data).map(Project.fromJson).toList(growable: false);
  }

  Future<Project> createProject({
    required String directory,
    String? name,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/projects',
      data: <String, Object?>{
        'directory': directory,
        if (name != null && name.isNotEmpty) 'name': name,
      },
    );
    return Project.fromJson(res.data ?? const <String, dynamic>{});
  }

  Future<Project> getProject(String projectId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/projects/${_path(projectId)}',
    );
    return Project.fromJson(res.data ?? const <String, dynamic>{});
  }

  Future<void> deleteProject(String projectId) async {
    await _dio.delete<dynamic>('/projects/${_path(projectId)}');
  }

  Future<List<String>> listDirectories() async {
    final res = await _dio.get<dynamic>('/directories');
    final data = res.data;
    if (data is List<dynamic>) {
      return data.whereType<String>().toList(growable: false);
    }
    if (data is Map<String, dynamic>) {
      final dirs = data['directories'] as List<dynamic>? ?? const <dynamic>[];
      return dirs.whereType<String>().toList(growable: false);
    }
    return const <String>[];
  }

  Future<List<Agent>> listAgents() async {
    final res = await _dio.get<List<dynamic>>('/agents');
    return _readList(res.data).map(Agent.fromJson).toList(growable: false);
  }

  Future<Agent> getAgent(String agentId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/agents/${_path(agentId)}',
    );
    return Agent.fromJson(res.data ?? const <String, dynamic>{});
  }

  Future<List<AgentModel>> listAgentModels(String agentId) async {
    final res = await _dio.get<dynamic>('/agents/${_path(agentId)}/models');
    return _readEnvelopeList(res.data, 'models')
        .map(AgentModel.fromJson)
        .toList(growable: false);
  }

  Future<List<AgentCommand>> listAgentCommands(String agentId) async {
    final res = await _dio.get<dynamic>('/agents/${_path(agentId)}/commands');
    return _readEnvelopeList(res.data, 'commands')
        .map(AgentCommand.fromJson)
        .toList(growable: false);
  }

  Future<List<GatewaySession>> listProjectSessions(String projectId) async {
    final res = await _dio.get<List<dynamic>>(
      '/projects/${_path(projectId)}/sessions',
    );
    return _readList(res.data)
        .map(GatewaySession.fromJson)
        .toList(growable: false);
  }

  Future<GatewaySession> createSession({
    required String projectId,
    required String agentId,
    String? modelId,
    String? title,
    String? sandbox,
    String? permissionMode,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/projects/${_path(projectId)}/sessions',
      data: <String, Object?>{
        'agentId': agentId,
        if (modelId != null && modelId.isNotEmpty) 'modelId': modelId,
        if (title != null && title.isNotEmpty) 'title': title,
        if (sandbox != null && sandbox.isNotEmpty) 'sandbox': sandbox,
        if (permissionMode != null && permissionMode.isNotEmpty)
          'permissionMode': permissionMode,
      },
    );
    return GatewaySession.fromJson(res.data ?? const <String, dynamic>{});
  }

  Future<GatewaySession> getSession(String sessionId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/sessions/${_path(sessionId)}',
    );
    return GatewaySession.fromJson(res.data ?? const <String, dynamic>{});
  }

  Future<GatewaySession> updateSession(
    String sessionId, {
    String? title,
    String? modelId,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/sessions/${_path(sessionId)}',
      data: <String, Object?>{
        if (title != null) 'title': title,
        if (modelId != null) 'modelId': modelId,
      },
    );
    return GatewaySession.fromJson(res.data ?? const <String, dynamic>{});
  }

  Future<void> deleteSession(String sessionId) async {
    await _dio.delete<dynamic>('/sessions/${_path(sessionId)}');
  }

  Future<void> deleteMessage(String sessionId, String messageId) async {
    await _dio.delete<dynamic>(
      '/sessions/${_path(sessionId)}/messages/${_path(messageId)}',
    );
  }

  Future<List<Map<String, dynamic>>> listMessages(String sessionId) async {
    final res = await _dio.get<List<dynamic>>(
      '/sessions/${_path(sessionId)}/messages',
    );
    return _readList(res.data);
  }

  Future<Map<String, dynamic>> sendMessage({
    required String sessionId,
    String? text,
    List<Map<String, dynamic>> parts = const <Map<String, dynamic>>[],
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/sessions/${_path(sessionId)}/messages',
      data: <String, Object?>{
        if (text != null) 'text': text,
        if (parts.isNotEmpty) 'parts': parts,
        ...extra,
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> sendSlashCommand({
    required String sessionId,
    required String command,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    return sendMessage(
      sessionId: sessionId,
      text: command,
      extra: <String, dynamic>{
        'slashCommand': command,
        ...extra,
      },
    );
  }

  Future<void> abortSession(String sessionId) async {
    await _dio.post<dynamic>('/sessions/${_path(sessionId)}/abort');
  }

  Stream<GatewayEvent> events(String sessionId) {
    final request = http.Request(
      'GET',
      Uri.parse('$_base/sessions/${_path(sessionId)}/events'),
    );
    request.headers['Accept'] = 'text/event-stream';
    request.headers['Cache-Control'] = 'no-cache';
    if (_bearerToken != null && _bearerToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $_bearerToken';
    }
    return _sendSse(request);
  }

  Stream<GatewayEvent> _sendSse(http.BaseRequest request) async* {
    final response = await _httpClient.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.drain<void>();
      throw StateError('SSE handshake failed: HTTP ${response.statusCode}');
    }

    String? eventType;
    final dataBuffer = StringBuffer();
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final normalized =
          line.endsWith('\r') ? line.substring(0, line.length - 1) : line;
      if (normalized.isEmpty) {
        if (dataBuffer.isNotEmpty) {
          yield GatewayEvent.fromSseData(
            sseEvent: eventType ?? 'message',
            data: dataBuffer.toString(),
          );
        }
        eventType = null;
        dataBuffer.clear();
        continue;
      }
      if (normalized.startsWith(':')) continue;

      final colon = normalized.indexOf(':');
      final field = colon >= 0 ? normalized.substring(0, colon) : normalized;
      final value = colon >= 0
          ? (normalized.length > colon + 1 && normalized[colon + 1] == ' '
              ? normalized.substring(colon + 2)
              : normalized.substring(colon + 1))
          : '';

      switch (field) {
        case 'event':
          eventType = value;
          break;
        case 'data':
          if (dataBuffer.isNotEmpty) dataBuffer.writeln();
          dataBuffer.write(value);
          break;
        default:
          break;
      }
    }

    if (dataBuffer.isNotEmpty) {
      yield GatewayEvent.fromSseData(
        sseEvent: eventType ?? 'message',
        data: dataBuffer.toString(),
      );
    }
  }

  void close() {
    if (_ownsDio) _dio.close(force: true);
    if (_ownsHttpClient) _httpClient.close();
  }

  static String _path(String value) => Uri.encodeComponent(value);

  static List<Map<String, dynamic>> _readList(Object? data) {
    return (data as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  static List<Map<String, dynamic>> _readEnvelopeList(
    Object? data,
    String field,
  ) {
    if (data is Map<String, dynamic>) {
      return _readList(data[field]);
    }
    return _readList(data);
  }
}
