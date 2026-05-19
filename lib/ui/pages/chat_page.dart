import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/sse_stream.dart';
import '../../models/message.dart';
import '../../state/providers.dart';
import '../../state/settings_store.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/connection_chip.dart';
import '../widgets/message_bubble.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    super.key,
    required this.sessionId,
    required this.title,
    this.directory,
  });

  final String sessionId;
  final String title;

  /// The directory the session is pinned to. Forwarded as `?directory=` on
  /// every message send / abort so the OpenCode server runs the agent in the
  /// right working dir even when other sessions in other dirs are active.
  final String? directory;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();

  /// Pending attachments to send with the next message.
  final List<Attachment> _attachments = [];

  /// Tracks the previously-rendered message count so we can detect "list
  /// grew" without comparing message lists deep-equally on every frame.
  int _lastMessageCount = 0;

  /// Tracks the keyboard inset across builds so we know when the keyboard
  /// just rose / fell and can respond by scrolling.
  double _lastBottomInset = 0;

  @override
  void initState() {
    super.initState();
    _inputFocus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _inputFocus.removeListener(_onFocusChange);
    _input.dispose();
    _scroll.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  /// When the input field gains focus, force-scroll the latest message above
  /// the about-to-appear keyboard. Mirrors WeChat / iMessage UX.
  void _onFocusChange() {
    if (_inputFocus.hasFocus) {
      _scrollToBottom(force: true);
    }
  }

  /// Schedule a scroll-to-bottom on the next two frames.
  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final pos = _scroll.position;
        if (!force) {
          if (pos.maxScrollExtent - pos.pixels >= 120) return;
        }
        _scroll.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      });
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;

    final settings = ref.read(settingsControllerProvider);
    final client = ref.read(opencodeClientProvider);
    final attachments = List<Attachment>.from(_attachments);

    _input.clear();
    setState(() => _attachments.clear());

    try {
      await client.sendMessageWithAttachments(
        sessionId: widget.sessionId,
        text: text,
        providerId: settings.providerId,
        modelId: settings.modelId,
        attachments: attachments,
        directory: widget.directory,
      );
      _scrollToBottom(force: true);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Send failed: $err')));
    }
  }

  Future<void> _pickAttachment() async {
    final result = await showAttachmentPicker(context);
    if (result != null && result.isNotEmpty) {
      setState(() => _attachments.addAll(result));
    }
  }

  Future<void> _abort() async {
    final client = ref.read(opencodeClientProvider);
    try {
      await client.abortSession(widget.sessionId, directory: widget.directory);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Abort failed: $err')));
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatControllerProvider(widget.sessionId));
    final messages = state.orderedMessages.toList(growable: false);

    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardJustRose = inset > _lastBottomInset && inset > 80;
    final listGrew = messages.length > _lastMessageCount;
    _lastBottomInset = inset;
    _lastMessageCount = messages.length;
    if (listGrew) _scrollToBottom();
    if (keyboardJustRose) _scrollToBottom(force: true);

    // Auto-scroll when content changes (agent streaming long messages).
    // We always try to scroll; _scrollToBottom respects the "user scrolled up" guard.
    if (messages.isNotEmpty) _scrollToBottom();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(widget.title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                ConnectionChip(state: state.connection),
                const Spacer(),
                if (state.error != null)
                  Flexible(
                    child: Text(
                      state.error!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? _EmptyHint(connected: state.connection == SseState.connected)
                : ListView.builder(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (_, i) =>
                        MessageBubble(message: messages[i]),
                  ),
          ),
          // Attachment preview strip
          if (_attachments.isNotEmpty)
            AttachmentPreviewStrip(
              attachments: _attachments,
              onRemove: _removeAttachment,
            ),
          _InputBar(
            controller: _input,
            focusNode: _inputFocus,
            onSend: _send,
            onAbort: _abort,
            onAttach: _pickAttachment,
            isStreaming:
                messages.any((m) => m.status == MessageStatus.running),
            hasAttachments: _attachments.isNotEmpty,
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.connected});
  final bool connected;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.chat_bubble_outline, size: 48),
              const SizedBox(height: 12),
              Text(
                connected ? 'Ready. Send a prompt below.' : 'Connecting…',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ],
          ),
        ),
      );
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.onSend,
    required this.onAbort,
    required this.onAttach,
    required this.isStreaming,
    required this.hasAttachments,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSend;
  final Future<void> Function() onAbort;
  final VoidCallback onAttach;
  final bool isStreaming;
  final bool hasAttachments;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Attachment button
              IconButton(
                icon: Icon(
                  Icons.attach_file,
                  color: hasAttachments
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                onPressed: onAttach,
                tooltip: 'Add attachment',
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 6,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: isStreaming ? 'Streaming…' : 'Send a message',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHigh,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isStreaming)
                IconButton.filled(
                  icon: const Icon(Icons.stop),
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: onAbort,
                  tooltip: 'Stop agent',
                )
              else
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  onPressed: onSend,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
