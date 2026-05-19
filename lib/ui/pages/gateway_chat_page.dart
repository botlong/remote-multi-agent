import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/gateway_providers.dart';
import '../widgets/agent_badge.dart';
import '../widgets/message_bubble.dart';
import '../widgets/session_status_chip.dart';
import 'diff_page.dart';
import 'gateway_ui_adapters.dart';

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

class _GatewayChatPageState extends ConsumerState<GatewayChatPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  bool _showCommands = false;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
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
    final messages = chatState.orderedMessages.toList(growable: false);
    final status = _statusFromState(chatState);
    final agent =
        widget.agent ?? _agentFromCatalog(ref, widget.session.agentId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

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
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    AgentBadge(
                      agentId: widget.session.agentId,
                      label: agent?.displayName,
                      compact: true,
                    ),
                    const SizedBox(width: 8),
                    SessionStatusChip(status: status, compact: true),
                    if (widget.session.modelId?.isNotEmpty == true) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.session.modelId!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                    ] else
                      const Spacer(),
                  ],
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.project.directory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                ? const _EmptyChat()
                : ListView.builder(
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    itemCount: messages.length,
                    itemBuilder: (_, index) {
                      final msg = messages[index];
                      return MessageBubble(
                        message: msg,
                        onDelete: () => _deleteMessage(msg.id),
                      );
                    },
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
          if (chatState.usage != null) _UsageBar(usage: chatState.usage!),
          _InputBar(
            controller: _input,
            focusNode: _focus,
            running: status == 'running',
            onSend: _send,
            onAbort: _abort,
          ),
        ],
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

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    try {
      final notifier =
          ref.read(gatewayChatProvider(widget.session.id).notifier);
      if (text.startsWith('/')) {
        await notifier.sendSlashCommand(text);
      } else {
        await notifier.sendMessage(text);
      }
      _scrollToBottom();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Send failed: $err')),
      );
    }
  }

  Future<void> _abort() async {
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

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels > 160) return;
    _scroll.animateTo(
      position.maxScrollExtent,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
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
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 4),
          shrinkWrap: true,
          itemCount: commands.length,
          itemBuilder: (_, index) {
            final command = commands[index];
            return InkWell(
              onTap: () => onSelected(command),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _iconFor(command.name),
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      command.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (command.description.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          command.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool running;
  final Future<void> Function() onSend;
  final Future<void> Function() onAbort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
                    fillColor: theme.colorScheme.surfaceContainerHigh,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (running) ...[
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  tooltip: 'Send guidance',
                  onPressed: onSend,
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  icon: const Icon(Icons.stop),
                  tooltip: 'Stop agent',
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                  ),
                  onPressed: onAbort,
                ),
              ] else
                IconButton.filled(
                  icon: const Icon(Icons.send),
                  tooltip: 'Send',
                  onPressed: onSend,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Start this agent session.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
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
    final ratio = usage.ratio.clamp(0.0, 1.0);
    final isHigh = ratio > 0.8;
    final color = isHigh ? theme.colorScheme.error : theme.colorScheme.primary;
    final totalK = (usage.totalTokens / 1000).toStringAsFixed(1);
    final limitK = (TokenUsage.contextLimit / 1000).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.data_usage, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                '${totalK}k / ${limitK}k tokens',
                style: theme.textTheme.labelSmall?.copyWith(color: color),
              ),
              const Spacer(),
              if (isHigh)
                Text(
                  'Consider /compact',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 3,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
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
