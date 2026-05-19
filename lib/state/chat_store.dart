/// Per-session chat state, fed by SSE events.
///
/// Responsibilities
///   1. Maintain an ordered list of messages.
///   2. Apply `message.updated` and `message.part.updated` events as patches.
///   3. Expose connection state for the UI's "Connecting / Live / Offline" pill.
///
/// We deliberately keep the reducer pure — given the same event sequence it
/// always produces the same state. This makes restoring history (replay
/// `GET /session/:id/messages` then live-tail `/event`) a one-pass operation
/// later on.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/opencode_client.dart';
import '../api/sse_stream.dart';
import '../models/message.dart';
import '../models/part.dart';

@immutable
class ChatState {
  const ChatState({
    required this.sessionId,
    required this.messages,
    required this.isStreaming,
    required this.connection,
    this.error,
  });

  final String sessionId;

  /// Insertion-ordered. We never mutate in place; reducers produce a new map.
  final Map<String, Message> messages;
  final bool isStreaming;
  final SseState connection;
  final String? error;

  Iterable<Message> get orderedMessages => messages.values;

  static ChatState initial(String sessionId) => ChatState(
        sessionId: sessionId,
        messages: const {},
        isStreaming: false,
        connection: SseState.connecting,
      );

  ChatState copyWith({
    Map<String, Message>? messages,
    bool? isStreaming,
    SseState? connection,
    String? error,
    bool clearError = false,
  }) =>
      ChatState(
        sessionId: sessionId,
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        connection: connection ?? this.connection,
        error: clearError ? null : (error ?? this.error),
      );
}

class ChatController extends StateNotifier<ChatState> {
  ChatController({
    required String sessionId,
    required SseClient sse,
    required OpencodeClient client,
  })  : _sse = sse,
        _client = client,
        super(ChatState.initial(sessionId)) {
    _eventSub = _sse.events.listen(_onEvent);
    _stateSub = _sse.state.listen((s) {
      state = state.copyWith(connection: s);
    });
    // Load history + start polling as fallback for SSE issues on iOS.
    init();
    _startPolling();
  }

  final SseClient _sse;
  final OpencodeClient _client;
  StreamSubscription<SseEvent>? _eventSub;
  StreamSubscription<SseState>? _stateSub;
  Timer? _pollTimer;

  /// Load existing messages from the REST API and populate state before
  /// SSE takes over with live updates. Silently fails on 502 / network errors.
  Future<void> init() async {
    final rawMessages = await _client.listMessages(state.sessionId);
    if (rawMessages.isEmpty) return;

    final next = Map<String, Message>.from(state.messages);
    for (final json in rawMessages) {
      final msg = Message.fromJson(json);
      if (msg.id.isNotEmpty) {
        next[msg.id] = msg;
      }
    }
    state = state.copyWith(messages: next);
  }

  /// Poll every 2 seconds as a fallback. On iOS, SSE streaming via Dio
  /// may not deliver events in real-time due to platform buffering.
  /// Polling ensures the user always sees responses even if SSE is delayed.
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        final rawMessages = await _client.listMessages(state.sessionId);
        if (rawMessages.isEmpty) return;

        final next = Map<String, Message>.from(state.messages);
        bool changed = false;
        for (final json in rawMessages) {
          final msg = Message.fromJson(json);
          if (msg.id.isEmpty) continue;
          final existing = next[msg.id];
          if (existing == null || msg.parts.length > existing.parts.length) {
            next[msg.id] = msg;
            changed = true;
          }
        }
        if (changed) {
          state = state.copyWith(messages: next);
        }
      } catch (_) {
        // Silently ignore polling errors
      }
    });
  }

  void _onEvent(SseEvent ev) {
    final type = ev.data['type'] as String? ?? ev.type;
    final props =
        (ev.data['properties'] as Map?)?.cast<String, dynamic>() ?? const {};

    switch (type) {
      case 'message.updated':
        _onMessageUpdated(props);
      case 'message.part.updated':
        _onPartUpdated(props);
      case 'message.part.delta':
        _onPartDelta(props);
      case 'session.error':
        final err = props['error'];
        state = state.copyWith(
          error: err is Map ? err['message'] as String? : err?.toString(),
        );
      case 'server.connected':
      case 'session.updated':
        // We don't change message state here; session updates affect the
        // SessionListController instead.
        break;
    }
  }

  void _onMessageUpdated(Map<String, dynamic> props) {
    final info = (props['info'] as Map?)?.cast<String, dynamic>();
    if (info == null) return;
    if (info['sessionID'] != null && info['sessionID'] != state.sessionId) {
      return;
    }

    final incoming = Message.fromJson(info);
    final existing = state.messages[incoming.id];
    final merged = existing == null
        ? incoming
        : existing.copyWith(
            role: incoming.role,
            status: incoming.status,
            createdAtMs: incoming.createdAtMs ?? existing.createdAtMs,
            completedAtMs: incoming.completedAtMs ?? existing.completedAtMs,
            modelId: incoming.modelId ?? existing.modelId,
            providerId: incoming.providerId ?? existing.providerId,
          );

    final next = Map<String, Message>.from(state.messages);
    next[merged.id] = merged;
    state = state.copyWith(messages: next, clearError: true);
  }

  void _onPartUpdated(Map<String, dynamic> props) {
    final sessionId = props['sessionID'] as String? ?? '';
    if (sessionId != state.sessionId) return;
    final partJson = (props['part'] as Map?)?.cast<String, dynamic>();
    if (partJson == null) return;
    // The messageID lives INSIDE the part object, not at properties level.
    // (Discovered by dumping raw SSE; see scripts/dump-sse-raw.mjs.)
    final messageId = partJson['messageID'] as String? ?? '';
    if (messageId.isEmpty) return;

    final part = Part.fromJson(partJson);
    final existing = state.messages[messageId];
    final next = Map<String, Message>.from(state.messages);
    if (existing == null) {
      // Part arrived before message.updated — fabricate a placeholder.
      // role is unknown here; the eventual message.updated will fix it.
      next[messageId] = Message(
        id: messageId,
        role: MessageRole.unknown,
        sessionId: sessionId,
        status: MessageStatus.running,
        parts: {part.id: part},
      );
    } else {
      next[messageId] = existing.withPartUpsert(part);
    }
    state = state.copyWith(messages: next);
  }

  /// Streamed token delta for a text/reasoning part.
  ///
  /// Wire shape (observed):
  ///   properties: \{
  ///     sessionID, messageID, partID,
  ///     field: 'text' or 'reasoning' or other,
  ///     delta: '\<chunk\>',
  ///   \}
  ///
  /// We append the delta onto whatever part we currently hold for `partID`.
  /// If the part doesn't exist yet (delta beat the part.updated event), we
  /// create a fresh TextPart so we never lose tokens.
  void _onPartDelta(Map<String, dynamic> props) {
    final sessionId = props['sessionID'] as String? ?? '';
    if (sessionId != state.sessionId) return;
    final messageId = props['messageID'] as String? ?? '';
    final partId = props['partID'] as String? ?? '';
    final field = props['field'] as String? ?? 'text';
    final delta = props['delta'];
    if (messageId.isEmpty || partId.isEmpty || delta is! String) return;

    final existing = state.messages[messageId];
    final existingPart = existing?.parts[partId];

    Part nextPart;
    if (existingPart is TextPart && field == 'text') {
      nextPart = TextPart(
        id: existingPart.id,
        messageId: existingPart.messageId,
        sessionId: existingPart.sessionId,
        text: existingPart.text + delta,
      );
    } else if (existingPart is ReasoningPart && field == 'reasoning') {
      nextPart = ReasoningPart(
        id: existingPart.id,
        messageId: existingPart.messageId,
        sessionId: existingPart.sessionId,
        text: existingPart.text + delta,
      );
    } else if (existingPart == null) {
      // Brand-new part — most often `field: text`.
      if (field == 'reasoning') {
        nextPart = ReasoningPart(
          id: partId,
          messageId: messageId,
          sessionId: sessionId,
          text: delta,
        );
      } else {
        nextPart = TextPart(
          id: partId,
          messageId: messageId,
          sessionId: sessionId,
          text: delta,
        );
      }
    } else {
      // Mismatched type vs field — keep existing untouched.
      return;
    }

    final next = Map<String, Message>.from(state.messages);
    if (existing == null) {
      next[messageId] = Message(
        id: messageId,
        role: MessageRole.unknown,
        sessionId: sessionId,
        status: MessageStatus.running,
        parts: {partId: nextPart},
      );
    } else {
      next[messageId] = existing.withPartUpsert(nextPart);
    }
    state = state.copyWith(messages: next);
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _eventSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }
}
