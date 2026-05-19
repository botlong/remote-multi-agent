/// Chat page driven by the Codex backend.
///
/// Reuses the existing message-rendering widgets so attachments, markdown,
/// code highlighting, copy buttons, image viewer all keep working — only the
/// transport underneath has changed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/message.dart';
import '../../state/codex_providers.dart';
import '../../state/codex_thread_store.dart';
import '../../state/settings_store.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/message_bubble.dart';

class CodexChatPage extends ConsumerStatefulWidget {
  const CodexChatPage({super.key, required this.localKey});

  final String localKey;

  @override
  ConsumerState<CodexChatPage> createState() => _CodexChatPageState();
}

class _CodexChatPageState extends ConsumerState<CodexChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _inputFocus = FocusNode();
  final List<Attachment> _attachments = [];

  int _lastMessageCount = 0;
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

  void _onFocusChange() {
    if (_inputFocus.hasFocus) _scrollToBottom(force: true);
  }

  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final pos = _scroll.position;
        if (!force && pos.maxScrollExtent - pos.pixels >= 120) return;
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
    final ctrl = ref.read(codexChatProvider(widget.localKey).notifier);
    final state = ref.read(codexChatProvider(widget.localKey));

    // Codex CLI doesn't accept attachments via the same prompt yet — for now,
    // include filenames inline so the agent can read them via shell tools.
    var prompt = text;
    if (_attachments.isNotEmpty) {
      final names =
          _attachments.map((a) => '- ${a.fileName} (${a.mimeType})').join('\n');
      prompt = '$prompt\n\nAttachments available in working directory:\n$names';
    }

    _input.clear();
    setState(() => _attachments.clear());

    try {
      await ctrl.send(
        prompt: prompt,
        directory: state.directory,
        model: settings.modelId,
      );
      // Persist new threadId once codex emitted thread.started.
      final tid = ref.read(codexChatProvider(widget.localKey)).threadId;
      if (tid.isNotEmpty) {
        await ref
            .read(codexThreadListProvider.notifier)
            .updateThreadId(widget.localKey, tid);
      }
      await ref.read(codexThreadListProvider.notifier).touch(widget.localKey);
      _scrollToBottom(force: true);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Send failed: $err')));
    }
  }

  Future<void> _abort() async {
    try {
      await ref.read(codexChatProvider(widget.localKey).notifier).abort();
    } catch (_) {/* ignore */}
  }

  Future<void> _pickAttachment() async {
    final result = await showAttachmentPicker(context);
    if (result != null && result.isNotEmpty) {
      setState(() => _attachments.addAll(result));
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(codexChatProvider(widget.localKey));
    final messages = state.orderedMessages.toList(growable: false);

    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardJustRose = inset > _lastBottomInset && inset > 80;
    final listGrew = messages.length > _lastMessageCount;
    _lastBottomInset = inset;
    _lastMessageCount = messages.length;
    if (listGrew) _scrollToBottom();
    if (keyboardJustRose) _scrollToBottom(force: true);
    if (messages.isNotEmpty) _scrollToBottom();

    final threadMatches = ref
        .watch(codexThreadListProvider)
        .items
        .where((t) => t.localKey == widget.localKey);
    final thread = threadMatches.isEmpty ? null : threadMatches.first;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(thread?.title ?? 'Codex'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                _StatusChip(streaming: state.isStreaming),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.directory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (state.error != null)
                  Tooltip(
                    message: state.error!,
                    child: Icon(
                      Icons.error_outline,
                      size: 16,
                      color: Theme.of(context).colorScheme.error,
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
                ? const _EmptyHint()
                : ListView.builder(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => MessageBubble(message: messages[i]),
                  ),
          ),
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
            isStreaming: state.isStreaming ||
                messages.any((m) => m.status == MessageStatus.running),
            hasAttachments: _attachments.isNotEmpty,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.streaming});
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = streaming ? theme.colorScheme.primary : Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            streaming ? 'Running' : 'Idle',
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.terminal, size: 48),
              const SizedBox(height: 12),
              Text(
                'Send a prompt to start a Codex turn.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
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
                    hintText: isStreaming ? 'Streaming…' : 'Send a prompt',
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
