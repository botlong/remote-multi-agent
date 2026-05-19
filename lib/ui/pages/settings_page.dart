import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/gateway_client.dart';
import '../../state/settings_store.dart';
import '../widgets/model_picker.dart';
import 'home_page.dart';

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
  bool _testing = false;
  String? _testError;
  bool? _testOk;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsControllerProvider);
    _baseUrlCtrl = TextEditingController(text: s.baseUrl);
    _tokenCtrl = TextEditingController(text: s.bearerToken);
    _providerId = s.providerId;
    _modelId = s.modelId;
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _testAndLoadModels() async {
    setState(() {
      _testing = true;
      _testError = null;
      _testOk = null;
    });
    try {
      final client = GatewayClient(
        baseUrl: Uri.parse(_baseUrlCtrl.text.trim()),
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
      for (final agent in agents) {
        if (!agent.supportsModels) continue;
        final agentModels = await client.listAgentModels(agent.id);
        models.addAll(
          agentModels.map(
            (model) => (
              providerId: agent.id,
              modelId: model.id,
              label: '${agent.displayName} / ${model.displayName}',
            ),
          ),
        );
      }
      client.close();
      if (!mounted) return;
      setState(() {
        _models = models;
        _testOk = true;
        // If the current selection is no longer offered, drop to the first.
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
    await controller.update(
      AppSettings(
        baseUrl: _baseUrlCtrl.text.trim(),
        bearerToken: _tokenCtrl.text.trim(),
        providerId: _providerId,
        modelId: _modelId,
      ),
    );
    if (!mounted) return;
    if (widget.firstRun) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomePage()),
      );
    } else {
      // When embedded in the Settings tab, just show a confirmation.
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
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Connect to your agent gateway',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _baseUrlCtrl,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'http://100.x.x.x:4096',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _tokenCtrl,
            decoration: const InputDecoration(
              labelText: 'Bearer token (optional)',
              prefixIcon: Icon(Icons.lock_outline),
            ),
            autocorrect: false,
            obscureText: true,
          ),
          const SizedBox(height: 16),
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
                    : const Icon(Icons.bolt_outlined),
                label: Text(_testing ? 'Testing...' : 'Test & load models'),
              ),
              const SizedBox(width: 12),
              if (_testOk == true)
                const Icon(Icons.check_circle, color: Colors.green),
              if (_testOk == false)
                Tooltip(
                  message: _testError ?? '',
                  child: const Icon(Icons.error, color: Colors.red),
                ),
            ],
          ),
          if (_testError != null) ...[
            const SizedBox(height: 8),
            Text(
              _testError!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ],
          if (_models.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Default model', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            _ModelTile(
              providerId: _providerId,
              modelId: _modelId,
              modelCount: _models.length,
              onTap: _openModelPicker,
            ),
          ],
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
