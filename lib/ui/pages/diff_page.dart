import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/gateway_providers.dart';

/// Displays git diff output for a session's working directory.
class DiffPage extends ConsumerStatefulWidget {
  const DiffPage({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<DiffPage> createState() => _DiffPageState();
}

class _DiffPageState extends ConsumerState<DiffPage> {
  String? _diff;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDiff();
  }

  Future<void> _loadDiff() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(gatewayClientProvider);
      final result = await client.getSessionDiff(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _diff = result['diff'] as String? ?? '';
        _error = result['error'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Git Diff'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadDiff,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && (_diff == null || _diff!.isEmpty)
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                )
              : _diff != null && _diff!.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No uncommitted changes',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                    )
                  : _DiffView(diff: _diff!),
    );
  }
}

class _DiffView extends StatelessWidget {
  const _DiffView({required this.diff});
  final String diff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = diff.split('\n');
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final (bg, fg) = _lineColors(line, theme);
        return Container(
          width: double.infinity,
          color: bg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          child: Text(
            line,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: fg,
              height: 1.4,
            ),
          ),
        );
      },
    );
  }

  (Color?, Color) _lineColors(String line, ThemeData theme) {
    if (line.startsWith('+++') || line.startsWith('---')) {
      return (null, theme.colorScheme.onSurfaceVariant);
    }
    if (line.startsWith('+')) {
      return (
        const Color(0x2200AA00),
        theme.brightness == Brightness.dark
            ? const Color(0xFF66FF66)
            : const Color(0xFF006600),
      );
    }
    if (line.startsWith('-')) {
      return (
        const Color(0x22FF0000),
        theme.brightness == Brightness.dark
            ? const Color(0xFFFF6666)
            : const Color(0xFFAA0000),
      );
    }
    if (line.startsWith('@@')) {
      return (
        const Color(0x220066FF),
        theme.colorScheme.primary,
      );
    }
    if (line.startsWith('diff ')) {
      return (null, theme.colorScheme.primary);
    }
    return (null, theme.colorScheme.onSurface);
  }
}
