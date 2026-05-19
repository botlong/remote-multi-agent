library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gateway_client.dart';
import '../models/gateway_event.dart';
import '../models/gateway_session.dart';
import '../models/message.dart';
import '../models/part.dart';
import 'gateway_client_provider.dart';

enum GatewayChatConnectionState { connecting, connected, disconnected }

@immutable
class GatewayChatState {
  const GatewayChatState({
    required this.sessionId,
    required this.session,
    required this.messages,
    required this.isStreaming,
    required this.connection,
    this.error,
  });

  final String sessionId;
  final GatewaySession? session;
  final Map<String, Message> messages;
  final bool isStreaming;
  final GatewayChatConnectionState connection;
  final String? error;

  Iterable<Message> get orderedMessages => messages.values;
  List<Message> get items => messages.values.toList(growable: false);

  static GatewayChatState initial(String sessionId) => GatewayChatState(
        sessionId: sessionId,
        session: null,
        messages: const {},
        isStreaming: false,
        connection: GatewayChatConnectionState.connecting,
      );

  GatewayChatState copyWith({
    String? sessionId,
    GatewaySession? session,
    Map<String, Message>? messages,
    bool? isStreaming,
    GatewayChatConnectionState? connection,
    String? error,
    bool clearError = false,
  }) =>
      GatewayChatState(
        sessionId: sessionId ?? this.sessionId,
        session: session ?? this.session,
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        connection: connection ?? this.connection,
        error: clearError ? null : (error ?? this.error),
      );
}

class GatewayChatStore extends StateNotifier<GatewayChatState> {
  GatewayChatStore({
    required GatewayClient client,
    required String sessionId,
  })  : _client = client,
        super(GatewayChatState.initial(sessionId)) {
    _load();
    _bindEvents();
  }

  final GatewayClient _client;
  StreamSubscription<GatewayEvent>? _eventSub;

  Future<void> _load() async {
    try {
      final session = await _client.getSession(state.sessionId);
      final rawMessages = await _client.listMessages(state.sessionId);
      final next = Map<String, Message>.from(state.messages);
      for (final json in rawMessages) {
        final message = Message.fromJson(json);
        if (message.id.isNotEmpty) {
          final existing = next[message.id];
          if (existing == null ||
              message.parts.length >= existing.parts.length) {
            next[message.id] = message;
          }
        }
      }
      state = state.copyWith(session: session, messages: next);
    } catch (error) {
      state = state.copyWith(error: error.toString());
    }
  }

  void _bindEvents() {
    state = state.copyWith(connection: GatewayChatConnectionState.connecting);
    _eventSub = _client.events(state.sessionId).listen(
      _onEvent,
      onError: (Object error) {
        state = state.copyWith(
          connection: GatewayChatConnectionState.disconnected,
          error: error.toString(),
        );
      },
      onDone: () {
        state =
            state.copyWith(connection: GatewayChatConnectionState.disconnected);
      },
    );
  }

  Future<void> sendMessage(
    String text, {
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    if (text.trim().isEmpty && attachments.isEmpty) return;
    state = state.copyWith(isStreaming: true, clearError: true);
    await _client.sendMessage(
      sessionId: state.sessionId,
      text: text,
      parts: attachments,
    );
  }

  Future<void> sendSlashCommand(String command) async {
    if (command.trim().isEmpty) return;
    state = state.copyWith(isStreaming: true, clearError: true);
    await _client.sendSlashCommand(
      sessionId: state.sessionId,
      command: command,
    );
  }

  Future<void> abort() async {
    await _client.abortSession(state.sessionId);
    state = state.copyWith(isStreaming: false);
  }

  void _onEvent(GatewayEvent event) {
    if (state.connection != GatewayChatConnectionState.connected) {
      state = state.copyWith(connection: GatewayChatConnectionState.connected);
    }
    switch (event.type) {
      case 'message.created':
      case 'message.updated':
        _onMessage(event.data);
      case 'message.part.updated':
        _onPart(event.data);
      case 'message.delta':
        _onMessageDelta(event);
      case 'message.part.delta':
        _onPartDelta(event.data);
      case 'session.updated':
        _onSession(event.data);
      case 'session.started':
      case 'session.completed':
        state = state.copyWith(isStreaming: event.type != 'session.completed');
      case 'session.error':
        state = state.copyWith(
          isStreaming: false,
          error: _stringMessage(event.data['error']) ??
              _stringMessage(event.data['message']) ??
              'session error',
        );
      case 'status.updated':
        state = state.copyWith(
          isStreaming: event.data['status']?.toString() == 'running',
        );
      default:
        break;
    }
  }

  void _onSession(Map<String, dynamic> data) {
    final session = data['session'] is Map
        ? GatewaySession.fromJson(
            (data['session'] as Map).cast<String, dynamic>(),
          )
        : GatewaySession.fromJson(data);
    state = state.copyWith(session: session);
  }

  void _onMessage(Map<String, dynamic> data) {
    final messageJson = data['message'] is Map
        ? (data['message'] as Map).cast<String, dynamic>()
        : data['info'] is Map
            ? (data['info'] as Map).cast<String, dynamic>()
            : data;
    final message = Message.fromJson(messageJson);
    if (message.id.isEmpty) return;
    final existing = state.messages[message.id];
    final merged = existing == null
        ? message
        : existing.copyWith(
            role: message.role,
            status: message.status,
            createdAtMs: message.createdAtMs ?? existing.createdAtMs,
            completedAtMs: message.completedAtMs ?? existing.completedAtMs,
            modelId: message.modelId ?? existing.modelId,
            providerId: message.providerId ?? existing.providerId,
          );
    final next = Map<String, Message>.from(state.messages)
      ..[merged.id] = merged;
    state = state.copyWith(messages: next, clearError: true);
  }

  void _onPart(Map<String, dynamic> data) {
    final partJson = data['part'] is Map
        ? (data['part'] as Map).cast<String, dynamic>()
        : data;
    final part = Part.fromJson(partJson);
    if (part.id.isEmpty) return;
    final messageId = part.messageId;
    if (messageId.isEmpty) return;
    final existing = state.messages[messageId];
    if (existing == null) {
      final placeholder = Message(
        id: messageId,
        role: MessageRole.unknown,
        sessionId: state.sessionId,
        status: MessageStatus.running,
        parts: {part.id: part},
      );
      final next = Map<String, Message>.from(state.messages)
        ..[messageId] = placeholder;
      state = state.copyWith(messages: next);
      return;
    }
    final next = Map<String, Message>.from(state.messages)
      ..[messageId] = existing.withPartUpsert(part);
    state = state.copyWith(messages: next);
  }

  void _onMessageDelta(GatewayEvent event) {
    final data = event.data;
    final messageId = data['messageID'] as String? ??
        data['messageId'] as String? ??
        data['id'] as String? ??
        'gateway_${event.sessionId}_${state.messages.length}';
    final partId = data['partID'] as String? ??
        data['partId'] as String? ??
        '${messageId}_text';
    final delta = data['delta'] ?? data['text'] ?? data['content'];
    if (delta is! String || delta.isEmpty) return;
    _onPartDelta(<String, dynamic>{
      'messageId': messageId,
      'partId': partId,
      'field': data['field'] as String? ?? 'text',
      'delta': delta,
    });
  }

  void _onPartDelta(Map<String, dynamic> data) {
    final messageId =
        data['messageID'] as String? ?? data['messageId'] as String? ?? '';
    final partId = data['partID'] as String? ?? data['partId'] as String? ?? '';
    final field = data['field'] as String? ?? 'text';
    final delta = data['delta'];
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
      nextPart = field == 'reasoning'
          ? ReasoningPart(
              id: partId,
              messageId: messageId,
              sessionId: state.sessionId,
              text: delta,
            )
          : TextPart(
              id: partId,
              messageId: messageId,
              sessionId: state.sessionId,
              text: delta,
            );
    } else {
      return;
    }

    if (existing == null) {
      final placeholder = Message(
        id: messageId,
        role: MessageRole.unknown,
        sessionId: state.sessionId,
        status: MessageStatus.running,
        parts: {partId: nextPart},
      );
      final next = Map<String, Message>.from(state.messages)
        ..[messageId] = placeholder;
      state = state.copyWith(messages: next);
      return;
    }
    final next = Map<String, Message>.from(state.messages)
      ..[messageId] = existing.withPartUpsert(nextPart);
    state = state.copyWith(messages: next);
  }

  static String? _stringMessage(Object? value) => value is String
      ? value
      : value is Map
          ? (value['message'] as String?)
          : value?.toString();

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }
}

final gatewayChatStoreProvider = StateNotifierProvider.autoDispose
    .family<GatewayChatStore, GatewayChatState, String>(
  (ref, sessionId) {
    final client = ref.watch(gatewayClientProvider);
    return GatewayChatStore(client: client, sessionId: sessionId);
  },
);

final gatewayChatProvider = gatewayChatStoreProvider;
