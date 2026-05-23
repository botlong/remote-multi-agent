/// Minimal Server-Sent Events client using dart:io HttpClient for true
/// chunked streaming on native iOS.
///
/// This native client relies on dart:io and is used by the mobile app.
// ignore_for_file: depend_on_referenced_packages
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io' show HttpClient, HttpClientRequest, HttpClientResponse;

import 'package:flutter/foundation.dart';

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Decoded SSE frame.
@immutable
class SseEvent {
  const SseEvent({required this.type, required this.data});
  final String type;
  final Map<String, dynamic> data;
}

/// Configuration for [SseClient].
@immutable
class SseConfig {
  const SseConfig({
    required this.url,
    this.bearerToken,
    this.reconnectMinDelay = const Duration(seconds: 1),
    this.reconnectMaxDelay = const Duration(seconds: 30),
    this.maxRetries = 12,
  });

  final Uri url;
  final String? bearerToken;
  final Duration reconnectMinDelay;
  final Duration reconnectMaxDelay;
  final int maxRetries;
}

/// Connection lifecycle state.
enum SseState { connecting, connected, disconnected }

/// A self-reconnecting SSE client backed by dart:io [HttpClient].
///
/// Delivers chunks in real-time on iOS (no buffering).
class SseClient {
  SseClient(this._config) {
    _start();
  }

  final SseConfig _config;

  final _controller = StreamController<SseEvent>.broadcast();
  final _stateController = StreamController<SseState>.broadcast();

  static const int _replaySize = 200;
  final ListQueue<SseEvent> _replay = ListQueue<SseEvent>();

  HttpClient? _httpClient;
  bool _disposed = false;
  int _attempt = 0;
  SseState _lastState = SseState.connecting;
  String? _lastEventId;

  // Stream subscription for the active response body.
  StreamSubscription<List<int>>? _responseSub;

  /// Decoded events. New listeners get the buffered replay first, then live.
  Stream<SseEvent> get events async* {
    // Snapshot the replay buffer so iteration is safe.
    final snapshot = List<SseEvent>.from(_replay);
    for (final e in snapshot) {
      yield e;
    }
    yield* _controller.stream;
  }

  /// Connection state. Current state is yielded immediately, then live updates.
  Stream<SseState> get state async* {
    yield _lastState;
    yield* _stateController.stream;
  }

  // -------------------------------------------------------------------------
  // Connection lifecycle
  // -------------------------------------------------------------------------

  Future<void> _start() async {
    if (_disposed) return;
    _emitState(SseState.connecting);

    _httpClient = HttpClient();
    // Don't follow redirects automatically for SSE — handle manually if needed.
    _httpClient!.autoUncompress = false;

    HttpClientRequest request;
    HttpClientResponse response;

    try {
      request = await _httpClient!.getUrl(_config.url);

      // Headers
      request.headers.set('Accept', 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');
      if (_config.bearerToken != null && _config.bearerToken!.isNotEmpty) {
        request.headers.set('Authorization', 'Bearer ${_config.bearerToken}');
      }
      if (_lastEventId != null) {
        request.headers.set('Last-Event-ID', _lastEventId!);
      }

      response = await request.close();

      if (response.statusCode != 200) {
        response.drain<void>();
        throw Exception('SSE handshake failed: HTTP ${response.statusCode}');
      }

      _emitState(SseState.connected);
      _attempt = 0;

      // Parse the chunked response line-by-line.
      await _consumeStream(response);

      // If we reach here the stream ended gracefully → reconnect.
      if (!_disposed) {
        _emitState(SseState.disconnected);
        _scheduleReconnect();
      }
    } catch (e) {
      if (_disposed) return;
      debugPrint('[SseClient] error: $e');
      _emitState(SseState.disconnected);
      _scheduleReconnect();
    }
  }

  /// Reads the response body as a stream of bytes, decodes UTF-8, splits into
  /// lines, and dispatches SSE events.
  Future<void> _consumeStream(HttpClientResponse response) async {
    String? eventType;
    final dataBuffer = StringBuffer();

    // We manually manage the subscription so we can cancel on dispose.
    final completer = Completer<void>();

    // Accumulates partial lines across chunk boundaries.
    String remainder = '';

    _responseSub = response.listen(
      (List<int> chunk) {
        if (_disposed) return;

        // Decode this chunk and split into lines.
        final text = remainder + utf8.decode(chunk, allowMalformed: true);
        final lines = text.split('\n');

        // The last element may be an incomplete line — save for next chunk.
        remainder = lines.removeLast();

        for (final rawLine in lines) {
          // Strip trailing \r if present (SSE spec allows \r\n).
          final line = rawLine.endsWith('\r')
              ? rawLine.substring(0, rawLine.length - 1)
              : rawLine;

          if (line.isEmpty) {
            // Empty line = end of event block.
            if (dataBuffer.isNotEmpty) {
              _dispatch(eventType ?? 'message', dataBuffer.toString());
            }
            eventType = null;
            dataBuffer.clear();
            continue;
          }

          // Comment line.
          if (line.startsWith(':')) continue;

          // Parse field:value
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
              if (dataBuffer.isNotEmpty) dataBuffer.writeln();
              dataBuffer.write(value);
            case 'id':
              if (value.isNotEmpty) _lastEventId = value;
            case 'retry':
              break;
          }
        }
      },
      onError: (Object error) {
        if (!completer.isCompleted) completer.completeError(error);
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete();
      },
      cancelOnError: true,
    );

    return completer.future;
  }

  // -------------------------------------------------------------------------
  // Event dispatch
  // -------------------------------------------------------------------------

  void _dispatch(String type, String data) {
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(data);
      parsed = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'_raw': decoded};
    } catch (_) {
      parsed = <String, dynamic>{'_raw': data};
    }

    final event = SseEvent(type: type, data: parsed);

    // Determine replay-worthiness from the inner `type` field or the SSE type.
    final t = parsed['type'] as String? ?? type;
    if (_isReplayWorthy(t)) {
      _replay.addLast(event);
      while (_replay.length > _replaySize) {
        _replay.removeFirst();
      }
    }

    if (!_controller.isClosed) {
      _controller.add(event);
    }
  }

  static bool _isReplayWorthy(String type) {
    switch (type) {
      case 'message.updated':
      case 'message.part.updated':
      case 'session.updated':
      case 'session.error':
      case 'session.idle':
        return true;
      // Delta events are incremental — replaying them after reconnect
      // would duplicate text (client fetches full state via REST).
      default:
        return false;
    }
  }

  // -------------------------------------------------------------------------
  // State management
  // -------------------------------------------------------------------------

  void _emitState(SseState s) {
    _lastState = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  // -------------------------------------------------------------------------
  // Reconnect with exponential backoff
  // -------------------------------------------------------------------------

  void _scheduleReconnect() {
    if (_disposed) return;
    _attempt++;
    if (_attempt > _config.maxRetries) {
      debugPrint('[SseClient] max retries ($_attempt) reached, giving up');
      return;
    }
    final base = _config.reconnectMinDelay.inMilliseconds;
    final max = _config.reconnectMaxDelay.inMilliseconds;
    // Exponential: base * 2^(attempt-1), capped at max.
    final wait = (base * (1 << (_attempt - 1).clamp(0, 6))).clamp(base, max);
    debugPrint('[SseClient] reconnecting in ${wait}ms (attempt $_attempt)');
    Future<void>.delayed(Duration(milliseconds: wait), () {
      if (!_disposed) _start();
    });
  }

  /// Manually trigger a reconnect (e.g. from a "Retry" button in the UI).
  void reconnect() {
    if (_disposed) return;
    _attempt = 0;
    _start();
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  Future<void> dispose() async {
    _disposed = true;
    await _responseSub?.cancel();
    _responseSub = null;
    _httpClient?.close(force: true);
    _httpClient = null;
    await _controller.close();
    await _stateController.close();
  }
}
