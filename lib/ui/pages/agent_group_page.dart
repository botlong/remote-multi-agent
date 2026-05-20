import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/gateway_providers.dart';
import '../widgets/agent_badge.dart';
import '../widgets/model_picker.dart';
import 'gateway_chat_page.dart';
import 'gateway_ui_adapters.dart';

class AgentGroupPage extends ConsumerStatefulWidget {
  const AgentGroupPage({
    super.key,
    required this.project,
  });

  final GatewayProjectView project;

  @override
  ConsumerState<AgentGroupPage> createState() => _AgentGroupPageState();
}

class _AgentGroupPageState extends ConsumerState<AgentGroupPage> {
  GatewayAgentView? _selectedAgent;
  GatewayModelView? _selectedModel;
  String? _selectedPermission;
  Future<List<GatewayModelView>>? _modelsFuture;
  bool _modelLookupComplete = false;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(agentCatalogProvider);
    final agents = readAgents(catalog);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New conversation'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
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
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text('Agent', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (agents.isEmpty)
            const _EmptyCatalog()
          else
            for (final agent in agents)
              _AgentOption(
                agent: agent,
                selected: _selectedAgent?.id == agent.id,
                onTap: () => setState(() {
                  _selectedAgent = agent;
                  _selectedModel = null;
                  _modelLookupComplete = false;
                  _modelsFuture = _loadModels(agent.id);
                  _selectedPermission = _defaultPermission(agent.id);
                }),
              ),
          if (_selectedAgent != null) ...[
            const SizedBox(height: 20),
            Text('Permission mode', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _PermissionPicker(
              agentId: _selectedAgent!.id,
              selected: _selectedPermission,
              onSelected: (v) => setState(() => _selectedPermission = v),
            ),
          ],
          if (_selectedAgent != null && _selectedAgent!.supportsModels) ...[
            const SizedBox(height: 20),
            Text('Model', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FutureBuilder<List<GatewayModelView>>(
              future: _modelsFuture ?? _loadModels(_selectedAgent!.id),
              builder: (context, snapshot) {
                final models = snapshot.data ?? const <GatewayModelView>[];
                if (snapshot.connectionState == ConnectionState.waiting &&
                    models.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (models.isNotEmpty &&
                    _selectedModel == null &&
                    _selectedAgent != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && _selectedModel == null) {
                      setState(() => _selectedModel = models.first);
                    }
                  });
                }
                if (snapshot.connectionState == ConnectionState.done &&
                    !_modelLookupComplete) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted && !_modelLookupComplete) {
                      setState(() => _modelLookupComplete = true);
                    }
                  });
                }
                return _ModelPicker(
                  agentId: _selectedAgent!.id,
                  models: models,
                  selected: _selectedModel,
                  onSelected: (model) => setState(() => _selectedModel = model),
                );
              },
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton.icon(
            icon: _creating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward),
            label: const Text('Create session'),
            onPressed: _canCreate ? _createSession : null,
          ),
        ),
      ),
    );
  }

  Future<List<GatewayModelView>> _loadModels(String agentId) async {
    final notifier = ref.read(agentCatalogProvider.notifier);
    try {
      final models = await notifier.modelsFor(agentId);
      return models
          .map(
            (model) => GatewayModelView(
              id: model.id,
              displayName: model.displayName.trim().isEmpty
                  ? model.id
                  : model.displayName,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return _selectedAgent?.models ?? const <GatewayModelView>[];
    }
  }

  bool get _canCreate {
    if (_creating || _selectedAgent == null) return false;
    if (_selectedAgent!.supportsModels) {
      return _selectedModel != null ||
          (_modelLookupComplete && _selectedAgent!.models.isEmpty);
    }
    return true;
  }

  Future<void> _createSession() async {
    final agent = _selectedAgent;
    if (agent == null) return;
    setState(() => _creating = true);
    try {
      final notifier =
          ref.read(gatewaySessionListProvider(widget.project.id).notifier);
      final isCodex = agent.id == 'codex';
      final created = await notifier.createSession(
        agentId: agent.id,
        modelId: _selectedModel?.id,
        sandbox: isCodex ? _selectedPermission : null,
        permissionMode: !isCodex ? _selectedPermission : null,
      );
      if (!mounted) return;
      final session = readSession(created);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => GatewayChatPage(
            session: session,
            project: widget.project,
            agent: agent,
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Create failed: $err')),
      );
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }
}

/// Safe default for headless agent runs. Without this Claude blocks on
/// interactive permission prompts in `-p` mode.
String _defaultPermission(String agentId) => switch (agentId) {
      'codex' => 'workspace-write',
      'claude-code' => 'acceptEdits',
      'opencode' => 'build',
      _ => 'build',
    };

class _AgentOption extends StatelessWidget {
  const _AgentOption({
    required this.agent,
    required this.selected,
    required this.onTap,
  });

  final GatewayAgentView agent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.55)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          leading: AgentBadge(
            agentId: agent.id,
            label: agent.displayName,
            compact: true,
          ),
          title: Text(agent.displayName),
          subtitle: Text(
            [
              if (agent.supportsModels) 'models',
              if (agent.supportsSlashCommands) 'slash commands',
            ].join(' / '),
          ),
          trailing: selected ? const Icon(Icons.check_circle) : null,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({
    required this.agentId,
    required this.models,
    required this.selected,
    required this.onSelected,
  });

  final String agentId;
  final List<GatewayModelView> models;
  final GatewayModelView? selected;
  final ValueChanged<GatewayModelView> onSelected;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) {
      return Text(
        'Gateway did not report selectable models.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final theme = Theme.of(context);
    final selectedLabel = selected == null
        ? 'Select a model'
        : selected!.displayName.trim().isEmpty
            ? selected!.id
            : selected!.displayName;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.manage_search_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selectedLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${models.length} models available / tap to search',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.unfold_more),
            ],
          ),
        ),
      ),
    );
  }

  /// Extract real provider from model ID (e.g. "anthropic/claude-4" → "anthropic").
  /// Falls back to agentId if no slash separator found.
  String _providerOf(String modelId) {
    final slash = modelId.indexOf('/');
    return slash > 0 ? modelId.substring(0, slash) : agentId;
  }

  Future<void> _open(BuildContext context) async {
    final choices = [
      for (final model in models)
        (
          providerId: _providerOf(model.id),
          modelId: model.id,
          label:
              model.displayName.trim().isEmpty ? model.id : model.displayName,
        ),
    ];
    final picked = await showModelPicker(
      context,
      models: choices,
      selected: selected == null
          ? null
          : (
              providerId: _providerOf(selected!.id),
              modelId: selected!.id,
              label: selected!.displayName.trim().isEmpty
                  ? selected!.id
                  : selected!.displayName,
            ),
    );
    if (picked == null) return;
    final match = models.firstWhere(
      (model) => model.id == picked.modelId,
      orElse: () => GatewayModelView(
        id: picked.modelId,
        displayName: picked.label,
      ),
    );
    onSelected(match);
  }
}

class _PermissionPicker extends StatelessWidget {
  const _PermissionPicker({
    required this.agentId,
    required this.selected,
    required this.onSelected,
  });

  final String agentId;
  final String? selected;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final options = _optionsFor(agentId);
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final entry in options)
          ChoiceChip(
            label: Text(entry.label),
            selected: selected == entry.value,
            onSelected: (on) => onSelected(on ? entry.value : null),
            tooltip: entry.description,
          ),
      ],
    );
  }

  static List<_PermOption> _optionsFor(String agentId) {
    return switch (agentId) {
      'codex' => const [
          _PermOption('full-auto', 'Full Auto', 'No confirmation needed'),
          _PermOption('workspace-write', 'Write', 'Write to workspace (default)'),
          _PermOption('workspace-read', 'Read-only', 'Read workspace only'),
          _PermOption('locked', 'Locked', 'No file access'),
        ],
      'claude-code' => const [
          _PermOption('acceptEdits', 'Accept Edits', 'Auto-accept edits (default)'),
          _PermOption('plan', 'Plan', 'Plan mode - no code changes'),
          _PermOption('bypassPermissions', 'Full Auto', 'Skip all permission prompts'),
          _PermOption('default', 'Ask', 'Prompt for each permission (interactive only)'),
        ],
      _ => const [
          _PermOption('build', 'Build', 'Standard build mode'),
          _PermOption('plan', 'Plan', 'Plan mode - no code changes'),
        ],
    };
  }
}

class _PermOption {
  const _PermOption(this.value, this.label, this.description);
  final String value;
  final String label;
  final String description;
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Center(
        child: Text(
          'No agents reported by the gateway.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
