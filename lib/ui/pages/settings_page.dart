import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/gateway_client.dart';
import '../../models/agent.dart';
import '../../state/agent_config_filter.dart';
import '../../state/settings_store.dart';
import '../widgets/model_picker.dart';
import 'home_page.dart';

class _ProviderBadge extends StatelessWidget {
  const _ProviderBadge({required this.provider});
  final String? provider;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (provider) {
      'anthropic' => ('Anthropic', const Color(0xFFCC785C)),
      'openai' => ('OpenAI', const Color(0xFF10A37F)),
      'google' => ('Google', const Color(0xFF4285F4)),
      'opencode' => ('OpenCode', const Color(0xFF7C3AED)),
      _ => (
          provider == null || provider!.isEmpty ? 'Other' : provider!,
          scheme.outline
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
      ),
    );
  }
}

class _CredentialEntryTile extends StatelessWidget {
  const _CredentialEntryTile({
    required this.entry,
    required this.onTap,
  });

  final Map<String, dynamic> entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isCurrent = entry['isCurrent'] == true;
    final raw = entry['raw'];
    final appType = raw is Map ? raw['appType']?.toString() : null;
    return ListTile(
      dense: true,
      leading: Icon(
        isCurrent ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 18,
        color: isCurrent ? Colors.green : Theme.of(context).disabledColor,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              entry['label']?.toString() ?? 'Unnamed',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 8),
          _ProviderBadge(provider: entry['provider']?.toString()),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (appType != null && appType.isNotEmpty)
            Text(
              appType,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (entry['tokenPreview'] != null)
            Text(
              entry['tokenPreview'].toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontFeatures: const [
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
          if (entry['baseUrl'] != null)
            Text(
              entry['baseUrl'].toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
      onTap: onTap,
    );
  }
}

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key, this.firstRun = false});
  final bool firstRun;

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _baseUrlCtrl;
  Map<String, List<ModelChoice>> _agentModels = const {};
  List<Agent> _agents = const [];
  Set<String> _refreshingAgentIds = const {};
  bool _testing = false;
  String? _testError;
  bool? _testOk;

  List<Map<String, dynamic>> _configEntries = const [];
  bool _profilesLoading = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsControllerProvider);
    _baseUrlCtrl = TextEditingController(text: s.baseUrl);
    // Auto-test if URL is already configured.
    if (s.baseUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _testAndLoadModels();
      });
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _profilesLoading = true);
    try {
      final client = GatewayClient(
        baseUrl: Uri.parse(url),
      );
      final profiles = await client.listProfiles();
      final configs = <Map<String, dynamic>>[
        for (final profile in profiles) _normalizeProfileEntry(profile),
      ];
      try {
        configs.addAll(
          (await client.listOfficialCredentials()).map(
            (entry) => _normalizeCredentialSourceEntry(entry, 'official'),
          ),
        );
      } catch (_) {
        // Optional source; keep profiles usable if local discovery is absent.
      }
      try {
        configs.addAll(
          (await client.listCcSwitchCredentials()).map(
            (entry) => _normalizeCredentialSourceEntry(entry, 'cc-switch'),
          ),
        );
      } catch (_) {
        // Optional source; CC-Switch may not be installed on this machine.
      }
      client.close();
      if (!mounted) return;
      setState(() {
        _configEntries = configs;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _profilesLoading = false);
    }
  }

  Map<String, dynamic> _normalizeProfileEntry(Map<String, dynamic> profile) {
    final providers = credentialEntryProviders(profile);
    final provider = providers.isEmpty ? null : providers.first;
    final baseUrl = _profileBaseUrl(profile, provider);
    return <String, dynamic>{
      ...profile,
      'source': 'profile',
      'label': profile['name'] ?? profile['label'] ?? 'Unnamed',
      if (provider != null) 'provider': provider,
      if (baseUrl != null && baseUrl.isNotEmpty) 'baseUrl': baseUrl,
    };
  }

  Map<String, dynamic> _normalizeCredentialSourceEntry(
    Map<String, dynamic> entry,
    String source,
  ) {
    return <String, dynamic>{
      ...entry,
      'source': entry['source'] ?? source,
      'label': entry['label'] ?? 'Unnamed',
    };
  }

  String? _profileBaseUrl(Map<String, dynamic> profile, String? provider) {
    if (provider == null) return null;
    final keys = profile['keys'];
    final entry = keys is Map ? keys[provider] : null;
    if (entry is Map && entry['baseUrl'] != null) {
      return entry['baseUrl'].toString();
    }
    return null;
  }

  Future<void> _openProfileEditor({Map<String, dynamic>? existing}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _ProfileEditorPage(
          baseUrl: _baseUrlCtrl.text.trim(),
          existing: existing,
        ),
      ),
    );
    if (result == true) {
      await _loadProfiles();
    }
  }

  Future<Map<String, dynamic>?> _pickCredentialEntry(
    List<Map<String, dynamic>> entries, {
    required String title,
  }) async {
    if (entries.length == 1) return entries.first;
    final grouped = _groupCredentialEntries(entries);
    final groupKeys = grouped.keys.toList()
      ..sort((a, b) {
        final order =
            _credentialGroupOrder(a).compareTo(_credentialGroupOrder(b));
        if (order != 0) return order;
        return _credentialGroupLabel(a).compareTo(_credentialGroupLabel(b));
      });
    final initialGroup = groupKeys.firstWhere(
      (key) => grouped[key]!.any((entry) => entry['isCurrent'] == true),
      orElse: () => groupKeys.first,
    );

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: SingleChildScrollView(
              child: ExpansionPanelList.radio(
                initialOpenPanelValue: initialGroup,
                children: [
                  for (final key in groupKeys)
                    ExpansionPanelRadio(
                      value: key,
                      headerBuilder: (context, isExpanded) {
                        final items = grouped[key]!;
                        final current =
                            items.any((entry) => entry['isCurrent'] == true);
                        return ListTile(
                          dense: true,
                          title: Text(_credentialGroupLabel(key)),
                          subtitle: Text(
                            current
                                ? '${items.length} providers - current selected'
                                : '${items.length} providers',
                          ),
                        );
                      },
                      body: Column(
                        children: [
                          for (final entry in grouped[key]!)
                            _CredentialEntryTile(
                              entry: entry,
                              onTap: () => Navigator.pop(ctx, entry),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, List<Map<String, dynamic>>> _groupCredentialEntries(
    List<Map<String, dynamic>> entries,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final entry in entries) {
      final key = _credentialGroupKey(entry);
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(entry);
    }
    return grouped;
  }

  String _credentialGroupKey(Map<String, dynamic> entry) {
    final raw = entry['raw'];
    if (raw is Map && raw['appType'] != null) {
      return raw['appType'].toString();
    }
    return entry['provider']?.toString() ?? 'other';
  }

  int _credentialGroupOrder(String key) {
    return switch (key) {
      'claude' => 0,
      'claude-desktop' => 1,
      'codex' => 2,
      'opencode' => 3,
      'anthropic' => 4,
      'openai' => 5,
      'google' => 6,
      _ => 99,
    };
  }

  String _credentialGroupLabel(String key) {
    return switch (key) {
      'claude' => 'Claude',
      'claude-desktop' => 'Claude Desktop',
      'codex' => 'Codex',
      'opencode' => 'OpenCode',
      'anthropic' => 'Anthropic',
      'openai' => 'OpenAI',
      'google' => 'Google',
      _ => key.isEmpty ? 'Other' : key,
    };
  }

  Future<String?> _promptProfileName({
    required String defaultName,
    required Map<String, dynamic> entry,
  }) async {
    final ctrl = TextEditingController(text: defaultName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this profile'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry['label']?.toString() ?? '',
                          style: Theme.of(ctx)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ProviderBadge(
                        provider: entry['provider']?.toString(),
                      ),
                    ],
                  ),
                  if (entry['tokenPreview'] != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry['tokenPreview'].toString(),
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                  if (entry['baseUrl'] != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      entry['baseUrl'].toString(),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Profile name'),
              onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }

  String _providerDisplay(String? provider) {
    switch (provider) {
      case 'anthropic':
        return 'Anthropic';
      case 'openai':
        return 'OpenAI';
      case 'google':
        return 'Google';
      case 'opencode':
        return 'OpenCode';
      default:
        return provider == null || provider.isEmpty ? 'Provider' : provider;
    }
  }

  List<Map<String, dynamic>> _configEntriesForAgent(String agentId) {
    return credentialEntriesForAgent(agentId, _configEntries);
  }

  Map<String, dynamic>? _selectedConfigForAgent(
    String agentId,
    AppSettings settings,
  ) {
    final profileId = settings.selectedProfileByAgent[agentId];
    if (profileId == null || profileId.isEmpty) return null;
    for (final entry in _configEntries) {
      if (entry['source'] == 'profile' &&
          entry['id']?.toString() == profileId) {
        return entry;
      }
    }
    return null;
  }

  Future<String?> _profileIdForConfig(Map<String, dynamic> entry) async {
    final source = entry['source']?.toString() ?? 'profile';
    final id = entry['id']?.toString();
    if (source == 'profile') return id;
    if (source != 'official' && source != 'cc-switch') return null;

    final providerLabel = _providerDisplay(entry['provider']?.toString());
    final defaultName = '${entry['label'] ?? providerLabel} ($providerLabel)';
    final name = await _promptProfileName(
      defaultName: defaultName,
      entry: entry,
    );
    if (name == null) return null;

    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) return null;
    final client = GatewayClient(baseUrl: Uri.parse(url));
    try {
      final profile = await client.importProfile(
        name: name,
        source: source,
        sourceId: id,
      );
      return profile['id']?.toString();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $err')),
        );
      }
      return null;
    } finally {
      client.close();
    }
  }

  Future<void> _chooseAgentConfig(Agent agent) async {
    if (_configEntries.isEmpty && !_profilesLoading) {
      await _loadProfiles();
    }
    final entries = _configEntriesForAgent(agent.id);
    if (entries.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No ${agent.displayName} config found')),
      );
      return;
    }

    final picked = await _pickCredentialEntry(
      entries,
      title: 'Choose ${agent.displayName} config',
    );
    if (picked == null) return;

    final profileId = await _profileIdForConfig(picked);
    if (profileId == null || profileId.isEmpty) return;
    final saved = await _saveAgentSettings(
      agent.id,
      profileId: profileId,
      defaultModel: '',
    );
    if (!saved) return;
    final controller = ref.read(settingsControllerProvider.notifier);
    await controller.setSelectedProfileForAgent(agent.id, profileId);
    await controller.setDefaultModelForAgent(agent.id, '');
    await _loadProfiles();
    await _refreshAgentModels(agent, profileId: profileId);
  }

  Future<void> _pickDefaultModel(Agent agent) async {
    var models = _agentModels[agent.id] ?? const <ModelChoice>[];
    if (models.isEmpty) {
      await _refreshAgentModels(agent);
      models = _agentModels[agent.id] ?? const <ModelChoice>[];
    }
    if (models.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No models returned for ${agent.displayName}')),
      );
      return;
    }

    final settings = ref.read(settingsControllerProvider);
    final selectedId = settings.defaultModelByAgent[agent.id];
    ModelChoice? selected;
    for (final model in models) {
      if (model.modelId == selectedId) {
        selected = model;
        break;
      }
    }
    if (!mounted) return;
    final picked = await showModelPicker(
      context,
      models: models,
      selected: selected,
    );
    if (picked == null) return;

    final saved = await _saveAgentSettings(
      agent.id,
      defaultModel: picked.modelId,
    );
    if (!saved) return;
    await ref
        .read(settingsControllerProvider.notifier)
        .setDefaultModelForAgent(agent.id, picked.modelId);
  }

  Future<bool> _saveAgentSettings(
    String agentId, {
    String? profileId,
    String? defaultModel,
  }) async {
    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) return false;
    final client = GatewayClient(baseUrl: Uri.parse(url));
    try {
      await client.updateAgentSettings(
        agentId,
        profileId: profileId,
        defaultModel: defaultModel,
      );
      return true;
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save agent settings: $err')),
        );
      }
      return false;
    } finally {
      client.close();
    }
  }

  Future<void> _refreshAgentModels(Agent agent, {String? profileId}) async {
    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _refreshingAgentIds = {..._refreshingAgentIds, agent.id};
    });
    final client = GatewayClient(baseUrl: Uri.parse(url));
    try {
      final settings = ref.read(settingsControllerProvider);
      final models = await client.listAgentModels(
        agent.id,
        profileId: profileId ?? settings.selectedProfileByAgent[agent.id],
      );
      if (!mounted) return;
      setState(() {
        final next = Map<String, List<ModelChoice>>.from(_agentModels);
        next[agent.id] = _modelChoicesForAgent(agent, models);
        _agentModels = next;
      });
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load models: $err')),
        );
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() {
          _refreshingAgentIds = {
            for (final id in _refreshingAgentIds)
              if (id != agent.id) id,
          };
        });
      }
    }
  }

  List<ModelChoice> _modelChoicesForAgent(
    Agent agent,
    List<AgentModel> models,
  ) {
    return models.map((model) {
      final slash = model.id.indexOf('/');
      final provider = slash > 0 ? model.id.substring(0, slash) : agent.id;
      return (
        providerId: provider,
        modelId: model.id,
        label: model.displayName.trim().isEmpty ? model.id : model.displayName,
      );
    }).toList(growable: false);
  }

  Future<AppSettings> _syncRemoteAgentSettings(GatewayClient client) async {
    try {
      final remote = await client.listAgentSettings();
      final current = ref.read(settingsControllerProvider);
      final profiles = Map<String, String>.from(current.selectedProfileByAgent);
      final models = Map<String, String>.from(current.defaultModelByAgent);
      var changed = false;
      for (final setting in remote) {
        final agentId = setting['agentId']?.toString() ?? '';
        if (agentId.isEmpty) continue;
        final profileId = setting['profileId']?.toString() ?? '';
        if (profileId.isNotEmpty && profiles[agentId] != profileId) {
          profiles[agentId] = profileId;
          changed = true;
        }
        final defaultModel = setting['defaultModel']?.toString() ?? '';
        if (defaultModel.isNotEmpty && models[agentId] != defaultModel) {
          models[agentId] = defaultModel;
          changed = true;
        }
      }
      if (changed) {
        await ref.read(settingsControllerProvider.notifier).update(
              current.copyWith(
                selectedProfileByAgent: profiles,
                defaultModelByAgent: models,
              ),
            );
      }
    } catch (_) {
      // Older gateways may not have agent-scoped settings yet.
    }
    return ref.read(settingsControllerProvider);
  }

  Future<void> _testAndLoadModels() async {
    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() {
      _testing = true;
      _testError = null;
      _testOk = null;
    });
    try {
      final client = GatewayClient(
        baseUrl: Uri.parse(url),
      );
      final ok = await client.health();
      if (!ok) {
        setState(() {
          _testOk = false;
          _testError = 'Server unreachable.';
        });
        client.close();
        return;
      }
      await _loadProfiles();
      final agents = await client.listAgents();
      final perAgent = <String, List<ModelChoice>>{};
      final settings = await _syncRemoteAgentSettings(client);
      for (final agent in agents) {
        if (!agent.supportsModels) continue;
        final agentModelList = await client.listAgentModels(
          agent.id,
          profileId: settings.selectedProfileByAgent[agent.id],
        );
        perAgent[agent.id] = _modelChoicesForAgent(agent, agentModelList);
      }
      client.close();
      if (!mounted) return;
      setState(() {
        _agents = agents;
        _agentModels = perAgent;
        _testOk = true;
      });
    } catch (err) {
      setState(() {
        _testOk = false;
        _testError = '$err';
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final controller = ref.read(settingsControllerProvider.notifier);
    final current = ref.read(settingsControllerProvider);
    await controller.update(
      current.copyWith(baseUrl: _baseUrlCtrl.text.trim()),
    );
    if (!mounted) return;
    if (widget.firstRun) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsControllerProvider);
    final canSave = _baseUrlCtrl.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        automaticallyImplyLeading: widget.firstRun,
        actions: [
          if (!widget.firstRun)
            TextButton(
              onPressed: canSave ? _save : null,
              child: const Text('Save'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const _SectionHeader(title: 'Connection', icon: Icons.dns_outlined),
          const SizedBox(height: 10),
          TextField(
            controller: _baseUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://100.x.x.x:4096',
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _testing ? null : _testAndLoadModels,
                icon: _testing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bolt_outlined, size: 18),
                label: Text(_testing ? 'Connecting...' : 'Test connection'),
              ),
              const SizedBox(width: 12),
              if (_testOk == true)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Connected',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_testOk == false)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.error,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Failed',
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_testError != null) ...[
            const SizedBox(height: 8),
            Text(
              _testError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          if (_agents.isNotEmpty) ...[
            const SizedBox(height: 28),
            const _SectionHeader(
              title: 'Agents & Models',
              icon: Icons.smart_toy_outlined,
            ),
            const SizedBox(height: 10),
            for (final agent in _agents)
              _AgentModelSection(
                agent: agent,
                models: _agentModels[agent.id] ?? const [],
                configEntries: _configEntriesForAgent(agent.id),
                selectedConfig: _selectedConfigForAgent(agent.id, settings),
                selectedModelId: settings.defaultModelByAgent[agent.id],
                loadingConfigs: _profilesLoading,
                loadingModels: _refreshingAgentIds.contains(agent.id),
                onChooseConfig: () => _chooseAgentConfig(agent),
                onPickDefaultModel: () => _pickDefaultModel(agent),
                onRefreshModels: () => _refreshAgentModels(agent),
                onAddManualConfig: () => _openProfileEditor(),
              ),
          ],
          const SizedBox(height: 28),
          const _SectionHeader(
            title: 'Appearance',
            icon: Icons.palette_outlined,
          ),
          const SizedBox(height: 10),
          _ThemeSelector(
            current: settings.themeMode,
            onChanged: (mode) {
              final ctrl = ref.read(settingsControllerProvider.notifier);
              ctrl.update(
                ref.read(settingsControllerProvider).copyWith(themeMode: mode),
              );
            },
          ),
          const SizedBox(height: 32),
          if (widget.firstRun)
            FilledButton.tonal(
              onPressed: canSave ? _save : null,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Continue'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Expandable section showing one agent and its available models.
class _AgentModelSection extends StatelessWidget {
  const _AgentModelSection({
    required this.agent,
    required this.models,
    required this.configEntries,
    required this.selectedConfig,
    required this.selectedModelId,
    required this.loadingConfigs,
    required this.loadingModels,
    required this.onChooseConfig,
    required this.onPickDefaultModel,
    required this.onRefreshModels,
    required this.onAddManualConfig,
  });

  final Agent agent;
  final List<ModelChoice> models;
  final List<Map<String, dynamic>> configEntries;
  final Map<String, dynamic>? selectedConfig;
  final String? selectedModelId;
  final bool loadingConfigs;
  final bool loadingModels;
  final VoidCallback onChooseConfig;
  final VoidCallback onPickDefaultModel;
  final VoidCallback onRefreshModels;
  final VoidCallback onAddManualConfig;

  IconData _agentIcon(String id) => switch (id) {
        'codex' => Icons.code,
        'claude-code' => Icons.auto_awesome,
        'opencode' => Icons.terminal,
        _ => Icons.smart_toy_outlined,
      };

  String _configTitle() {
    final config = selectedConfig;
    if (config == null) return 'No config selected';
    return config['label']?.toString() ??
        config['name']?.toString() ??
        'Unnamed';
  }

  String _configSubtitle() {
    final config = selectedConfig;
    if (config == null) {
      return configEntries.isEmpty
          ? 'No matching config found'
          : '${configEntries.length} configs available';
    }
    final source = switch (config['source']?.toString()) {
      'profile' => 'Gateway profile',
      'official' => 'Local config',
      'cc-switch' => 'CC-Switch',
      _ => 'Config',
    };
    final provider = config['provider']?.toString();
    final baseUrl = config['baseUrl']?.toString();
    return [
      source,
      if (provider != null && provider.isNotEmpty) provider,
      if (baseUrl != null && baseUrl.isNotEmpty) baseUrl,
    ].join(' / ');
  }

  String _agentSubtitle(bool available) {
    final modelText = '${models.length} model${models.length == 1 ? '' : 's'}';
    if (!available) return 'Not installed / $modelText loaded';
    if (selectedConfig != null &&
        selectedModelId != null &&
        selectedModelId!.isNotEmpty) {
      return '$modelText / default: $selectedModelId';
    }
    return '$modelText available';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final available = agent.raw['available'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(
          _agentIcon(agent.id),
          color: available
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        title: Text(agent.displayName),
        subtitle: Text(
          _agentSubtitle(available),
          style: theme.textTheme.bodySmall?.copyWith(
            color: available ? null : theme.colorScheme.error,
          ),
        ),
        trailing: available
            ? null
            : Icon(Icons.warning_amber, color: theme.colorScheme.error),
        children: [
          ListTile(
            dense: true,
            leading: const Icon(Icons.manage_accounts_outlined, size: 20),
            title: Text(_configTitle()),
            subtitle: Text(
              loadingConfigs ? 'Loading configs...' : _configSubtitle(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Add manual config',
                  icon: const Icon(Icons.add),
                  onPressed: onAddManualConfig,
                ),
                IconButton(
                  tooltip: 'Choose config',
                  icon: const Icon(Icons.tune),
                  onPressed: loadingConfigs ? null : onChooseConfig,
                ),
              ],
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.psychology_outlined, size: 20),
            title: Text(
              selectedModelId == null || selectedModelId!.isEmpty
                  ? 'No default model'
                  : selectedModelId!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: selectedModelId == null || selectedModelId!.isEmpty
                    ? null
                    : 'monospace',
              ),
            ),
            subtitle: Text(
              '${models.length} model${models.length == 1 ? '' : 's'} loaded',
            ),
            trailing: Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Refresh models',
                  icon: loadingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  onPressed: loadingModels ? null : onRefreshModels,
                ),
                IconButton(
                  tooltip: 'Choose default model',
                  icon: const Icon(Icons.unfold_more),
                  onPressed: loadingModels ? null : onPickDefaultModel,
                ),
              ],
            ),
          ),
          if (models.isNotEmpty)
            ...models.take(8).map(
                  (m) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: const Icon(Icons.circle, size: 8),
                    title: Text(
                      m.modelId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                loadingModels ? 'Loading models...' : 'No models loaded',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }
}

class _ThemeSelector extends StatelessWidget {
  const _ThemeSelector({
    required this.current,
    required this.onChanged,
  });

  final ThemeMode current;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment(
          value: ThemeMode.system,
          label: Text('System'),
          icon: Icon(Icons.brightness_auto),
        ),
        ButtonSegment(
          value: ThemeMode.light,
          label: Text('Light'),
          icon: Icon(Icons.light_mode),
        ),
        ButtonSegment(
          value: ThemeMode.dark,
          label: Text('Dark'),
          icon: Icon(Icons.dark_mode),
        ),
      ],
      selected: {current},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

class _ProfileEditorPage extends StatefulWidget {
  const _ProfileEditorPage({
    required this.baseUrl,
    this.existing,
  });

  final String baseUrl;
  final Map<String, dynamic>? existing;

  @override
  State<_ProfileEditorPage> createState() => _ProfileEditorPageState();
}

class _ProfileEditorPageState extends State<_ProfileEditorPage> {
  late final TextEditingController _nameCtrl;

  // Per-provider key controllers
  late final TextEditingController _anthropicKeyCtrl;
  late final TextEditingController _anthropicBaseUrlCtrl;
  late final TextEditingController _openaiKeyCtrl;
  late final TextEditingController _openaiBaseUrlCtrl;
  late final TextEditingController _opencodeKeyCtrl;
  late final TextEditingController _opencodeBaseUrlCtrl;

  // Masked key hints shown as placeholder when editing
  String _anthropicKeyHint = '';
  String _openaiKeyHint = '';
  String _opencodeKeyHint = '';

  final Map<String, bool> _obscure = {
    'anthropic': true,
    'openai': true,
    'opencode': true,
  };

  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameCtrl = TextEditingController(
      text: existing?['name'] as String? ?? '',
    );

    final keys = existing?['keys'] as Map<String, dynamic>? ?? {};
    final anthropic = keys['anthropic'] as Map<String, dynamic>? ?? {};
    final openai = keys['openai'] as Map<String, dynamic>? ?? {};
    final opencode = keys['opencode'] as Map<String, dynamic>? ?? {};

    // When editing, don't populate key fields with masked values.
    // Show masked values as hints only; empty field means "keep existing".
    final isEdit = existing != null;
    _anthropicKeyCtrl = TextEditingController(
      text: isEdit ? '' : (anthropic['key'] as String? ?? ''),
    );
    _anthropicBaseUrlCtrl =
        TextEditingController(text: anthropic['baseUrl'] as String? ?? '');
    _openaiKeyCtrl = TextEditingController(
      text: isEdit ? '' : (openai['key'] as String? ?? ''),
    );
    _openaiBaseUrlCtrl =
        TextEditingController(text: openai['baseUrl'] as String? ?? '');
    _opencodeKeyCtrl = TextEditingController(
      text: isEdit ? '' : (opencode['key'] as String? ?? ''),
    );
    _opencodeBaseUrlCtrl =
        TextEditingController(text: opencode['baseUrl'] as String? ?? '');

    _anthropicKeyHint = anthropic['key'] as String? ?? '';
    _openaiKeyHint = openai['key'] as String? ?? '';
    _opencodeKeyHint = opencode['key'] as String? ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _anthropicKeyCtrl.dispose();
    _anthropicBaseUrlCtrl.dispose();
    _openaiKeyCtrl.dispose();
    _openaiBaseUrlCtrl.dispose();
    _opencodeKeyCtrl.dispose();
    _opencodeBaseUrlCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic> _buildKeys() {
    final keys = <String, dynamic>{};
    void addProvider(
      String name,
      TextEditingController keyCtrl,
      TextEditingController baseUrlCtrl,
    ) {
      final key = keyCtrl.text.trim();
      final baseUrl = baseUrlCtrl.text.trim();
      if (key.isNotEmpty || baseUrl.isNotEmpty) {
        keys[name] = <String, dynamic>{
          if (key.isNotEmpty) 'key': key,
          if (baseUrl.isNotEmpty) 'baseUrl': baseUrl,
        };
      }
    }

    addProvider('anthropic', _anthropicKeyCtrl, _anthropicBaseUrlCtrl);
    addProvider('openai', _openaiKeyCtrl, _openaiBaseUrlCtrl);
    addProvider('opencode', _opencodeKeyCtrl, _opencodeBaseUrlCtrl);
    return keys;
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile name is required')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final client = GatewayClient(
        baseUrl: Uri.parse(widget.baseUrl),
      );
      final keys = _buildKeys();
      if (_isEditing) {
        final id = widget.existing!['id'] as String;
        await client.updateProfile(id, name: name, keys: keys);
      } else {
        await client.createProfile(name: name, keys: keys);
      }
      client.close();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save profile: $err')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Profile' : 'New Profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Profile Name',
              prefixIcon: Icon(Icons.label_outlined),
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 24),
          _buildProviderSection(
            theme: theme,
            title: 'Anthropic',
            providerKey: 'anthropic',
            keyCtrl: _anthropicKeyCtrl,
            baseUrlCtrl: _anthropicBaseUrlCtrl,
            keyHint: _anthropicKeyHint,
          ),
          const SizedBox(height: 16),
          _buildProviderSection(
            theme: theme,
            title: 'OpenAI',
            providerKey: 'openai',
            keyCtrl: _openaiKeyCtrl,
            baseUrlCtrl: _openaiBaseUrlCtrl,
            keyHint: _openaiKeyHint,
          ),
          const SizedBox(height: 16),
          _buildProviderSection(
            theme: theme,
            title: 'OpenCode',
            providerKey: 'opencode',
            keyCtrl: _opencodeKeyCtrl,
            baseUrlCtrl: _opencodeBaseUrlCtrl,
            keyHint: _opencodeKeyHint,
          ),
        ],
      ),
    );
  }

  Widget _buildProviderSection({
    required ThemeData theme,
    required String title,
    required String providerKey,
    required TextEditingController keyCtrl,
    required TextEditingController baseUrlCtrl,
    String keyHint = '',
  }) {
    final isObscured = _obscure[providerKey] ?? true;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: keyCtrl,
              obscureText: isObscured,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: keyHint.isNotEmpty ? keyHint : null,
                prefixIcon: const Icon(Icons.vpn_key_outlined),
                suffixIcon: IconButton(
                  icon: Icon(
                    isObscured ? Icons.visibility_off : Icons.visibility,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscure[providerKey] = !isObscured;
                    });
                  },
                ),
                isDense: true,
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: baseUrlCtrl,
              decoration: const InputDecoration(
                labelText: 'Base URL (optional)',
                prefixIcon: Icon(Icons.link),
                isDense: true,
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          ],
        ),
      ),
    );
  }
}
