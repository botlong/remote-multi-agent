import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/gateway_client.dart';
import '../../models/agent.dart';
import '../../state/settings_store.dart';
import '../widgets/model_picker.dart';
import 'home_page.dart';

enum _AddProfileChoice { official, ccSwitch, manual }

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
      _ => (provider == null || provider!.isEmpty ? 'Other' : provider!, scheme.outline),
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
              letterSpacing: 0.2,
            ),
      ),
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
  late final TextEditingController _tokenCtrl;
  String _providerId = '';
  String _modelId = '';
  List<ModelChoice> _models = const [];
  Map<String, List<ModelChoice>> _agentModels = const {};
  List<Agent> _agents = const [];
  bool _testing = false;
  String? _testError;
  bool? _testOk;

  // ── Profiles state ──
  List<Map<String, dynamic>> _profiles = const [];
  Map<String, dynamic>? _activeProfile;
  bool _profilesLoading = false;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsControllerProvider);
    _baseUrlCtrl = TextEditingController(text: s.baseUrl);
    _tokenCtrl = TextEditingController(text: s.bearerToken);
    _providerId = s.providerId;
    _modelId = s.modelId;
    // Auto-test if URL is already configured.
    if (s.baseUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _testAndLoadModels();
        _loadProfiles();
      });
    }
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) return;
    setState(() => _profilesLoading = true);
    try {
      final client = GatewayClient(
        baseUrl: Uri.parse(url),
        bearerToken: _tokenCtrl.text.trim(),
      );
      final profiles = await client.listProfiles();
      final active = await client.getActiveProfile();
      client.close();
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
        _activeProfile = active;
      });
    } catch (_) {
      // Silently ignore — profiles are optional.
    } finally {
      if (mounted) setState(() => _profilesLoading = false);
    }
  }

  Future<void> _activateProfile(String profileId) async {
    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) return;
    try {
      final client = GatewayClient(
        baseUrl: Uri.parse(url),
        bearerToken: _tokenCtrl.text.trim(),
      );
      await client.activateProfile(profileId);
      client.close();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to activate profile')),
      );
      return;
    }
    await _loadProfiles();
  }

  Future<void> _deleteProfile(String profileId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete profile?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final url = _baseUrlCtrl.text.trim();
    try {
      final client = GatewayClient(
        baseUrl: Uri.parse(url),
        bearerToken: _tokenCtrl.text.trim(),
      );
      await client.deleteProfile(profileId);
      client.close();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete profile')),
      );
      return;
    }
    await _loadProfiles();
  }

  Future<void> _openProfileEditor({Map<String, dynamic>? existing}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _ProfileEditorPage(
          baseUrl: _baseUrlCtrl.text.trim(),
          bearerToken: _tokenCtrl.text.trim(),
          existing: existing,
        ),
      ),
    );
    if (result == true) {
      await _loadProfiles();
    }
  }

  Future<void> _openAddProfileSheet() async {
    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set the server URL first')),
      );
      return;
    }
    final choice = await showModalBottomSheet<_AddProfileChoice>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Add credential profile',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: const Text('From local config files'),
              subtitle: const Text(
                'Claude ~/.claude/settings.json, Codex ~/.codex/auth.json',
              ),
              onTap: () => Navigator.pop(ctx, _AddProfileChoice.official),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_outlined),
              title: const Text('From CC-Switch'),
              subtitle: const Text(
                'Pick any provider configured in CC-Switch',
              ),
              onTap: () => Navigator.pop(ctx, _AddProfileChoice.ccSwitch),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Enter manually'),
              subtitle: const Text(
                'Paste API keys for one or more providers',
              ),
              onTap: () => Navigator.pop(ctx, _AddProfileChoice.manual),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _AddProfileChoice.official:
        await _importFromSource(
          source: 'official',
          dialogTitle: 'Pick a local config file',
          emptyMessage:
              'No credentials found in ~/.claude/settings.json or ~/.codex/auth.json',
          fetch: (c) => c.listOfficialCredentials(),
        );
        break;
      case _AddProfileChoice.ccSwitch:
        await _importFromSource(
          source: 'cc-switch',
          dialogTitle: 'Pick a CC-Switch provider',
          emptyMessage:
              'No providers found in CC-Switch (or node:sqlite unavailable)',
          fetch: (c) => c.listCcSwitchCredentials(),
        );
        break;
      case _AddProfileChoice.manual:
        await _openProfileEditor();
        break;
    }
  }

  Future<void> _importFromSource({
    required String source,
    required String dialogTitle,
    required String emptyMessage,
    required Future<List<Map<String, dynamic>>> Function(GatewayClient) fetch,
  }) async {
    final url = _baseUrlCtrl.text.trim();
    if (url.isEmpty) return;
    final client = GatewayClient(
      baseUrl: Uri.parse(url),
      bearerToken: _tokenCtrl.text.trim(),
    );
    List<Map<String, dynamic>> entries;
    try {
      entries = await fetch(client);
    } catch (err) {
      client.close();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to read source: $err')),
      );
      return;
    }
    if (entries.isEmpty) {
      client.close();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emptyMessage)),
      );
      return;
    }
    final picked = await _pickCredentialEntry(entries, title: dialogTitle);
    if (picked == null) {
      client.close();
      return;
    }
    final providerLabel = _providerDisplay(picked['provider']?.toString());
    final defaultName = '${picked['label'] ?? providerLabel} ($providerLabel)';
    final name = await _promptProfileName(
      defaultName: defaultName,
      entry: picked,
    );
    if (name == null) {
      client.close();
      return;
    }
    try {
      await client.importProfile(
        name: name,
        source: source,
        sourceId: picked['id']?.toString(),
        makeActive: _profiles.isEmpty,
      );
    } catch (err) {
      client.close();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Import failed: $err')),
      );
      return;
    }
    client.close();
    await _loadProfiles();
  }

  Future<Map<String, dynamic>?> _pickCredentialEntry(
    List<Map<String, dynamic>> entries, {
    required String title,
  }) async {
    if (entries.length == 1) return entries.first;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final entry in entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, entry),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      entry['isCurrent'] == true
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: entry['isCurrent'] == true
                          ? Colors.green
                          : Theme.of(ctx).disabledColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry['label']?.toString() ?? 'Unnamed',
                                  style: Theme.of(ctx)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _ProviderBadge(
                                provider: entry['provider']?.toString(),
                              ),
                            ],
                          ),
                          if (entry['tokenPreview'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                entry['tokenPreview'].toString(),
                                style: Theme.of(ctx)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                              ),
                            ),
                          if (entry['baseUrl'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                entry['baseUrl'].toString(),
                                style: Theme.of(ctx).textTheme.bodySmall,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
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
        bearerToken: _tokenCtrl.text.trim(),
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
      final agents = await client.listAgents();
      final models = <ModelChoice>[];
      final perAgent = <String, List<ModelChoice>>{};
      for (final agent in agents) {
        if (!agent.supportsModels) continue;
        final agentModelList = await client.listAgentModels(agent.id);
        final choices = agentModelList
            .map(
              (model) {
                final slash = model.id.indexOf('/');
                final provider = slash > 0 ? model.id.substring(0, slash) : agent.id;
                return (
                  providerId: provider,
                  modelId: model.id,
                  label: model.displayName.trim().isEmpty
                      ? model.id
                      : model.displayName,
                );
              },
            )
            .toList();
        models.addAll(choices);
        perAgent[agent.id] = choices;
      }
      client.close();
      if (!mounted) return;
      setState(() {
        _agents = agents;
        _models = models;
        _agentModels = perAgent;
        _testOk = true;
        final exists = models.any(
          (m) => m.providerId == _providerId && m.modelId == _modelId,
        );
        if (!exists && models.isNotEmpty) {
          _providerId = models.first.providerId;
          _modelId = models.first.modelId;
        }
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
      AppSettings(
        baseUrl: _baseUrlCtrl.text.trim(),
        bearerToken: _tokenCtrl.text.trim(),
        providerId: _providerId,
        modelId: _modelId,
        themeMode: current.themeMode,
      ),
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

  Future<void> _openModelPicker() async {
    final selected = _models.isEmpty
        ? null
        : _models.firstWhere(
            (m) => m.providerId == _providerId && m.modelId == _modelId,
            orElse: () => _models.first,
          );
    final picked = await showModelPicker(
      context,
      models: _models,
      selected: selected,
    );
    if (picked == null) return;
    setState(() {
      _providerId = picked.providerId;
      _modelId = picked.modelId;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _baseUrlCtrl.text.trim().isNotEmpty &&
        _providerId.isNotEmpty &&
        _modelId.isNotEmpty;

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
          // ── Profiles section ───────────────────────────────────────────
          const _SectionHeader(title: 'Profiles', icon: Icons.person_outlined),
          const SizedBox(height: 10),
          if (_activeProfile != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.green,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Active: ${_activeProfile!['name'] ?? 'Unnamed'}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (_profilesLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else ...[
            if (_profiles.isEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'No credentials yet',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'The gateway holds all API credentials. Add one to start a session — import from local config files, pick from CC-Switch, or paste keys manually.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            for (final profile in _profiles)
              _ProfileTile(
                profile: profile,
                isActive: _activeProfile != null &&
                    _activeProfile!['id'] == profile['id'],
                onTap: () {
                  final id = profile['id'] as String?;
                  if (id != null) _activateProfile(id);
                },
                onEdit: () => _openProfileEditor(existing: profile),
                onDelete: () {
                  final id = profile['id'] as String?;
                  if (id != null) _deleteProfile(id);
                },
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _openAddProfileSheet,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Profile'),
            ),
          ],
          const SizedBox(height: 28),
          // ── Connection section ──────────────────────────────────────────
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
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtrl,
            decoration: const InputDecoration(
              labelText: 'Bearer token (optional)',
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            autocorrect: false,
            obscureText: true,
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          // ── Agents & Models section ────────────────────────────────────
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
              ),
          ],
          // ── Default model section ──────────────────────────────────────
          if (_models.isNotEmpty) ...[
            const SizedBox(height: 28),
            const _SectionHeader(
              title: 'Default Model',
              icon: Icons.psychology_outlined,
            ),
            const SizedBox(height: 10),
            _ModelTile(
              providerId: _providerId,
              modelId: _modelId,
              modelCount: _models.length,
              onTap: _openModelPicker,
            ),
          ],
          // ── Appearance section ─────────────────────────────────────────
          const SizedBox(height: 28),
          const _SectionHeader(
            title: 'Appearance',
            icon: Icons.palette_outlined,
          ),
          const SizedBox(height: 10),
          _ThemeSelector(
            current: ref.watch(settingsControllerProvider).themeMode,
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
  });

  final Agent agent;
  final List<ModelChoice> models;

  IconData _agentIcon(String id) => switch (id) {
        'codex' => Icons.code,
        'claude-code' => Icons.auto_awesome,
        'opencode' => Icons.terminal,
        _ => Icons.smart_toy_outlined,
      };

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
          available
              ? '${models.length} model${models.length == 1 ? '' : 's'} available'
              : 'Not installed',
          style: theme.textTheme.bodySmall?.copyWith(
            color: available ? null : theme.colorScheme.error,
          ),
        ),
        trailing: available
            ? null
            : Icon(Icons.warning_amber, color: theme.colorScheme.error),
        children: [
          if (models.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'No models loaded for this agent.',
                style: theme.textTheme.bodySmall,
              ),
            )
          else
            ...models.map(
              (m) => ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading:
                    const Icon(Icons.psychology_outlined, size: 18),
                title: Text(
                  m.modelId,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Card-style tile that shows the chosen `provider / model` and opens the picker.
class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.providerId,
    required this.modelId,
    required this.modelCount,
    required this.onTap,
  });

  final String providerId;
  final String modelId;
  final int modelCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmpty = providerId.isEmpty || modelId.isEmpty;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.psychology_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEmpty ? 'Select a model' : modelId,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isEmpty
                          ? '$modelCount models available / tap to choose'
                          : 'Provider: $providerId / $modelCount available',
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

// ═══════════════════════════════════════════════════════════════════════════════
// Profile Tile
// ═══════════════════════════════════════════════════════════════════════════════

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.profile,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> profile;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _keysSummary() {
    final keys = profile['keys'];
    if (keys is! Map<String, dynamic> || keys.isEmpty) return 'No keys';
    final parts = <String>[];
    for (final entry in keys.entries) {
      final provider = entry.key;
      final value = entry.value;
      final hasKey = value is Map<String, dynamic> &&
          (value['key'] as String? ?? '').isNotEmpty;
      if (hasKey) parts.add('$provider ✓');
    }
    return parts.isEmpty ? 'No keys' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = profile['name'] as String? ?? 'Unnamed';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: isActive ? Colors.green : Colors.transparent,
                  border: Border.all(
                    color: isActive
                        ? Colors.green
                        : theme.colorScheme.outline,
                  ),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _keysSummary(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Profile Editor Page
// ═══════════════════════════════════════════════════════════════════════════════

class _ProfileEditorPage extends StatefulWidget {
  const _ProfileEditorPage({
    required this.baseUrl,
    required this.bearerToken,
    this.existing,
  });

  final String baseUrl;
  final String bearerToken;
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
    _anthropicKeyCtrl =
        TextEditingController(text: isEdit ? '' : (anthropic['key'] as String? ?? ''));
    _anthropicBaseUrlCtrl =
        TextEditingController(text: anthropic['baseUrl'] as String? ?? '');
    _openaiKeyCtrl =
        TextEditingController(text: isEdit ? '' : (openai['key'] as String? ?? ''));
    _openaiBaseUrlCtrl =
        TextEditingController(text: openai['baseUrl'] as String? ?? '');
    _opencodeKeyCtrl =
        TextEditingController(text: isEdit ? '' : (opencode['key'] as String? ?? ''));
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
        bearerToken: widget.bearerToken,
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
