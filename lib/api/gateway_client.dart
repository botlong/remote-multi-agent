/// Unified gateway protocol client.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;

import '../models/agent.dart';
import '../models/gateway_event.dart';
import '../models/gateway_session.dart';
import '../models/project.dart';
import 'sse_stream.dart';

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
        _httpClient = httpClient ?? http.Client() {
    if (dio == null) {
      _dio.interceptors.add(_RetryInterceptor(_dio));
    }
  }

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

  Future<List<Map<String, dynamic>>> search(
    String query, {
    String? projectId,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      '/search',
      queryParameters: <String, dynamic>{
        'q': query,
        if (projectId != null) 'projectId': projectId,
      },
    );
    return _readList(res.data);
  }

  /// Export session as markdown or JSON string.
  Future<String> exportSession(String sessionId, {String format = 'markdown'}) async {
    final res = await _dio.get<dynamic>(
      '/sessions/${_path(sessionId)}/export',
      queryParameters: {'format': format},
      options: Options(responseType: ResponseType.plain),
    );
    return res.data?.toString() ?? '';
  }

  Future<Map<String, dynamic>> getSessionDiff(String sessionId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/sessions/${_path(sessionId)}/diff',
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> approveChanges(
    String sessionId, {
    String? message,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/sessions/${_path(sessionId)}/approve',
      data: <String, dynamic>{
        if (message != null) 'message': message,
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> rejectChanges(String sessionId) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/sessions/${_path(sessionId)}/reject',
    );
    return res.data ?? const <String, dynamic>{};
  }

  Future<Map<String, dynamic>> handoffSession({
    required String sessionId,
    required String agentId,
    String? prompt,
    String? modelId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/sessions/${_path(sessionId)}/handoff',
      data: <String, dynamic>{
        'agentId': agentId,
        if (prompt != null) 'prompt': prompt,
        if (modelId != null) 'modelId': modelId,
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  /// List all profiles (keys are masked by the gateway).
  Future<List<Map<String, dynamic>>> listProfiles() async {
    final res = await _dio.get<List<dynamic>>('/settings/profiles');
    return _readList(res.data);
  }

  /// Get the currently active profile (masked keys).
  Future<Map<String, dynamic>?> getActiveProfile() async {
    final res = await _dio.get<dynamic>('/settings/active-profile');
    if (res.data == null) return null;
    if (res.data is Map<String, dynamic>) return res.data as Map<String, dynamic>;
    return null;
  }

  /// Create a new profile.
  Future<Map<String, dynamic>> createProfile({
    required String name,
    Map<String, dynamic> keys = const {},
    Map<String, String> defaultModel = const {},
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/settings/profiles',
      data: <String, Object?>{
        'name': name,
        'keys': keys,
        'defaultModel': defaultModel,
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  /// Update an existing profile.
  Future<Map<String, dynamic>> updateProfile(
    String profileId, {
    String? name,
    Map<String, dynamic>? keys,
    Map<String, String>? defaultModel,
  }) async {
    final res = await _dio.patch<Map<String, dynamic>>(
      '/settings/profiles/${_path(profileId)}',
      data: <String, Object?>{
        if (name != null) 'name': name,
        if (keys != null) 'keys': keys,
        if (defaultModel != null) 'defaultModel': defaultModel,
      },
    );
    return res.data ?? const <String, dynamic>{};
  }

  /// Delete a profile.
  Future<void> deleteProfile(String profileId) async {
    await _dio.delete<dynamic>('/settings/profiles/${_path(profileId)}');
  }

  /// Activate a profile (make it the current one).
  Future<void> activateProfile(String profileId) async {
    await _dio.post<dynamic>(
      '/settings/profiles/${_path(profileId)}/activate',
    );
  }

  /// List Claude credentials discoverable in `~/.claude/settings.json`.
  /// Each entry includes a `tokenPreview` but never the raw token.
  Future<List<Map<String, dynamic>>> listOfficialCredentials() async {
    final res = await _dio.get<List<dynamic>>(
      '/settings/credential-sources/official',
    );
    return _readList(res.data);
  }

  /// List Claude provider credentials discoverable in the CC-Switch database.
  /// Returns an empty list when CC-Switch or `node:sqlite` are unavailable.
  Future<List<Map<String, dynamic>>> listCcSwitchCredentials() async {
    final res = await _dio.get<List<dynamic>>(
      '/settings/credential-sources/cc-switch',
    );
    return _readList(res.data);
  }

  /// Import a credential from a local source into a new profile.
  /// [source] must be `'official'` or `'cc-switch'`.
  /// For `cc-switch`, pass [sourceId] to pick a specific provider; otherwise
  /// the active provider (or first available) is used.
  Future<Map<String, dynamic>> importProfile({
    required String name,
    required String source,
    String? sourceId,
    bool makeActive = false,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/settings/profiles/import',
      data: <String, Object?>{
        'name': name,
        'source': source,
        if (sourceId != null) 'sourceId': sourceId,
        if (makeActive) 'makeActive': true,
      },
    );
    return res.data ?? const <String, dynamic>{};
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
    // Use the self-reconnecting SseClient so that gateway restarts and
    // brief network drops don't leave the chat permanently disconnected.
    final controller = StreamController<GatewayEvent>();
    SseClient? client;
    StreamSubscription<SseEvent>? sub;
    StreamSubscription<SseState>? stateSub;
    bool everConnected = false;

    controller.onListen = () {
      client = SseClient(
        SseConfig(
          url: Uri.parse('$_base/sessions/${_path(sessionId)}/events'),
          bearerToken: _bearerToken,
        ),
      );
      sub = client!.events.listen(
        (sse) {
          if (controller.isClosed) return;
          controller.add(
            GatewayEvent.fromJson(sse.data, sseEvent: sse.type),
          );
        },
        onError: (Object error) {
          if (!controller.isClosed) controller.addError(error);
        },
      );
      // Watch state transitions so consumers can refetch after a reconnect
      // (gateway restart, network blip). Synthesize a 'gateway.reconnected'
      // event on every connect AFTER the first.
      stateSub = client!.state.listen((s) {
        if (controller.isClosed) return;
        if (s == SseState.connected) {
          if (everConnected) {
            controller.add(
              GatewayEvent.fromJson(
                <String, dynamic>{
                  'type': 'gateway.reconnected',
                  'sessionId': sessionId,
                  'data': <String, dynamic>{},
                },
                sseEvent: 'gateway',
              ),
            );
          }
          everConnected = true;
        }
      });
    };

    controller.onCancel = () async {
      await sub?.cancel();
      await stateSub?.cancel();
      await client?.dispose();
    };

    return controller.stream;
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

class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);

  final Dio _dio;
  static const _maxRetries = 2;
  static const _baseDelay = Duration(milliseconds: 500);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (!_shouldRetry(err)) return handler.next(err);

    final attempt = (err.requestOptions.extra['_retryAttempt'] as int?) ?? 0;
    if (attempt >= _maxRetries) return handler.next(err);

    final delay = _baseDelay * (1 << attempt);
    await Future<void>.delayed(delay);

    final options = err.requestOptions;
    options.extra['_retryAttempt'] = attempt + 1;

    try {
      final response = await _dio.fetch<dynamic>(options);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  static bool _shouldRetry(DioException err) {
    if (err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout ||
        err.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = err.response?.statusCode ?? 0;
    return status == 502 || status == 503 || status == 504 || status == 429;
  }
}
