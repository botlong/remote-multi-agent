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
import 'notification_service.dart';

enum GatewayChatConnectionState { connecting, connected, disconnected }

@immutable
class TokenUsage {
  const TokenUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.totalTokens = 0,
  });

  final int inputTokens;
  final int outputTokens;
  final int totalTokens;

  double get ratio => totalTokens > 0 ? totalTokens / contextLimit : 0;
  static const int contextLimit = 128000;
}

@immutable
class TerminalLine {
  const TerminalLine({
    required this.stream,
    required this.text,
    required this.timestampMs,
  });

  final String stream;
  final String text;
  final int timestampMs;
}

enum ActivityKind {
  status,
  command,
  tool,
  output,
  checklist;

  static ActivityKind from(String? raw) => switch (raw) {
        'command' => ActivityKind.command,
        'tool' => ActivityKind.tool,
        'output' => ActivityKind.output,
        'checklist' => ActivityKind.checklist,
        _ => ActivityKind.status,
      };
}

enum ActivityStatus {
  running,
  completed,
  error,
  info;

  static ActivityStatus from(String? raw) => switch (raw) {
        'running' => ActivityStatus.running,
        'completed' => ActivityStatus.completed,
        'error' => ActivityStatus.error,
        _ => ActivityStatus.info,
      };

  bool get isTerminal => this == completed || this == error;
}

@immutable
class ActivityItem {
  const ActivityItem({
    required this.id,
    required this.kind,
    required this.status,
    required this.title,
    required this.sequence,
    this.command,
    this.tool,
    this.stream,
    this.output = '',
    this.outputDelta = '',
    this.timestampMs,
  });

  final String id;
  final ActivityKind kind;
  final ActivityStatus status;
  final String title;
  final int sequence;
  final String? command;
  final String? tool;
  final String? stream;
  final String output;
  final String outputDelta;
  final int? timestampMs;

  factory ActivityItem.fromJson(
    Map<String, dynamic> json, {
    int? timestampMs,
  }) {
    final id = json['id'] as String? ?? '';
    final kind = ActivityKind.from(json['kind'] as String?);
    final status = ActivityStatus.from(json['status'] as String?);
    final command = _stringOrNull(json['command']);
    final tool = _stringOrNull(json['tool']);
    final stream = _stringOrNull(json['stream']);
    final output = _stringOrNull(json['output']) ?? '';
    final outputDelta = _stringOrNull(json['outputDelta']) ?? '';
    final title = _stringOrNull(json['title']) ??
        command ??
        tool ??
        (stream != null ? '$stream output' : kind.name);
    return ActivityItem(
      id: id,
      kind: kind,
      status: status,
      title: title,
      sequence: _readInt(json['sequence']) ?? 0,
      command: command,
      tool: tool,
      stream: stream,
      output: output,
      outputDelta: outputDelta,
      timestampMs: timestampMs,
    );
  }

  ActivityItem merge(ActivityItem incoming) {
    final nextOutput = incoming.outputDelta.isNotEmpty
        ? output + incoming.outputDelta
        : incoming.output.isNotEmpty
            ? incoming.output
            : output;
    return ActivityItem(
      id: id,
      kind: incoming.kind,
      status: incoming.status,
      title: incoming.title.isNotEmpty ? incoming.title : title,
      sequence: incoming.sequence == 0 ? sequence : incoming.sequence,
      command: incoming.command ?? command,
      tool: incoming.tool ?? tool,
      stream: incoming.stream ?? stream,
      output: nextOutput,
      timestampMs: incoming.timestampMs ?? timestampMs,
    );
  }

  ActivityItem normalizeOutput() {
    if (output.isNotEmpty || outputDelta.isEmpty) return this;
    return ActivityItem(
      id: id,
      kind: kind,
      status: status,
      title: title,
      sequence: sequence,
      command: command,
      tool: tool,
      stream: stream,
      output: outputDelta,
      timestampMs: timestampMs,
    );
  }
}

String? _stringOrNull(Object? value) {
  if (value is String && value.isNotEmpty) return value;
  return null;
}

int? _readInt(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

@immutable
class ActiveTool {
  const ActiveTool({
    required this.name,
    this.info,
    this.icon,
  });

  final String name;
  final String? info;
  final String? icon;

  String get displayLabel {
    if (info != null && info!.isNotEmpty) return '$name  $info';
    return name;
  }
}

@immutable
class GatewayChatState {
  const GatewayChatState({
    required this.sessionId,
    required this.session,
    required this.messages,
    required this.isStreaming,
    required this.connection,
    required this.terminalLines,
    required this.activities,
    this.error,
    this.usage,
    this.activeTool,
  });

  final String sessionId;
  final GatewaySession? session;
  final Map<String, Message> messages;
  final bool isStreaming;
  final GatewayChatConnectionState connection;
  final List<TerminalLine> terminalLines;
  final List<ActivityItem> activities;
  final String? error;
  final TokenUsage? usage;
  final ActiveTool? activeTool;

  String get sessionTitle => session?.title ?? '';
  Iterable<Message> get orderedMessages {
    final list = messages.values.toList(growable: false);
    list.sort((a, b) => (a.createdAtMs ?? 0).compareTo(b.createdAtMs ?? 0));
    return list;
  }
  List<Message> get items => messages.values.toList(growable: false);

  static GatewayChatState initial(String sessionId) => GatewayChatState(
        sessionId: sessionId,
        session: null,
        messages: const {},
        isStreaming: false,
        connection: GatewayChatConnectionState.connecting,
        terminalLines: const <TerminalLine>[],
        activities: const <ActivityItem>[],
        activeTool: null,
      );

  GatewayChatState copyWith({
    String? sessionId,
    GatewaySession? session,
    Map<String, Message>? messages,
    bool? isStreaming,
    GatewayChatConnectionState? connection,
    List<TerminalLine>? terminalLines,
    List<ActivityItem>? activities,
    String? error,
    bool clearError = false,
    TokenUsage? usage,
    ActiveTool? activeTool,
    bool clearActiveTool = false,
  }) =>
      GatewayChatState(
        sessionId: sessionId ?? this.sessionId,
        session: session ?? this.session,
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        connection: connection ?? this.connection,
        terminalLines: terminalLines ?? this.terminalLines,
        activities: activities ?? this.activities,
        error: clearError ? null : (error ?? this.error),
        usage: usage ?? this.usage,
        activeTool: clearActiveTool ? null : (activeTool ?? this.activeTool),
      );
}

class GatewayChatStore extends StateNotifier<GatewayChatState> {
  GatewayChatStore({
    required GatewayClient client,
    required String sessionId,
  })  : _client = client,
        super(GatewayChatState.initial(sessionId)) {
    _bindEvents();
    _load();
  }

  final GatewayClient _client;
  StreamSubscription<GatewayEvent>? _eventSub;

  Future<void> _load() async {
    try {
      final session = await _client.getSession(state.sessionId);
      final rawMessages = await _client.listMessages(state.sessionId);
      // Merge REST snapshot with the LATEST state.messages — not the snapshot
      // we took before the await — otherwise any SSE deltas that arrived
      // mid-flight get clobbered.
      final next = Map<String, Message>.from(state.messages);
      for (final json in rawMessages) {
        final message = Message.fromJson(json);
        if (message.id.isEmpty) continue;
        final existing = next[message.id];
        if (existing == null) {
          next[message.id] = message;
          continue;
        }
        // Per-part merge: keep whichever version has more content so REST
        // snapshots don't clobber in-flight SSE deltas, but new parts from
        // REST (e.g. tool calls) are still accepted.
        final mergedParts = Map<String, Part>.from(message.parts);
        for (final entry in existing.parts.entries) {
          final restPart = mergedParts[entry.key];
          if (restPart == null) {
            mergedParts[entry.key] = entry.value;
          } else {
            final existingLen = _partTextLength(entry.value);
            final restLen = _partTextLength(restPart);
            if (existingLen > restLen) {
              mergedParts[entry.key] = entry.value;
            }
          }
        }
        next[message.id] = message.copyWith(parts: mergedParts);
      }
      state = state.copyWith(
        session: state.session ?? session,
        messages: next,
      );
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

  /// Drop the current SSE subscription and create a new one. Call this when
  /// the app resumes from background — the OS may have killed the underlying
  /// socket without firing onDone, so we can't trust the existing stream.
  Future<void> reconnect() async {
    await _eventSub?.cancel();
    _eventSub = null;
    _bindEvents();
    // Also re-pull state in case we missed events while backgrounded.
    await _load();
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

  Future<void> handoff({
    required String agentId,
    String? prompt,
    String? modelId,
  }) async {
    state = state.copyWith(isStreaming: true, clearError: true);
    await _client.handoffSession(
      sessionId: state.sessionId,
      agentId: agentId,
      prompt: prompt,
      modelId: modelId,
    );
  }

  Future<void> deleteMessage(String messageId) async {
    await _client.deleteMessage(state.sessionId, messageId);
    final next = Map<String, Message>.from(state.messages)..remove(messageId);
    state = state.copyWith(messages: next);
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
      case 'message.completed':
        _onMessageCompleted(event.data);
      case 'message.delta':
        _onMessageDelta(event);
      case 'message.deleted':
        final messageId = event.data['messageId'] as String?;
        if (messageId != null) {
          final next = Map<String, Message>.from(state.messages)
            ..remove(messageId);
          state = state.copyWith(messages: next);
        }
      case 'message.part.delta':
        _onPartDelta(event.data);
      case 'session.updated':
        _onSession(event.data);
      case 'session.started':
        state = state.copyWith(
          isStreaming: true,
          activities: const <ActivityItem>[],
          clearActiveTool: true,
        );
      case 'session.completed':
        state = state.copyWith(isStreaming: false, clearActiveTool: true);
        showAppNotification(
          title: 'Agent finished',
          body: state.sessionTitle.isNotEmpty
              ? state.sessionTitle
              : 'Session completed successfully',
          sessionId: state.sessionId,
        );
      case 'session.error':
        final errMsg = _stringMessage(event.data['error']) ??
            _stringMessage(event.data['message']) ??
            'session error';
        state = state.copyWith(isStreaming: false, error: errMsg, clearActiveTool: true);
        showAppNotification(
          title: 'Agent error',
          body: errMsg,
          sessionId: state.sessionId,
        );
      case 'gateway.reconnected':
        // SSE just came back from a disconnect (e.g. gateway restart) — pull
        // the latest session + messages so we don't keep showing stale
        // 'running' bubbles for messages that ended while we were offline.
        _load();
      case 'session.usage':
        final u = event.data['usage'] as Map<String, dynamic>?;
        if (u != null) {
          state = state.copyWith(
            usage: TokenUsage(
              inputTokens: (u['inputTokens'] as num?)?.toInt() ?? 0,
              outputTokens: (u['outputTokens'] as num?)?.toInt() ?? 0,
              totalTokens: (u['totalTokens'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      case 'command.updated':
        _onCommandUpdated(event);
      case 'activity.updated':
        _onActivityUpdated(event);
      case 'status.updated':
        state = state.copyWith(
          isStreaming: event.data['status']?.toString() == 'running',
        );
      default:
        break;
    }
  }

  void _onMessageCompleted(Map<String, dynamic> data) {
    final messageJson = data['message'] is Map
        ? (data['message'] as Map).cast<String, dynamic>()
        : data;
    final messageId = messageJson['id'] as String? ?? '';
    if (messageId.isNotEmpty) {
      final existing = state.messages[messageId];
      if (existing != null) {
        final updated = existing.copyWith(status: MessageStatus.completed);
        final next = Map<String, Message>.from(state.messages)
          ..[messageId] = updated;
        state = state.copyWith(messages: next);
      }
    }
  }

  void _onSession(Map<String, dynamic> data) {
    final session = data['session'] is Map
        ? GatewaySession.fromJson(
            (data['session'] as Map).cast<String, dynamic>(),
          )
        : GatewaySession.fromJson(data);
    final isIdle = session.status == GatewaySessionStatus.idle ||
        session.status == GatewaySessionStatus.error ||
        session.status == GatewaySessionStatus.completed;
    state = state.copyWith(
      session: session,
      isStreaming: isIdle ? false : state.isStreaming,
    );
  }

  static const _maxTerminalLines = 500;
  static const _maxActivities = 80;

  void _onCommandUpdated(GatewayEvent event) {
    final stream = event.data['stream'] as String? ?? 'stdout';
    final text = event.data['text'] as String?;
    if (text == null || text.isEmpty) return;
    var next = <TerminalLine>[
      ...state.terminalLines,
      TerminalLine(
        stream: stream,
        text: text.endsWith('\n') ? text : '$text\n',
        timestampMs: event.timestampMs,
      ),
    ];
    if (next.length > _maxTerminalLines) {
      next = next.sublist(next.length - _maxTerminalLines);
    }
    state = state.copyWith(terminalLines: next);
  }

  void _onActivityUpdated(GatewayEvent event) {
    final rawActivity = event.data['activity'];
    if (rawActivity is! Map) return;
    final incoming = ActivityItem.fromJson(
      rawActivity.cast<String, dynamic>(),
      timestampMs: event.timestampMs,
    );
    if (incoming.id.isEmpty) return;

    final next = <ActivityItem>[...state.activities];
    final index = next.indexWhere((item) => item.id == incoming.id);
    final ActivityItem updated;
    if (index == -1) {
      updated = incoming.normalizeOutput();
      next.add(updated);
    } else {
      updated = next[index].merge(incoming);
      next[index] = updated;
    }
    next.sort((a, b) {
      final bySequence = a.sequence.compareTo(b.sequence);
      if (bySequence != 0) return bySequence;
      return (a.timestampMs ?? 0).compareTo(b.timestampMs ?? 0);
    });
    final bounded = next.length > _maxActivities
        ? next.sublist(next.length - _maxActivities)
        : next;

    if (updated.status == ActivityStatus.running &&
        (updated.kind == ActivityKind.command ||
            updated.kind == ActivityKind.tool)) {
      state = state.copyWith(
        activities: bounded,
        activeTool: ActiveTool(
          name: updated.command ?? updated.tool ?? updated.title,
          info: updated.command != null ? null : updated.title,
        ),
      );
      return;
    }

    state = state.copyWith(
      activities: bounded,
      clearActiveTool: updated.status.isTerminal,
    );
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
    if (existing == null) {
      final next = Map<String, Message>.from(state.messages)
        ..[message.id] = message;
      state = state.copyWith(messages: next, clearError: true);
      return;
    }
    // Prefer existing parts if they have more content (from deltas)
    final mergedParts = Map<String, Part>.from(message.parts);
    for (final entry in existing.parts.entries) {
      final incomingPart = mergedParts[entry.key];
      if (incomingPart == null) {
        mergedParts[entry.key] = entry.value;
      } else if (_partTextLength(entry.value) > _partTextLength(incomingPart)) {
        mergedParts[entry.key] = entry.value;
      }
    }
    final merged = existing.copyWith(
      role: message.role != MessageRole.unknown ? message.role : existing.role,
      status: message.status != MessageStatus.unknown
          ? message.status
          : existing.status,
      parts: mergedParts,
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

    // Track active tool for the activity bar
    if (part is ToolPart) {
      if (part.status == ToolStatus.running) {
        state = state.copyWith(
          activeTool: ActiveTool(
            name: part.tool,
            info: _extractToolInfo(part),
          ),
        );
      } else if (part.status.isTerminal) {
        state = state.copyWith(clearActiveTool: true);
      }
    }

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

  static String? _extractToolInfo(ToolPart part) {
    final input = part.input;
    if (input == null) return null;
    final path = input['filePath'] as String? ??
        input['path'] as String? ??
        input['file'] as String? ??
        input['file_path'] as String?;
    if (path != null) {
      final segments = path.split(RegExp(r'[/\\]'));
      return segments.length > 2
          ? '.../${segments.sublist(segments.length - 2).join('/')}'
          : path;
    }
    final command = input['command'] as String? ?? input['cmd'] as String?;
    if (command != null) {
      return command.length > 50 ? '${command.substring(0, 50)}...' : command;
    }
    final pattern = input['pattern'] as String? ?? input['query'] as String?;
    if (pattern != null) return pattern;
    return null;
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

  static int _partTextLength(Part p) => switch (p) {
        TextPart(:final text) => text.length,
        ReasoningPart(:final text) => text.length,
        _ => 0,
      };

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
