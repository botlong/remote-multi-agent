/// Per-thread chat state for the Codex backend.
///
/// Codex is conceptually different from OpenCode:
///   * One HTTP call = one *turn*. The connection closes when the codex
///     process exits.
///   * Resume across turns is just `POST /codex/threads/:id/messages` with
///     the next prompt. The server spawns a new codex process that reads
///     the persisted session.
///
/// We translate codex JSONL events into the existing [Message] / [Part] model
/// so we can reuse all the chat UI: bubbles, markdown, tool cards, copy
/// buttons. The mapping:
///
///   thread.started                         → record threadId
///   turn.started                           → start a new assistant message
///   item.started   {type:command_execution} → ToolPart(status: running, tool: bash, input.command)
///   item.completed {type:command_execution} → ToolPart(status: completed, output: aggregated_output)
///   item.completed {type:agent_message}     → TextPart(text)
///   item.completed {type:reasoning}         → ReasoningPart(text)
///   turn.completed                         → mark assistant message completed
///   error / log (stderr)                   → state.error
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/codex_client.dart';
import '../models/message.dart';
import '../models/part.dart';

@immutable
class CodexChatState {
  const CodexChatState({
    required this.threadId,
    required this.directory,
    required this.messages,
    required this.isStreaming,
    this.error,
    this.lastModel,
  });

  /// Empty until codex emits `thread.started`.
  final String threadId;
  final String directory;

  /// Insertion-ordered.
  final Map<String, Message> messages;
  final bool isStreaming;
  final String? error;
  final String? lastModel;

  Iterable<Message> get orderedMessages => messages.values;

  CodexChatState copyWith({
    String? threadId,
    String? directory,
    Map<String, Message>? messages,
    bool? isStreaming,
    String? error,
    bool clearError = false,
    String? lastModel,
  }) =>
      CodexChatState(
        threadId: threadId ?? this.threadId,
        directory: directory ?? this.directory,
        messages: messages ?? this.messages,
        isStreaming: isStreaming ?? this.isStreaming,
        error: clearError ? null : (error ?? this.error),
        lastModel: lastModel ?? this.lastModel,
      );

  static CodexChatState initial({
    required String threadId,
    required String directory,
  }) =>
      CodexChatState(
        threadId: threadId,
        directory: directory,
        messages: const {},
        isStreaming: false,
      );
}

/// Identifies a chat — for new threads we don't yet have a server-side id, so
/// the controller is keyed by a client-generated `localKey`.
@immutable
class CodexChatKey {
  const CodexChatKey({required this.localKey, this.threadId});
  final String localKey;
  final String? threadId;

  @override
  bool operator ==(Object other) =>
      other is CodexChatKey && other.localKey == localKey;
  @override
  int get hashCode => localKey.hashCode;
}

class CodexChatController extends StateNotifier<CodexChatState> {
  CodexChatController({
    required CodexClient client,
    required String localKey,
    String? threadId,
    String directory = '',
  })  : _client = client,
        _localKey = localKey,
        super(
          CodexChatState.initial(
            threadId: threadId ?? '',
            directory: directory,
          ),
        );

  final CodexClient _client;
  // ignore: unused_field
  final String _localKey;

  StreamSubscription<CodexEvent>? _sub;
  String? _activeAssistantMessageId;
  int _userMsgCounter = 0;
  int _asstMsgCounter = 0;
  int _itemSeq = 0;

  /// Send a prompt. If [threadId] is empty, this starts a new thread; the
  /// `thread.started` event will populate state.threadId.
  Future<void> send({
    required String prompt,
    required String directory,
    String? model,
  }) async {
    if (prompt.trim().isEmpty) return;
    if (state.isStreaming) return; // serialize turns

    // 1) Append the user message immediately so the UI shows it.
    final userId =
        'u_${++_userMsgCounter}_${DateTime.now().microsecondsSinceEpoch}';
    final userMessage = Message(
      id: userId,
      role: MessageRole.user,
      sessionId: state.threadId,
      status: MessageStatus.completed,
      parts: {
        'p_text': TextPart(
          id: 'p_text',
          messageId: userId,
          sessionId: state.threadId,
          text: prompt,
        ),
      },
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    final next = Map<String, Message>.from(state.messages)
      ..[userId] = userMessage;
    state = state.copyWith(
      messages: next,
      directory: directory,
      isStreaming: true,
      clearError: true,
    );

    // 2) Pre-create the assistant message so streaming parts can attach.
    final asstId =
        'a_${++_asstMsgCounter}_${DateTime.now().microsecondsSinceEpoch}';
    _activeAssistantMessageId = asstId;
    final asst = Message(
      id: asstId,
      role: MessageRole.assistant,
      sessionId: state.threadId,
      status: MessageStatus.running,
      parts: const {},
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      modelId: model ?? state.lastModel,
    );
    final withAsst = Map<String, Message>.from(state.messages)..[asstId] = asst;
    state = state.copyWith(messages: withAsst, lastModel: model);

    // 3) Open SSE stream — start vs resume.
    final stream = state.threadId.isEmpty
        ? _client.startThread(
            directory: directory,
            prompt: prompt,
            model: model,
          )
        : _client.resumeThread(
            threadId: state.threadId,
            prompt: prompt,
            directory: directory,
            model: model,
          );

    final completer = Completer<void>();
    _sub = stream.listen(
      _onEvent,
      onError: (Object e) {
        _finalize(error: '$e');
        if (!completer.isCompleted) completer.complete();
      },
      onDone: () {
        _finalize();
        if (!completer.isCompleted) completer.complete();
      },
    );

    await completer.future;
  }

  /// Abort the in-flight turn (if any).
  Future<void> abort() async {
    final id = state.threadId;
    if (id.isEmpty) {
      // Pre-thread-started; just cancel locally.
      await _sub?.cancel();
      _finalize();
      return;
    }
    try {
      await _client.abortThread(id);
    } catch (_) {/* ignore */}
    await _sub?.cancel();
    _finalize();
  }

  // -------------------------------------------------------------------------
  // Event handling
  // -------------------------------------------------------------------------

  void _onEvent(CodexEvent ev) {
    if (ev.type == 'end') {
      // Process exited; onDone will call _finalize.
      return;
    }
    if (ev.type == 'error') {
      final msg = ev.data['message']?.toString() ?? 'codex error';
      state = state.copyWith(error: msg);
      return;
    }
    if (ev.type == 'log') {
      // stderr: surface only if it's clearly an error line.
      return;
    }

    // 'codex' events → look at inner type.
    final type = ev.data['type'] as String? ?? '';
    switch (type) {
      case 'thread.started':
        final tid = ev.data['thread_id'] as String? ?? '';
        if (tid.isNotEmpty && state.threadId.isEmpty) {
          state = state.copyWith(threadId: tid);
        }
      case 'turn.started':
        // Already pre-created the assistant message in send().
        break;
      case 'item.started':
        _onItem(ev.data['item'], started: true);
      case 'item.completed':
        _onItem(ev.data['item'], started: false);
      case 'turn.completed':
        // Will be finalized when stream closes.
        break;
      default:
        break;
    }
  }

  void _onItem(Object? raw, {required bool started}) {
    if (raw is! Map) return;
    final item = raw.cast<String, dynamic>();
    final itemType = item['type'] as String? ?? '';
    final itemId = (item['id'] as String?)?.toString() ?? 'item_${++_itemSeq}';

    switch (itemType) {
      case 'command_execution':
        _upsertToolPart(
          partId: itemId,
          tool: 'bash',
          status: started ? ToolStatus.running : ToolStatus.completed,
          input: {
            'command': item['command'] ?? '',
          },
          output: item['aggregated_output'] ?? '',
          error: (item['exit_code'] is int && item['exit_code'] != 0)
              ? 'exit ${item['exit_code']}'
              : null,
        );
      case 'agent_message':
        if (!started) {
          _upsertTextPart(
            partId: itemId,
            text: (item['text'] as String?) ?? '',
          );
        }
      case 'reasoning':
        if (!started) {
          _upsertReasoningPart(
            partId: itemId,
            text: (item['text'] as String?) ?? '',
          );
        }
      case 'file_change':
        // Render as a tool card with the diff as output.
        _upsertToolPart(
          partId: itemId,
          tool: 'edit',
          status: started ? ToolStatus.running : ToolStatus.completed,
          input: {
            'path': item['path'] ?? item['filePath'] ?? '',
          },
          output: item['changes'] ?? item['summary'] ?? '',
          error: null,
        );
      case 'mcp_tool_call':
      case 'tool_call':
        _upsertToolPart(
          partId: itemId,
          tool: (item['name'] as String?) ?? 'tool',
          status: started ? ToolStatus.running : ToolStatus.completed,
          input: (item['arguments'] is Map)
              ? (item['arguments'] as Map).cast<String, dynamic>()
              : {'_raw': item['arguments']},
          output: item['result'] ?? item['output'] ?? '',
          error: item['error'] as String?,
        );
      default:
        // Unknown item type — represent as a debug tool card.
        if (!started) {
          _upsertToolPart(
            partId: itemId,
            tool: itemType.isEmpty ? 'unknown' : itemType,
            status: ToolStatus.completed,
            input: item,
            output: null,
            error: null,
          );
        }
    }
  }

  void _upsertTextPart({required String partId, required String text}) {
    final asstId = _activeAssistantMessageId;
    if (asstId == null) return;
    final msg = state.messages[asstId];
    if (msg == null) return;
    final part = TextPart(
      id: partId,
      messageId: asstId,
      sessionId: state.threadId,
      text: text,
    );
    final next = Map<String, Message>.from(state.messages);
    next[asstId] = msg.withPartUpsert(part);
    state = state.copyWith(messages: next);
  }

  void _upsertReasoningPart({required String partId, required String text}) {
    final asstId = _activeAssistantMessageId;
    if (asstId == null) return;
    final msg = state.messages[asstId];
    if (msg == null) return;
    final part = ReasoningPart(
      id: partId,
      messageId: asstId,
      sessionId: state.threadId,
      text: text,
    );
    final next = Map<String, Message>.from(state.messages);
    next[asstId] = msg.withPartUpsert(part);
    state = state.copyWith(messages: next);
  }

  void _upsertToolPart({
    required String partId,
    required String tool,
    required ToolStatus status,
    required Map<String, dynamic>? input,
    required Object? output,
    required String? error,
  }) {
    final asstId = _activeAssistantMessageId;
    if (asstId == null) return;
    final msg = state.messages[asstId];
    if (msg == null) return;
    final part = ToolPart(
      id: partId,
      messageId: asstId,
      sessionId: state.threadId,
      tool: tool,
      status: status,
      input: input,
      output: output,
      error: error,
    );
    final next = Map<String, Message>.from(state.messages);
    next[asstId] = msg.withPartUpsert(part);
    state = state.copyWith(messages: next);
  }

  void _finalize({String? error}) {
    final asstId = _activeAssistantMessageId;
    if (asstId != null) {
      final msg = state.messages[asstId];
      if (msg != null) {
        final next = Map<String, Message>.from(state.messages);
        next[asstId] = msg.copyWith(
          status: error == null ? MessageStatus.completed : MessageStatus.error,
          completedAtMs: DateTime.now().millisecondsSinceEpoch,
        );
        state = state.copyWith(
          messages: next,
          isStreaming: false,
          error: error,
        );
      } else {
        state = state.copyWith(isStreaming: false, error: error);
      }
    } else {
      state = state.copyWith(isStreaming: false, error: error);
    }
    _activeAssistantMessageId = null;
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
