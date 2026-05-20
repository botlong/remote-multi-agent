import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/part.dart';

/// Card-style render for a tool invocation: shows tool name, status,
/// and (when available) the input + output collapsed by default.
class ToolPartView extends StatefulWidget {
  const ToolPartView({super.key, required this.part});
  final ToolPart part;

  @override
  State<ToolPartView> createState() => _ToolPartViewState();
}

class _ToolPartViewState extends State<ToolPartView> {
  bool _expanded = false;

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (widget.part.status) {
      ToolStatus.pending => scheme.outline,
      ToolStatus.running => scheme.primary,
      ToolStatus.completed => Colors.green,
      ToolStatus.error => scheme.error,
    };
  }

  IconData _statusIcon() => switch (widget.part.status) {
        ToolStatus.pending => Icons.hourglass_empty,
        ToolStatus.running => Icons.sync,
        ToolStatus.completed => Icons.check_circle_outline,
        ToolStatus.error => Icons.error_outline,
      };

  /// One-line preview of what the tool is doing, drawn next to the tool name.
  /// Examples:
  ///   bash:       `git status`
  ///   read:       `lib/main.dart`
  ///   edit/write: `src/foo.ts`
  ///   glob:       `**/*.dart`
  String? _summary() {
    final raw = widget.part.input;
    if (raw is! Map) return null;
    // Cast to a concrete Map so the closure below indexes a non-null value.
    // (Dart promotion doesn't reach into nested closures reliably.)
    final input = raw as Map;

    final tool = widget.part.tool;
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = input[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    return switch (tool) {
      'bash' || 'shell' || 'execute' => pick(['command', 'cmd']),
      'read' || 'cat' => pick(['filePath', 'path', 'file']),
      'write' || 'edit' || 'patch' => pick(['filePath', 'path', 'file']),
      'glob' || 'find' => pick(['pattern', 'glob', 'query']),
      'grep' || 'search' => pick(['pattern', 'query']),
      'list' || 'ls' => pick(['path', 'directory']),
      _ => pick(['command', 'path', 'file', 'pattern', 'query']),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(context);
    final summary = _summary();

    final scheme = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.04),
        border: Border.all(color: statusColor.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          _statusIcon(),
                          size: 14,
                          color: statusColor,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.part.tool,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.part.status.name,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                  if (summary != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      summary,
                      maxLines: _expanded ? null : 2,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 0),
            if (widget.part.input != null)
              _Section(
                title: 'Input',
                child: _CodeBlock(
                  text: const JsonEncoder.withIndent('  ')
                      .convert(widget.part.input),
                ),
              ),
            if (widget.part.output != null)
              _Section(
                title: 'Output',
                child: _CodeBlock(text: _formatOutput(widget.part.output!)),
              ),
            if (widget.part.error != null)
              _Section(
                title: 'Error',
                child: _CodeBlock(
                  text: widget.part.error!,
                  color: theme.colorScheme.error,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            child,
          ],
        ),
      );
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.15),
        ),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.5,
          color: color ?? scheme.onSurface.withValues(alpha: 0.85),
        ),
      ),
    );
  }
}

String _formatOutput(Object value) {
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}
