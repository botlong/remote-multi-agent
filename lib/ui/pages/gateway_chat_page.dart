import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/message.dart';
import '../../models/part.dart';
import '../../state/gateway_providers.dart';
import '../../state/notification_service.dart';
import '../../state/settings_store.dart';
import '../widgets/agent_activity_bar.dart';
import '../widgets/agent_badge.dart';
import '../widgets/attachment_picker.dart';
import '../widgets/directory_picker.dart';
import '../widgets/message_bubble.dart';
import '../widgets/model_picker.dart';
import '../widgets/session_status_chip.dart';
import 'diff_page.dart';
import 'gateway_ui_adapters.dart';
import 'terminal_page.dart';

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
  bool _showFileHints = false;
  bool _isScrolledAway = false;
  int _lastMessageCount = 0;
  bool _hasNewWhileAway = false;
  final List<Attachment> _attachments = [];
  String? _activeProfileName;

  @override
  void initState() {
    super.initState();
    _input.addListener(_onInputChanged);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    // Mark this session as active to suppress notifications
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setActiveSessionId(widget.session.id);
      ref.read(activeSessionIdProvider.notifier).state = widget.session.id;
      // Persist last-used session/project for restore on next launch.
      ref.read(settingsControllerProvider.notifier).setLastUsed(
            sessionId: widget.session.id,
            projectId: widget.project.id,
          );
      // Fetch active profile name for display in AppBar.
      final client = ref.read(gatewayClientProvider);
      client.getActiveProfile().then((profile) {
        if (mounted && profile != null) {
          setState(() => _activeProfileName = profile['name'] as String?);
        }
      }).catchError((_) {});
    });
  }

  @override
  void dispose() {
    // Clear active session when leaving
    setActiveSessionId(null);
    ref.read(activeSessionIdProvider.notifier).state = null;
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
    final hasAt = text.contains('@') && !text.startsWith('/') && !text.startsWith(r'$');
    if (hasAt != _showFileHints) {
      setState(() => _showFileHints = hasAt);
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
            icon: const Icon(Icons.terminal),
            tooltip: 'Terminal',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => TerminalPage(sessionId: widget.session.id),
              ),
            ),
          ),
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
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onSelected: (v) {
              if (v == 'markdown' || v == 'json') {
                _export(v);
              } else if (v == 'handoff') {
                _showHandoffDialog();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'handoff', child: Text('Hand off to agent...')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'markdown', child: Text('Copy as Markdown')),
              const PopupMenuItem(value: 'json', child: Text('Copy as JSON')),
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
                    if (_activeProfileName != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _activeProfileName!,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: Theme.of(context).colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
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
          if (chatState.connection == GatewayChatConnectionState.disconnected)
            const _DisconnectedBanner()
          else if (chatState.connection == GatewayChatConnectionState.connecting)
            const _ConnectingBanner(),
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
          if (_showFileHints)
            _FileHintBar(directory: widget.session.directory),
          if (_attachments.isNotEmpty)
            AttachmentPreviewStrip(
              attachments: _attachments,
              onRemove: (i) => setState(() => _attachments.removeAt(i)),
            ),
          if (chatState.activeTool != null)
            AgentActivityBar(activeTool: chatState.activeTool!),
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
    final query = _input.text.trim().toLowerCase();
    if (query == '/' || query == r'$') return commands;
    return commands.where((c) => c.name.toLowerCase().contains(query)).toList();
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

    // For slash commands, try interception BEFORE clearing input
    if (text.startsWith('/')) {
      if (_tryInterceptCommand(text)) {
        _input.clear();
        setState(() => _attachments.clear());
        return;
      }
    }

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

  // ─── Command Interception System ───────────────────────────────────────

  /// Passthrough commands that should always be sent directly to the gateway.
  static const _passthroughCommands = <String>{
    '/plan', '/goal', '/personality', '/raw', '/memory', '/mcp', '/config',
    '/doctor', '/agents', '/login', '/logout', '/bug', '/feedback',
    '/experimental', '/debug-config', '/plugins', '/hooks', '/apps',
    '/agent', '/mention',
  };

  /// Confirm commands that show a confirmation dialog before sending.
  static const _confirmCommands = <String, String>{
    '/compact': 'Compact the conversation context?',
    '/clear': 'Clear the conversation history?',
    '/undo': 'Undo the last change?',
    '/redo': 'Redo the last undone change?',
    '/fork': 'Fork this session into a new branch?',
    '/side': 'Start a side conversation?',
    '/init': 'Initialize the project?',
    '/unshare': 'Unshare this session?',
    '/review': 'Request a code review?',
  };

  /// Returns true if the command was intercepted (handled locally),
  /// false if it should pass through to the gateway.
  bool _tryInterceptCommand(String text) {
    final parts = text.split(RegExp(r'\s+'));
    final commandName = parts.first.toLowerCase();
    final agentId = widget.session.agentId;

    // $ prefix commands always pass through
    if (text.startsWith(r'$')) return false;

    // Passthrough commands
    if (_passthroughCommands.contains(commandName)) return false;

    // Picker commands
    switch (commandName) {
      case '/model' || '/models':
        _handleModelCommand();
        return true;
      case '/permissions':
        _handlePermissionsCommand();
        return true;
      case '/export':
        _handleExportCommand();
        return true;
      case '/add-dir':
        _handleAddDirCommand();
        return true;
      case '/sessions':
        _handleSessionsCommand();
        return true;
    }

    // Confirm commands
    if (commandName == '/new') {
      _handleNewCommand();
      return true;
    }
    if (_confirmCommands.containsKey(commandName)) {
      _handleConfirmCommand(commandName, _confirmCommands[commandName]!);
      return true;
    }

    // Action commands
    switch (commandName) {
      case '/status':
        _handleStatusCommand();
        return true;
      case '/diff':
        _handleDiffCommand();
        return true;
      case '/copy':
        _handleCopyCommand();
        return true;
      case '/fast':
        _handleFastCommand();
        return true;
      case '/stop':
        _handleStopCommand();
        return true;
      case '/exit' || '/quit' || '/q':
        _handleExitCommand();
        return true;
      case '/cost':
        _handleCostCommand();
        return true;
      case '/help':
        _handleNotAvailableCommand(commandName);
        return true;
    }

    // Agent-specific not-available commands
    if (agentId == 'codex' && commandName == '/summarize') {
      // Codex uses /compact instead
      _handleConfirmCommand('/compact', 'Compact the conversation context?');
      return true;
    }

    // Not intercepted — pass through to gateway
    return false;
  }

  // ─── Picker Command Handlers ─────────────────────────────────────────

  Future<void> _handleModelCommand() async {
    final agentId = widget.session.agentId;
    final notifier = ref.read(agentCatalogProvider.notifier);

    List<ModelChoice> choices;
    try {
      final models = await notifier.modelsFor(agentId);
      choices = models
          .map(
            (m) => (
              providerId: _providerOf(m.id, agentId),
              modelId: m.id,
              label: m.displayName.trim().isEmpty ? m.id : m.displayName,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      // Fallback to agent catalog models
      final catalog = ref.read(agentCatalogProvider);
      final agents = readAgents(catalog);
      final agent = agents.where((a) => a.id == agentId).firstOrNull;
      choices = (agent?.models ?? <GatewayModelView>[])
          .map(
            (m) => (
              providerId: _providerOf(m.id, agentId),
              modelId: m.id,
              label: m.displayName.trim().isEmpty ? m.id : m.displayName,
            ),
          )
          .toList(growable: false);
    }

    if (!mounted) return;
    if (choices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No models available for this agent')),
      );
      return;
    }

    final currentModelId = widget.session.modelId;
    final currentChoice = currentModelId != null
        ? choices.where((c) => c.modelId == currentModelId).firstOrNull
        : null;

    final picked = await showModelPicker(
      context,
      models: choices,
      selected: currentChoice,
    );
    if (picked == null || !mounted) return;

    final chatNotifier =
        ref.read(gatewayChatProvider(widget.session.id).notifier);
    await chatNotifier.sendSlashCommand('/model ${picked.modelId}');
  }

  Future<void> _handlePermissionsCommand() async {
    final agentId = widget.session.agentId;
    final options = _permissionOptionsFor(agentId);

    if (!mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _PermissionPickerSheet(options: options),
    );
    if (selected == null || !mounted) return;

    final notifier =
        ref.read(gatewayChatProvider(widget.session.id).notifier);
    await notifier.sendSlashCommand('/permissions $selected');
  }

  Future<void> _handleExportCommand() async {
    if (!mounted) return;
    final format = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Text(
                'Export conversation',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Markdown'),
              onTap: () => Navigator.pop(ctx, 'markdown'),
            ),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('JSON'),
              onTap: () => Navigator.pop(ctx, 'json'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
    if (format == null || !mounted) return;
    _export(format);
  }

  Future<void> _handleAddDirCommand() async {
    final settings = ref.read(settingsControllerProvider);
    if (!mounted) return;
    final path = await showDirectoryPicker(
      context,
      gatewayBaseUrl: settings.baseUrl,
      bearerToken: settings.bearerToken,
      initialPath: widget.project.directory,
    );
    if (path == null || !mounted) return;

    final notifier =
        ref.read(gatewayChatProvider(widget.session.id).notifier);
    await notifier.sendSlashCommand('/add-dir $path');
  }

  Future<void> _handleSessionsCommand() async {
    final projectId = widget.session.projectId;
    final sessionState =
        ref.read(gatewaySessionListProvider(projectId));
    final sessionViews = readSessions(sessionState);

    if (!mounted) return;
    if (sessionViews.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other sessions found')),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _SessionPickerSheet(
        sessions: sessionViews,
        currentSessionId: widget.session.id,
      ),
    );
    if (selected == null || !mounted) return;
    if (selected == widget.session.id) return;

    // Find the session and navigate to it
    final sessionView = sessionViews.firstWhere(
      (GatewaySessionView s) => s.id == selected,
    );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GatewayChatPage(
          session: sessionView,
          project: widget.project,
        ),
      ),
    );
  }

  // ─── Confirm Command Handlers ────────────────────────────────────────

  Future<void> _handleConfirmCommand(String command, String message) async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(command),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final notifier =
        ref.read(gatewayChatProvider(widget.session.id).notifier);
    await notifier.sendSlashCommand(command);
  }

  Future<void> _handleNewCommand() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('/new'),
        content: const Text('Start a new session with this agent?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final projectId = widget.session.projectId;
      final agentId = widget.session.agentId;
      final notifier =
          ref.read(gatewaySessionListProvider(projectId).notifier);
      final created = await notifier.createSession(agentId: agentId);
      if (!mounted) return;
      final session = readSession(created);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GatewayChatPage(
            session: session,
            project: widget.project,
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create session: $err')),
      );
    }
  }

  // ─── Action Command Handlers ─────────────────────────────────────────

  Future<void> _handleStatusCommand() async {
    final chatState = ref.read(gatewayChatProvider(widget.session.id));
    final agentId = widget.session.agentId;
    final agent = _agentFromCatalog(ref, agentId);
    final commands = await _commandsFuture(agent);

    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _StatusSheet(
        sessionId: widget.session.id,
        agentId: agentId,
        agentName: agent?.displayName ?? agentId,
        modelId: widget.session.modelId,
        usage: chatState.usage,
        connection: chatState.connection,
        commands: commands,
      ),
    );
  }

  void _handleDiffCommand() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DiffPage(sessionId: widget.session.id),
      ),
    );
  }

  void _handleCopyCommand() {
    final chatState = ref.read(gatewayChatProvider(widget.session.id));
    final messages = chatState.orderedMessages.toList();
    if (messages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages to copy')),
      );
      return;
    }
    final lastAssistant = messages.lastWhere(
      (m) => m.role == MessageRole.assistant,
      orElse: () => messages.last,
    );
    final text = lastAssistant.orderedParts
        .whereType<TextPart>()
        .map((p) => p.text)
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied last assistant message')),
    );
  }

  Future<void> _handleFastCommand() async {
    final notifier =
        ref.read(gatewayChatProvider(widget.session.id).notifier);
    await notifier.sendSlashCommand('/fast');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Switching to fast model...')),
    );
  }

  void _handleStopCommand() {
    _abort();
  }

  Future<void> _handleExitCommand() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Exit session'),
        content: const Text('End this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    Navigator.of(context).pop();
  }

  void _handleCostCommand() {
    final chatState = ref.read(gatewayChatProvider(widget.session.id));
    final usage = chatState.usage;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _CostSheet(usage: usage),
    );
  }

  void _handleNotAvailableCommand(String command) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$command is not available on mobile')),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────

  static String _providerOf(String modelId, String fallback) {
    final slash = modelId.indexOf('/');
    return slash > 0 ? modelId.substring(0, slash) : fallback;
  }

  static List<_PermOption> _permissionOptionsFor(String agentId) {
    return switch (agentId) {
      'claude-code' => const [
          _PermOption('acceptEdits', 'Accept Edits', 'Auto-accept file edits (default)'),
          _PermOption('auto', 'Auto', 'Auto-approve most actions'),
          _PermOption('plan', 'Plan', 'Plan mode - no code changes'),
          _PermOption('bypassPermissions', 'Bypass All', 'Skip all permission prompts (dangerous)'),
        ],
      'codex' => const [
          _PermOption('workspace-write', 'Write', 'Write to workspace (default)'),
          _PermOption('read-only', 'Read-only', 'Read workspace only'),
          _PermOption('danger-full-access', 'Full Access', 'Full disk access (dangerous)'),
        ],
      'opencode' => const [
          _PermOption('build', 'Build', 'Standard build mode (default)'),
          _PermOption('plan', 'Plan', 'Plan mode - read-only exploration'),
        ],
      _ => const [
          _PermOption('build', 'Build', 'Standard build mode'),
          _PermOption('plan', 'Plan', 'Plan mode - no code changes'),
        ],
    };
  }

  // ─── End Command Interception System ─────────────────────────────────

  Future<void> _showHandoffDialog() async {
    final agents = ref.read(agentCatalogProvider).agents;
    final currentAgentId = widget.session.agentId;
    final otherAgents =
        agents.where((a) => a.id != currentAgentId).toList(growable: false);
    if (otherAgents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other agents available')),
      );
      return;
    }
    final promptController = TextEditingController(text: '');
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        String? selectedAgent = otherAgents.first.id;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Hand off to agent'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: selectedAgent,
                  decoration: const InputDecoration(
                    labelText: 'Target Agent',
                    border: OutlineInputBorder(),
                  ),
                  items: otherAgents
                      .map(
                        (a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(a.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedAgent = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: promptController,
                  decoration: const InputDecoration(
                    labelText: 'Instructions (optional)',
                    hintText: 'Review the code changes...',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, {
                  'agentId': selectedAgent!,
                  'prompt': promptController.text,
                }),
                child: const Text('Hand off'),
              ),
            ],
          ),
        );
      },
    );
    promptController.dispose();
    if (result == null || !mounted) return;
    try {
      final notifier =
          ref.read(gatewayChatProvider(widget.session.id).notifier);
      await notifier.handoff(
        agentId: result['agentId']!,
        prompt: result['prompt']?.isNotEmpty == true
            ? result['prompt']
            : null,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Handoff failed: $e')),
      );
    }
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
                '${totalK}k / ${limitK}k tokens'
                '  (in: ${(usage.inputTokens / 1000).toStringAsFixed(1)}k'
                ' out: ${(usage.outputTokens / 1000).toStringAsFixed(1)}k)',
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

// ─── Command Interception Helper Widgets ────────────────────────────────

class _PermOption {
  const _PermOption(this.value, this.label, this.description);
  final String value;
  final String label;
  final String description;
}

class _PermissionPickerSheet extends StatelessWidget {
  const _PermissionPickerSheet({required this.options});
  final List<_PermOption> options;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Permission mode',
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final opt in options)
            ListTile(
              leading: const Icon(Icons.security),
              title: Text(opt.label),
              subtitle: Text(opt.description),
              onTap: () => Navigator.pop(context, opt.value),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SessionPickerSheet extends StatelessWidget {
  const _SessionPickerSheet({
    required this.sessions,
    required this.currentSessionId,
  });

  final List<GatewaySessionView> sessions;
  final String currentSessionId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.7;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Text(
              'Switch session',
              style: theme.textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: sessions.length,
              itemBuilder: (ctx, i) {
                final s = sessions[i];
                final isCurrent = s.id == currentSessionId;
                return ListTile(
                  leading: Icon(
                    isCurrent ? Icons.chat_bubble : Icons.chat_bubble_outline,
                    color: isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(
                    s.title.isEmpty ? '(untitled)' : s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: isCurrent
                        ? TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                  ),
                  subtitle: Text(
                    '${s.agentId} - ${s.status}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: isCurrent
                      ? Icon(Icons.check, color: theme.colorScheme.primary, size: 18)
                      : null,
                  onTap: () => Navigator.pop(ctx, s.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusSheet extends StatelessWidget {
  const _StatusSheet({
    required this.sessionId,
    required this.agentId,
    required this.agentName,
    required this.modelId,
    required this.usage,
    required this.connection,
    required this.commands,
  });

  final String sessionId;
  final String agentId;
  final String agentName;
  final String? modelId;
  final TokenUsage? usage;
  final GatewayChatConnectionState connection;
  final List<GatewayCommandView> commands;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.8;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Text('Status', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: 16),
            _statusRow(theme, 'Session', sessionId),
            _statusRow(theme, 'Agent', agentName),
            _statusRow(theme, 'Model', modelId ?? 'default'),
            _statusRow(
              theme,
              'Connection',
              switch (connection) {
                GatewayChatConnectionState.connected => 'Connected',
                GatewayChatConnectionState.connecting => 'Connecting...',
                GatewayChatConnectionState.disconnected => 'Disconnected',
              },
            ),
            if (usage != null) ...[
              _statusRow(
                theme,
                'Tokens',
                '${(usage!.totalTokens / 1000).toStringAsFixed(1)}k / '
                    '${(TokenUsage.contextLimit / 1000).toStringAsFixed(0)}k',
              ),
              _statusRow(
                theme,
                'Input / Output',
                '${(usage!.inputTokens / 1000).toStringAsFixed(1)}k / '
                    '${(usage!.outputTokens / 1000).toStringAsFixed(1)}k',
              ),
            ],
            if (commands.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'Available commands',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              for (final cmd in commands)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(
                        cmd.name,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (cmd.description.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            cmd.description,
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _CostSheet extends StatelessWidget {
  const _CostSheet({required this.usage});
  final TokenUsage? usage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (usage == null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'No token usage data available yet.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }
    final u = usage!;
    final ratio = u.ratio.clamp(0.0, 1.0);
    final color = ratio > 0.8 ? scheme.error : scheme.primary;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Token Usage', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.15)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total', style: theme.textTheme.bodyMedium),
                      Text(
                        '${(u.totalTokens / 1000).toStringAsFixed(1)}k / '
                        '${(TokenUsage.contextLimit / 1000).toStringAsFixed(0)}k',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: ratio,
                      minHeight: 6,
                      backgroundColor: scheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Input tokens', style: theme.textTheme.bodySmall),
                      Text(
                        '${(u.inputTokens / 1000).toStringAsFixed(1)}k',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Output tokens', style: theme.textTheme.bodySmall),
                      Text(
                        '${(u.outputTokens / 1000).toStringAsFixed(1)}k',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Context used', style: theme.textTheme.bodySmall),
                      Text(
                        '${(ratio * 100).toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisconnectedBanner extends StatelessWidget {
  const _DisconnectedBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: scheme.error.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 14, color: scheme.error),
          const SizedBox(width: 8),
          Text(
            'Disconnected — reconnecting...',
            style: TextStyle(
              fontSize: 12,
              color: scheme.error,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectingBanner extends StatelessWidget {
  const _ConnectingBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: scheme.surfaceContainerHigh,
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Connecting...',
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _FileHintBar extends StatelessWidget {
  const _FileHintBar({required this.directory});
  final String directory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2))),
      ),
      child: Row(
        children: [
          Icon(Icons.attach_file, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Type file path relative to ${_shortDir(directory)}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  static String _shortDir(String path) {
    final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty).toList();
    return parts.length > 2 ? '.../${parts.sublist(parts.length - 2).join('/')}' : path;
  }
}
