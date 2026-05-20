import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/part.dart';

/// Card-style render for a tool invocation with agent-aware detail rendering.
///
/// - **bash/shell**: shows command inline, output as terminal block
/// - **read/cat**: shows file path, content preview
/// - **write/edit/patch**: shows file path, diff-style content
/// - **grep/search**: shows pattern, matched results
/// - **Other tools**: generic input/output JSON view
///
/// Running tools auto-expand, completed tools stay collapsed.
class ToolPartView extends StatefulWidget {
  const ToolPartView({super.key, required this.part});
  final ToolPart part;

  @override
  State<ToolPartView> createState() => _ToolPartViewState();
}

class _ToolPartViewState extends State<ToolPartView> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = !widget.part.status.isTerminal;
  }

  @override
  void didUpdateWidget(ToolPartView old) {
    super.didUpdateWidget(old);
    // Auto-collapse when tool finishes
    if (!old.part.status.isTerminal && widget.part.status.isTerminal) {
      setState(() => _expanded = false);
    }
    // Auto-expand when tool starts running
    if (old.part.status == ToolStatus.pending &&
        widget.part.status == ToolStatus.running) {
      setState(() => _expanded = true);
    }
  }

  // ─── Tool category helpers ──────────────────────────────────────────

  _ToolCategory get _category {
    final t = widget.part.tool.toLowerCase();
    if (t.contains('bash') || t.contains('shell') || t.contains('execute') ||
        t.contains('command') || t.contains('terminal')) {
      return _ToolCategory.shell;
    }
    if (t.contains('read') || t == 'cat' || t.contains('view')) {
      return _ToolCategory.read;
    }
    if (t.contains('write') || t.contains('create') || t.contains('save')) {
      return _ToolCategory.write;
    }
    if (t.contains('edit') || t.contains('patch') || t.contains('replace') ||
        t.contains('update') || t.contains('multi_edit')) {
      return _ToolCategory.edit;
    }
    if (t.contains('grep') || t.contains('search') || t.contains('find') ||
        t.contains('glob') || t.contains('list') || t == 'ls') {
      return _ToolCategory.search;
    }
    return _ToolCategory.other;
  }

  IconData get _toolIcon => switch (_category) {
        _ToolCategory.shell => Icons.terminal_rounded,
        _ToolCategory.read => Icons.description_outlined,
        _ToolCategory.write => Icons.edit_note_rounded,
        _ToolCategory.edit => Icons.compare_rounded,
        _ToolCategory.search => Icons.search_rounded,
        _ToolCategory.other => Icons.extension_outlined,
      };

  Color _statusColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (widget.part.status) {
      ToolStatus.pending => scheme.outline,
      ToolStatus.running => scheme.onSurface,
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

  // ─── Input field extraction ────────────────────────────────────────

  Map<String, dynamic> get _input {
    final raw = widget.part.input;
    if (raw is Map<String, dynamic>) return raw;
    return const {};
  }

  String? _pick(List<String> keys) {
    for (final k in keys) {
      final v = _input[k];
      if (v is String && v.isNotEmpty) return v;
    }
    return null;
  }

  /// Primary summary line (file path or command).
  String? get _primaryInfo => switch (_category) {
        _ToolCategory.shell => _pick(['command', 'cmd']),
        _ToolCategory.read => _pick(['filePath', 'path', 'file', 'file_path']),
        _ToolCategory.write =>
          _pick(['filePath', 'path', 'file', 'file_path']),
        _ToolCategory.edit =>
          _pick(['filePath', 'path', 'file', 'file_path']),
        _ToolCategory.search =>
          _pick(['pattern', 'query', 'glob', 'path', 'regex']),
        _ToolCategory.other =>
          _pick(['command', 'path', 'file', 'pattern', 'query', 'url']),
      };

  /// Secondary detail (e.g. content for write, or search path).
  String? get _secondaryInfo => switch (_category) {
        _ToolCategory.shell => null,
        _ToolCategory.read => null,
        _ToolCategory.write => _pick(['content', 'text', 'data']),
        _ToolCategory.edit =>
          _pick(['new_string', 'newText', 'content', 'replacement']),
        _ToolCategory.search =>
          _pick(['path', 'directory', 'searchPath', 'SearchPath']),
        _ToolCategory.other => null,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final statusColor = _statusColor(context);
    final primary = _primaryInfo;
    final output = widget.part.output;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(
          color: widget.part.status == ToolStatus.running
              ? statusColor.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(_toolIcon, size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: widget.part.tool,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        if (primary != null) ...[
                          const TextSpan(text: '  '),
                          TextSpan(
                            text: _truncate(primary, 60),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  _StatusBadge(
                    status: widget.part.status,
                    color: statusColor,
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded detail ──
          if (_expanded) ...[
            Divider(
              height: 0,
              color: scheme.outlineVariant.withValues(alpha: 0.2),
            ),
            _buildDetail(context, scheme, theme),
          ],
        ],
      ),
    );
  }

  Widget _buildDetail(
    BuildContext context,
    ColorScheme scheme,
    ThemeData theme,
  ) {
    final output = widget.part.output;
    final error = widget.part.error;
    final secondary = _secondaryInfo;

    if (_category == _ToolCategory.shell) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_primaryInfo != null)
              _TerminalBlock(command: _primaryInfo!, output: _fmtOutput(output)),
            if (error != null) ...[
              const SizedBox(height: 6),
              _CodeBlock(text: error, label: 'Error', color: scheme.error),
            ],
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File path for read/write/edit/search
          if (_primaryInfo != null && _category != _ToolCategory.other) ...[
            _FilePathRow(path: _primaryInfo!),
            const SizedBox(height: 6),
          ],

          // Write/edit content preview
          if (secondary != null)
            _CodeBlock(
              text: _truncate(secondary, 2000),
              label: _category == _ToolCategory.edit ? 'Changes' : 'Content',
            ),

          // Generic input for "other" tools
          if (_category == _ToolCategory.other &&
              widget.part.input != null &&
              _input.isNotEmpty)
            _CodeBlock(
              text: const JsonEncoder.withIndent('  ')
                  .convert(widget.part.input),
              label: 'Input',
            ),

          // Output
          if (output != null) ...[
            const SizedBox(height: 6),
            _CodeBlock(text: _fmtOutput(output), label: 'Output'),
          ],

          // Error (always show)
          if (error != null) ...[
            const SizedBox(height: 6),
            _CodeBlock(text: error, label: 'Error', color: scheme.error),
          ],
        ],
      ),
    );
  }
}

// ─── Tool category enum ──────────────────────────────────────────────

enum _ToolCategory { shell, read, write, edit, search, other }

// ─── Sub-widgets ─────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.color});
  final ToolStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == ToolStatus.running)
            Padding(
              padding: const EdgeInsets.only(right: 3),
              child: SizedBox(
                width: 8,
                height: 8,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: color,
                ),
              ),
            ),
          Text(
            status.name,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _FilePathRow extends StatelessWidget {
  const _FilePathRow({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final parts = path.split(RegExp(r'[/\\]'));
    final fileName = parts.isNotEmpty ? parts.last : path;
    final dir = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') + '/' : '';

    return Row(
      children: [
        Icon(Icons.insert_drive_file_outlined,
            size: 12, color: scheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              if (dir.isNotEmpty)
                TextSpan(
                  text: dir,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
              TextSpan(
                text: fileName,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ]),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TerminalBlock extends StatelessWidget {
  const _TerminalBlock({required this.command, this.output});
  final String command;
  final String? output;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Command line with $ prefix
          SelectableText.rich(
            TextSpan(children: [
              const TextSpan(
                text: '\$ ',
                style: TextStyle(
                  color: Colors.green,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(
                text: command,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ]),
          ),
          // Output
          if (output != null && output!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: SelectableText(
                  output!,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    height: 1.4,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text, this.color, this.label});
  final String text;
  final Color? color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(maxHeight: 200),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.15),
            ),
          ),
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                height: 1.5,
                color: color ?? scheme.onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _fmtOutput(Object? value) {
  if (value == null) return '';
  if (value is String) return value;
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

String _truncate(String text, int max) =>
    text.length > max ? '${text.substring(0, max)}…' : text;
