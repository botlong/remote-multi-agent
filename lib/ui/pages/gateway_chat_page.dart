import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/gateway_providers.dart';
import '../widgets/agent_badge.dart';
import '../widgets/message_bubble.dart';
import '../widgets/session_status_chip.dart';
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
    final shouldShow = _input.text.startsWith('/');
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
                    itemBuilder: (_, index) =>
                        MessageBubble(message: messages[index]),
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
                );
              },
            ),
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
    if (query == '/') return commands;
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
  });

  final List<GatewayCommandView> commands;
  final ValueChanged<GatewayCommandView> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SizedBox(
          height: 112,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            scrollDirection: Axis.horizontal,
            itemCount: commands.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, index) {
              final command = commands[index];
              return SizedBox(
                width: 220,
                child: ActionChip(
                  avatar: const Icon(Icons.keyboard_command_key, size: 16),
                  label: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          command.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (command.description.isNotEmpty)
                          Text(
                            command.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
                          ),
                      ],
                    ),
                  ),
                  onPressed: () => onSelected(command),
                ),
              );
            },
          ),
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
                    hintText: 'Message or /command',
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
              IconButton.filled(
                icon: Icon(running ? Icons.stop : Icons.send),
                tooltip: running ? 'Stop agent' : 'Send',
                onPressed: running ? onAbort : onSend,
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

GatewayAgentView? _agentFromCatalog(WidgetRef ref, String agentId) {
  final agents = readAgents(ref.watch(agentCatalogProvider));
  for (final agent in agents) {
    if (agent.id == agentId) return agent;
  }
  return null;
}

List<GatewayCommandView> _fallbackCommands(String agentId) {
  final commands = switch (agentId) {
    'codex' => const [
        '/permissions',
        '/model',
        '/fast',
        '/plan',
        '/status',
        '/stop',
      ],
    'claude-code' => const [
        '/help',
        '/clear',
        '/compact',
        '/model',
        '/permissions',
        '/status',
      ],
    'opencode' => const [
        '/help',
        '/new',
        '/models',
        '/compact',
        '/undo',
        '/redo',
      ],
    _ => const <String>[],
  };
  return commands
      .map(
        (command) => GatewayCommandView(
          name: command,
          description: '',
        ),
      )
      .toList(growable: false);
}
