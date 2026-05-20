import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/gateway_providers.dart';
import '../widgets/agent_badge.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/message_bubble.dart';
import '../widgets/session_status_chip.dart';
import 'diff_page.dart';
import 'gateway_ui_adapters.dart';

const _scrollAwayThreshold = 200.0;

class GatewayChatPage extends ConsumerStatefulWidget {
  const GatewayChatPage({
    super.key,
    required this.session,
    required this.project,
    this.agent,
  });

  final GatewaySessionView session;
  final GatewayProjectView project;
  final GatewayAgentView? agent;

  @override
  ConsumerState<GatewayChatPage> createState() => _GatewayChatPageState();
}

class _GatewayChatPageState extends ConsumerState<GatewayChatPage>
    with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _showCommands = false;
  bool _isScrolledAway = false;
  int _lastMessageCount = 0;
  bool _hasNewWhileAway = false;
  final List<Attachment> _attachments = [];

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _input.removeListener(_onInputChanged);
    _scroll.removeListener(_onScroll);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    final away = _scroll.hasClients && _scroll.offset > _scrollAwayThreshold;
    if (away != _isScrolledAway) {
      setState(() {
        _isScrolledAway = away;
        if (!away) _hasNewWhileAway = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // OS may have killed the SSE socket while backgrounded; refresh it.
      ref
          .read(gatewayChatProvider(widget.session.id).notifier)
          .reconnect();
    }
  }

  void _onInputChanged() {
    final text = _input.text;
    final shouldShow = text.startsWith('/') || text.startsWith(r'$');
    if (shouldShow != _showCommands) {
      setState(() => _showCommands = shouldShow);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(gatewayChatProvider(widget.session.id));
    final messages = chatState.orderedMessages.toList(growable: false).reversed.toList();
    final status = _statusFromState(chatState);
    final agent =
        widget.agent ?? _agentFromCatalog(ref, widget.session.agentId);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.difference_outlined),
            tooltip: 'View diff',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => DiffPage(sessionId: widget.session.id),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export',
            onSelected: (v) => _export(v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'markdown', child: Text('Copy as Markdown')),
              PopupMenuItem(value: 'json', child: Text('Copy as JSON')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    AgentBadge(
                      agentId: widget.session.agentId,
                      label: agent?.displayName,
                      compact: true,
                    ),
                    const SizedBox(width: 6),
                    SessionStatusChip(status: status, compact: true),
                    if (widget.session.modelId?.isNotEmpty == true) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.session.modelId!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                                fontSize: 10,
                              ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Builder(
        builder: (context) {
          // Track new messages arriving while scrolled away
          if (messages.length > _lastMessageCount && _isScrolledAway) {
            _hasNewWhileAway = true;
          }
          _lastMessageCount = messages.length;

          return Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => _focus.unfocus(),
                  behavior: HitTestBehavior.translucent,
                  child: messages.isEmpty
                      ? const _EmptyChat()
                      : ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                          itemCount: messages.length,
                          itemBuilder: (_, index) {
                            final msg = messages[index];
                            return MessageBubble(
                              message: msg,
                              onDelete: () => _deleteMessage(msg.id),
                              onResend: (text) => _resend(text),
                              onEditResend: (text) => _editResend(text),
                              onQuote: (text) => _quote(text),
                            );
                          },
                        ),
                ),
                if (_isScrolledAway || _hasNewWhileAway)
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _ScrollToBottomButton(
                        hasNew: _hasNewWhileAway,
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _scrollToBottom();
                          setState(() {
                            _isScrolledAway = false;
                            _hasNewWhileAway = false;
                          });
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_showCommands)
            FutureBuilder<List<GatewayCommandView>>(
              future: _commandsFuture(agent),
              builder: (context, snapshot) {
                final commands = _filteredCommands(snapshot.data ?? const []);
                if (snapshot.connectionState == ConnectionState.waiting &&
                    commands.isEmpty) {
                  return const SizedBox.shrink();
                }
                if (commands.isEmpty) return const SizedBox.shrink();
                return _CommandSuggestions(
                  commands: commands,
                  onSelected: (command) {
                    _input.text = '${command.name} ';
                    _input.selection =
                        TextSelection.collapsed(offset: _input.text.length);
                    _focus.requestFocus();
                  },
                  maxHeight: 280,
                );
              },
            ),
          if (_attachments.isNotEmpty)
            AttachmentPreviewStrip(
              attachments: _attachments,
              onRemove: (i) => setState(() => _attachments.removeAt(i)),
            ),
          if (chatState.usage != null) _UsageBar(usage: chatState.usage!),
          _InputBar(
            controller: _input,
            focusNode: _focus,
            running: status == 'running',
            onSend: _send,
            onAbort: _abort,
            onAttach: _pickAttachments,
          ),
        ],
      );
        },
      ),
    );
  }


  String _statusFromState(dynamic state) {
    if (state.isStreaming == true) return 'running';
    final session = state.session;
    if (session != null) {
      final status = session.status.wireName as String;
      if (status != 'unknown') return status;
    }
    return widget.session.status;
  }

  List<GatewayCommandView> _filteredCommands(
    List<GatewayCommandView> commands,
  ) {
    final query = _input.text.trim();
    if (query == '/' || query == r'$') return commands;
    return commands.where((c) => c.name.startsWith(query)).toList();
  }

  Future<List<GatewayCommandView>> _commandsFuture(
    GatewayAgentView? agent,
  ) async {
    final local = agent?.commands ?? const <GatewayCommandView>[];
    if (local.isNotEmpty) return local;
    if (agent == null) return const <GatewayCommandView>[];
    final notifier = ref.read(agentCatalogProvider.notifier);
    final commands = await notifier.commandsFor(agent.id);
    final fromGateway = commands
        .map(
          (command) => GatewayCommandView(
            name: command.name,
            description: command.description,
          ),
        )
        .toList(growable: false);
    return fromGateway.isNotEmpty ? fromGateway : _fallbackCommands(agent.id);
  }

  Future<void> _pickAttachments() async {
    final picked = await showAttachmentPicker(context);
    if (picked != null && picked.isNotEmpty) {
      setState(() => _attachments.addAll(picked));
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    HapticFeedback.lightImpact();
    _input.clear();
    final pendingAttachments = List<Attachment>.from(_attachments);
    setState(() => _attachments.clear());
    try {
      final notifier =
          ref.read(gatewayChatProvider(widget.session.id).notifier);
      if (text.startsWith('/')) {
        await notifier.sendSlashCommand(text);
      } else {
        await notifier.sendMessage(
          text,
          attachments: pendingAttachments.isEmpty
              ? const []
              : pendingAttachments.map((a) => a.toPartJson()).toList(),
        );
      }
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $err')),
      );
    }
  }

  Future<void> _abort() async {
    HapticFeedback.mediumImpact();
    final notifier = ref.read(gatewayChatProvider(widget.session.id).notifier);
    await notifier.abort();
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      final notifier =
          ref.read(gatewayChatProvider(widget.session.id).notifier);
      await notifier.deleteMessage(messageId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _export(String format) async {
    try {
      final client = ref.read(gatewayClientProvider);
      final content =
          await client.exportSession(widget.session.id, format: format);
      await Clipboard.setData(ClipboardData(text: content));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            format == 'json'
                ? 'JSON copied to clipboard'
                : 'Markdown copied to clipboard',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    // reverse: true means offset 0 = bottom
    if (_scroll.offset > 0) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _resend(String text) {
    _input.text = text;
    _send();
  }

  void _editResend(String text) {
    _input.text = text;
    _input.selection = TextSelection.collapsed(offset: text.length);
    _focus.requestFocus();
  }

  void _quote(String text) {
    final quoted = text.split('\n').map((l) => '> $l').join('\n');
    _input.text = '$quoted\n\n';
    _input.selection = TextSelection.collapsed(offset: _input.text.length);
    _focus.requestFocus();
  }
}

class _CommandSuggestions extends StatelessWidget {
  const _CommandSuggestions({
    required this.commands,
    required this.onSelected,
    this.maxHeight = 280,
  });

  final List<GatewayCommandView> commands;
  final ValueChanged<GatewayCommandView> onSelected;
  final double maxHeight;

  IconData _iconFor(String name) {
    if (name.startsWith(r'$')) return Icons.terminal;
    return switch (name) {
      '/model' || '/models' || '/fast' => Icons.psychology_outlined,
      '/compact' || '/summarize' => Icons.compress,
      '/clear' || '/new' => Icons.cleaning_services_outlined,
      '/help' => Icons.help_outline,
      '/status' => Icons.info_outline,
      '/mcp' => Icons.settings_ethernet,
      '/permissions' => Icons.security,
      '/plan' || '/goal' => Icons.flag_outlined,
      '/feedback' || '/review' || '/bug' => Icons.rate_review_outlined,
      '/fork' || '/side' => Icons.call_split,
      '/init' => Icons.play_arrow_outlined,
      '/stop' || '/exit' || '/quit' || '/q' => Icons.stop_outlined,
      '/undo' => Icons.undo,
      '/redo' => Icons.redo,
      '/diff' || '/copy' => Icons.content_copy_outlined,
      '/memories' || '/memory' => Icons.bookmark_outline,
      '/personality' => Icons.face_outlined,
      '/login' || '/logout' => Icons.login,
      '/agent' || '/agents' => Icons.smart_toy_outlined,
      '/plugins' || '/hooks' || '/apps' => Icons.extension_outlined,
      _ => Icons.keyboard_command_key,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          shrinkWrap: true,
          itemCount: commands.length,
          separatorBuilder: (_, __) => const SizedBox(height: 2),
          itemBuilder: (_, index) {
            final command = commands[index];
            return Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => onSelected(command),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          _iconFor(command.name),
                          size: 16,
                          color: scheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        command.name,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (command.description.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            command.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.running,
    required this.onSend,
    required this.onAbort,
    this.onAttach,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool running;
  final Future<void> Function() onSend;
  final Future<void> Function() onAbort;
  final VoidCallback? onAttach;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (onAttach != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4, right: 4),
                  child: IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: scheme.onSurfaceVariant,
                    ),
                    onPressed: onAttach,
                    tooltip: 'Add attachment',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 6,
                  decoration: InputDecoration(
                    hintText: running
                        ? 'Send guidance to running agent...'
                        : 'Message, /command, or \$shell',
                    filled: true,
                    fillColor: scheme.surfaceContainerHigh.withValues(alpha: 0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide(
                        color: scheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (running) ...[
                _SendButton(onPressed: onSend),
                const SizedBox(width: 6),
                _StopButton(onPressed: onAbort),
              ] else
                _SendButton(onPressed: onSend),
            ],
          ),
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  const _SendButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: scheme.primary,
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: const Icon(Icons.arrow_upward_rounded, size: 18),
        color: scheme.onPrimary,
        onPressed: onPressed,
        tooltip: 'Send',
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(Icons.stop_rounded, size: 20, color: scheme.error),
        onPressed: onPressed,
        tooltip: 'Stop agent',
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bubble_chart_outlined,
              size: 44,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 14),
            Text(
              'New conversation',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({required this.usage});
  final TokenUsage usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ratio = usage.ratio.clamp(0.0, 1.0);
    final isHigh = ratio > 0.8;
    final color = isHigh ? scheme.error : scheme.primary;
    final totalK = (usage.totalTokens / 1000).toStringAsFixed(1);
    final limitK = (TokenUsage.contextLimit / 1000).toStringAsFixed(0);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.data_usage, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                '${totalK}k / ${limitK}k tokens',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (isHigh)
                Text(
                  'Consider /compact',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 3,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }
}

GatewayAgentView? _agentFromCatalog(WidgetRef ref, String agentId) {
  final agents = readAgents(ref.watch(agentCatalogProvider));
  for (final agent in agents) {
    if (agent.id == agentId) return agent;
  }
  return null;
}

List<GatewayCommandView> _fallbackCommands(String agentId) {
  return switch (agentId) {
    'codex' => const [
        GatewayCommandView(name: '/model', description: 'Switch model'),
        GatewayCommandView(name: '/fast', description: 'Switch to fast model'),
        GatewayCommandView(name: '/plan', description: 'Plan a goal'),
        GatewayCommandView(name: '/compact', description: 'Compress context'),
        GatewayCommandView(name: '/status', description: 'Show status'),
        GatewayCommandView(name: '/permissions', description: 'Manage permissions'),
        GatewayCommandView(name: r'$', description: 'Run a shell command'),
      ],
    'claude-code' => const [
        GatewayCommandView(name: '/model', description: 'Switch model'),
        GatewayCommandView(name: '/compact', description: 'Compress context'),
        GatewayCommandView(name: '/status', description: 'Show status'),
        GatewayCommandView(name: '/help', description: 'Show help'),
        GatewayCommandView(name: '/clear', description: 'Clear conversation'),
        GatewayCommandView(name: '/permissions', description: 'Manage permissions'),
      ],
    'opencode' => const [
        GatewayCommandView(name: '/models', description: 'Show or switch models'),
        GatewayCommandView(name: '/compact', description: 'Compress context'),
        GatewayCommandView(name: '/help', description: 'Show help'),
        GatewayCommandView(name: '/new', description: 'Start a new session'),
        GatewayCommandView(name: '/undo', description: 'Undo last change'),
        GatewayCommandView(name: '/redo', description: 'Redo last change'),
      ],
    _ => const <GatewayCommandView>[],
  };
}

class _ScrollToBottomButton extends StatelessWidget {
  const _ScrollToBottomButton({
    required this.hasNew,
    required this.onPressed,
  });

  final bool hasNew;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(20),
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.2),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.keyboard_arrow_down,
                size: 18,
                color: scheme.onSurface,
              ),
              if (hasNew) ...[
                const SizedBox(width: 4),
                Text(
                  'New',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
