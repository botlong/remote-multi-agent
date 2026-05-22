import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/gateway_chat_store.dart';

class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage> {
  final _scroll = ScrollController();
  bool _autoScroll = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(gatewayChatProvider(widget.sessionId));
    final lines = chatState.terminalLines;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminal'),
        actions: [
          IconButton(
            icon: Icon(_autoScroll ? Icons.vertical_align_bottom : Icons.pause),
            tooltip: _autoScroll ? 'Auto-scroll on' : 'Auto-scroll off',
            onPressed: () => setState(() => _autoScroll = !_autoScroll),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy all',
            onPressed: () {
              final text = lines.map((l) => l.text).join('');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Terminal output copied')),
              );
            },
          ),
        ],
      ),
      body: lines.isEmpty
          ? Center(
              child: Text(
                'No terminal output yet',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : _buildTerminal(lines, theme),
    );
  }

  Widget _buildTerminal(List<TerminalLine> lines, ThemeData theme) {
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
    return Container(
      color: const Color(0xFF1E1E1E),
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        itemCount: lines.length,
        itemBuilder: (_, index) {
          final line = lines[index];
          final isStderr = line.stream == 'stderr';
          return Text(
            line.text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.4,
              color: isStderr
                  ? const Color(0xFFFF6B6B)
                  : const Color(0xFFD4D4D4),
            ),
          );
        },
      ),
    );
  }
}
