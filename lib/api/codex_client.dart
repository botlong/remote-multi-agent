/// HTTP client for the Codex CLI bridge that lives inside the QQBot server.
///
/// Endpoints used:
///   POST /codex/threads               body: {directory, prompt, model?}
///                                     → SSE stream until codex exits
///   POST /codex/threads/:id/messages  body: {prompt, directory?, model?}
///                                     → SSE stream of resumed turn
///   POST /codex/threads/:id/abort     → SIGTERM the running process
///   GET  /codex/threads               → list running threads
///
/// The chat layer treats each SSE *connection* as one "turn" of the
/// conversation. When the connection ends, the turn is over.
///
/// Auth: when [bearerToken] is non-empty we attach `Authorization: Bearer ...`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpClientRequest, HttpClientResponse;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

/// Decoded codex JSONL event: forwarded as-is from the server.
@immutable
class CodexEvent {
  const CodexEvent({required this.type, required this.data});

  /// SSE event name. We use `'codex'` for codex JSONL lines, `'log'` for
  /// stderr passthrough, `'end'` for process termination, `'error'` for
  /// fatal client/server errors.
  final String type;

  /// Decoded JSON payload (may be empty if the server sent malformed data).
  final Map<String, dynamic> data;
}

@immutable
class RunningThread {
  const RunningThread({
    required this.threadId,
    required this.directory,
    required this.startedAt,
    required this.pid,
  });

  final String threadId;
  final String directory;
  final DateTime startedAt;
  final int pid;

  factory RunningThread.fromJson(Map<String, dynamic> j) => RunningThread(
        threadId: j['thread_id'] as String? ?? '',
        directory: j['directory'] as String? ?? '',
        startedAt: DateTime.tryParse(j['started_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        pid: (j['pid'] as num?)?.toInt() ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------

class CodexClient {
  CodexClient({required Uri baseUrl, String? bearerToken})
      : _base = baseUrl.toString().replaceAll(RegExp(r'/$'), ''),
        _bearer = bearerToken,
        _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl.toString().replaceAll(RegExp(r'/$'), ''),
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 30),
            headers: {
              'Accept': 'application/json',
              if (bearerToken != null && bearerToken.isNotEmpty)
                'Authorization': 'Bearer $bearerToken',
            },
          ),
        );

  final String _base;
  final String? _bearer;
  final Dio _dio;

  // -------------------------------------------------------------------------
  // SSE: start a new thread
  // -------------------------------------------------------------------------

  /// Start a fresh codex thread with the given prompt. The returned stream
  /// emits parsed [CodexEvent]s and closes when the codex process exits.
  ///
  /// The very first non-end event is typically `thread.started` whose
  /// `thread_id` you should persist as your "session id".
  Stream<CodexEvent> startThread({
    required String directory,
    required String prompt,
    String? model,
  }) {
    final body = <String, Object?>{
      'directory': directory,
      'prompt': prompt,
      if (model != null && model.isNotEmpty) 'model': model,
    };
    return _ssePost('/codex/threads', body);
  }

  /// Resume an existing thread with a follow-up prompt.
  Stream<CodexEvent> resumeThread({
    required String threadId,
    required String prompt,
    String? directory,
    String? model,
  }) {
    final body = <String, Object?>{
      'prompt': prompt,
      if (directory != null && directory.isNotEmpty) 'directory': directory,
      if (model != null && model.isNotEmpty) 'model': model,
    };
    return _ssePost('/codex/threads/$threadId/messages', body);
  }

  /// Abort the currently-running codex process for this thread (if any).
  Future<void> abortThread(String threadId) async {
    await _dio.post<dynamic>('/codex/threads/$threadId/abort');
  }

  /// Snapshot of running threads.
  Future<List<RunningThread>> listRunning() async {
    final res = await _dio.get<Map<String, dynamic>>('/codex/threads');
    final list = (res.data?['threads'] as List<dynamic>?) ?? const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(RunningThread.fromJson)
        .toList(growable: false);
  }

  Future<bool> ping() async {
    try {
      final res = await _dio.get<dynamic>('/codex/threads');
      return res.statusCode == 200;
    } on DioException {
      return false;
    }
  }

  void close() => _dio.close(force: true);

  // -------------------------------------------------------------------------
  // SSE plumbing — built on dart:io HttpClient for true chunked streaming on
  // iOS. Dart's default http client / Dio sometimes buffers the
  // entire body before exposing it; HttpClient does not.
  // -------------------------------------------------------------------------

  Stream<CodexEvent> _ssePost(
    String path,
    Map<String, Object?> body,
  ) {
    final controller = StreamController<CodexEvent>();
    _runSseRequest(path, body, controller);
    return controller.stream;
  }

  Future<void> _runSseRequest(
    String path,
    Map<String, Object?> body,
    StreamController<CodexEvent> controller,
  ) async {
    final url = Uri.parse('$_base$path');
    HttpClient? http;
    HttpClientRequest? req;
    HttpClientResponse? res;
    StreamSubscription<List<int>>? sub;

    try {
      http = HttpClient();
      http.autoUncompress = false;
      req = await http.postUrl(url);
      req.headers.set('Accept', 'text/event-stream');
      req.headers.set('Content-Type', 'application/json; charset=utf-8');
      if (_bearer != null && _bearer!.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $_bearer');
      }
      req.add(utf8.encode(jsonEncode(body)));
      res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        controller.add(CodexEvent(
          type: 'error',
          data: {'message': 'HTTP ${res.statusCode}'},
        ));
        await controller.close();
        return;
      }

      String? eventType;
      final dataBuf = StringBuffer();
      String remainder = '';

      sub = res.listen(
        (List<int> chunk) {
          final text = remainder + utf8.decode(chunk, allowMalformed: true);
          final lines = text.split('\n');
          remainder = lines.removeLast();

          for (final raw in lines) {
            final line = raw.endsWith('\r')
                ? raw.substring(0, raw.length - 1)
                : raw;

            if (line.isEmpty) {
              if (dataBuf.isNotEmpty) {
                _dispatch(controller, eventType ?? 'codex', dataBuf.toString());
              }
              eventType = null;
              dataBuf.clear();
              continue;
            }
            if (line.startsWith(':')) continue;

            final colon = line.indexOf(':');
            final field = colon >= 0 ? line.substring(0, colon) : line;
            final value = colon >= 0
                ? (line.length > colon + 1 && line[colon + 1] == ' '
                    ? line.substring(colon + 2)
                    : line.substring(colon + 1))
                : '';
            switch (field) {
              case 'event':
                eventType = value;
              case 'data':
                if (dataBuf.isNotEmpty) dataBuf.writeln();
                dataBuf.write(value);
              default:
                break;
            }
          }
        },
        onError: (Object e) {
          if (!controller.isClosed) {
            controller.add(CodexEvent(
              type: 'error',
              data: {'message': e.toString()},
            ));
          }
          controller.close();
        },
        onDone: () {
          // Some servers send the last event without a trailing blank line.
          if (dataBuf.isNotEmpty && !controller.isClosed) {
            _dispatch(controller, eventType ?? 'codex', dataBuf.toString());
          }
          controller.close();
        },
        cancelOnError: true,
      );

      // Close upstream subscription if the consumer cancels.
      controller.onCancel = () async {
        await sub?.cancel();
        try {
          http?.close(force: true);
        } catch (_) {}
      };
    } catch (e) {
      if (!controller.isClosed) {
        controller.add(CodexEvent(
          type: 'error',
          data: {'message': e.toString()},
        ));
        await controller.close();
      }
      try {
        http?.close(force: true);
      } catch (_) {}
    }
  }

  static void _dispatch(
    StreamController<CodexEvent> controller,
    String type,
    String data,
  ) {
    if (controller.isClosed) return;
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(data);
      parsed = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'_raw': decoded};
    } catch (_) {
      parsed = <String, dynamic>{'_raw': data};
    }
    controller.add(CodexEvent(type: type, data: parsed));
  }
}
