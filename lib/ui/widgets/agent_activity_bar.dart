import 'package:flutter/material.dart';

import '../../state/gateway_chat_store.dart';

class AgentActivityBar extends StatelessWidget {
  const AgentActivityBar({super.key, required this.activeTool});
  final ActiveTool activeTool;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final toolName = activeTool.name.toLowerCase();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const _ActivitySpinner(),
          const SizedBox(width: 10),
          Icon(
            _iconForTool(toolName),
            size: 14,
            color: scheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _labelForTool(toolName),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (activeTool.info != null) ...[
                    const TextSpan(text: '  '),
                    TextSpan(
                      text: activeTool.info!,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _labelForTool(String tool) {
    if (_isShell(tool)) return 'Running command';
    if (_isRead(tool)) return 'Reading file';
    if (_isWrite(tool)) return 'Writing file';
    if (_isEdit(tool)) return 'Editing file';
    if (_isSearch(tool)) return 'Searching';
    if (_isWeb(tool)) return 'Fetching';
    return 'Running $tool';
  }

  IconData _iconForTool(String tool) {
    if (_isShell(tool)) return Icons.terminal_rounded;
    if (_isRead(tool)) return Icons.description_outlined;
    if (_isWrite(tool)) return Icons.edit_note_rounded;
    if (_isEdit(tool)) return Icons.compare_rounded;
    if (_isSearch(tool)) return Icons.search_rounded;
    if (_isWeb(tool)) return Icons.language_rounded;
    return Icons.extension_outlined;
  }

  bool _isShell(String t) =>
      t.contains('bash') || t.contains('shell') ||
      t.contains('execute') || t.contains('command') ||
      t.contains('terminal');

  bool _isRead(String t) =>
      t.contains('read') || t == 'cat' || t.contains('view');

  bool _isWrite(String t) =>
      t.contains('write') || t.contains('create') || t.contains('save');

  bool _isEdit(String t) =>
      t.contains('edit') || t.contains('patch') ||
      t.contains('replace') || t.contains('multi_edit');

  bool _isSearch(String t) =>
      t.contains('grep') || t.contains('search') ||
      t.contains('find') || t.contains('glob') || t == 'ls';

  bool _isWeb(String t) =>
      t.contains('web') || t.contains('fetch') || t.contains('http');
}

class _ActivitySpinner extends StatelessWidget {
  const _ActivitySpinner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 12,
      height: 12,
      child: CircularProgressIndicator(
        strokeWidth: 1.5,
        color: scheme.primary,
      ),
    );
  }
}
