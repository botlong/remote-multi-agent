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

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: statusColor.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(_statusIcon(), size: 16, color: statusColor),
                      const SizedBox(width: 8),
                      Text(
                        widget.part.tool,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.part.status.name,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: statusColor),
                      ),
                      const Spacer(),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                    ],
                  ),
                  if (summary != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      summary,
                      maxLines: _expanded ? null : 2,
                      overflow: _expanded ? null : TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        color: theme.colorScheme.onSurfaceVariant,
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
                  text: const JsonEncoder.withIndent('  ').convert(widget.part.input),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: color,
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
