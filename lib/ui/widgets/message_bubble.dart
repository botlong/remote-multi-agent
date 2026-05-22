import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/message.dart';
import '../../models/part.dart';
import 'parts/image_part_view.dart';
import 'parts/reasoning_part_view.dart';
import 'parts/step_part_view.dart';
import 'parts/text_part_view.dart';
import 'parts/tool_part_view.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onDelete,
    this.onResend,
    this.onEditResend,
    this.onQuote,
  });
  final Message message;
  final VoidCallback? onDelete;
  final ValueChanged<String>? onResend;
  final ValueChanged<String>? onEditResend;
  final ValueChanged<String>? onQuote;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    final partWidgets = _buildPartWidgets();

    if (partWidgets.isEmpty && message.role == MessageRole.assistant) {
      partWidgets.add(const _TypingIndicator());
    }

    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPress: () => _showContextMenu(context),
      child: Padding(
        padding: EdgeInsets.only(
          top: 4,
          bottom: 4,
          left: isUser ? 40 : 0,
          right: isUser ? 0 : 40,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              const _RoleAvatar(role: MessageRole.assistant),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: const BoxConstraints(maxWidth: 720),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? scheme.primaryContainer.withValues(alpha: 0.7)
                          : scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                      border: isUser
                          ? null
                          : Border.all(
                              color: scheme.outlineVariant.withValues(alpha: 0.15),
                            ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final w in partWidgets) ...[
                          w,
                          if (w is! StepPartView &&
                              w is! ToolPartView &&
                              w is! _CollapsedToolGroup)
                            const SizedBox(height: 4),
                        ],
                      ],
                    ),
                  ),
                  if (message.modelId != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, left: 6, right: 6),
                      child: Text(
                        message.modelId!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                              fontSize: 10,
                            ),
                      ),
                    ),
                ],
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 8),
              const _RoleAvatar(role: MessageRole.user),
            ],
          ],
        ),
      ),
    );
  }

  String _plainText() {
    final buf = StringBuffer();
    for (final part in message.orderedParts) {
      switch (part) {
        case TextPart():
          buf.writeln(part.text);
        case ReasoningPart():
          buf.writeln(part.text);
        case ToolPart():
          buf.writeln('[${part.tool}] ${part.input ?? ""}');
          if (part.output != null) buf.writeln(part.output);
        default:
          break;
      }
    }
    return buf.toString().trim();
  }

  void _showContextMenu(BuildContext context) {
    HapticFeedback.lightImpact();
    final isUser = message.role == MessageRole.user;
    final text = _plainText();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Copy text'),
              onTap: () {
                Clipboard.setData(ClipboardData(text: text));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
            if (isUser && onResend != null)
              ListTile(
                leading: const Icon(Icons.replay),
                title: const Text('Resend'),
                onTap: () {
                  Navigator.pop(ctx);
                  onResend!(text);
                },
              ),
            if (isUser && onEditResend != null)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit & resend'),
                onTap: () {
                  Navigator.pop(ctx);
                  onEditResend!(text);
                },
              ),
            if (!isUser && onQuote != null)
              ListTile(
                leading: const Icon(Icons.format_quote_outlined),
                title: const Text('Quote'),
                onTap: () {
                  Navigator.pop(ctx);
                  onQuote!(text);
                },
              ),
            if (onDelete != null)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                title: Text(
                  'Delete message',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  onDelete!();
                },
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPartWidgets() {
    final parts = message.orderedParts.toList();
    final widgets = <Widget>[];
    int i = 0;

    while (i < parts.length) {
      final part = parts[i];

      // Group consecutive completed tools (3+)
      if (part is ToolPart && part.status.isTerminal) {
        int j = i;
        while (j < parts.length &&
            parts[j] is ToolPart &&
            (parts[j] as ToolPart).status.isTerminal) {
          j++;
        }
        final groupLen = j - i;
        if (groupLen >= 3) {
          final toolParts = parts.sublist(i, j).cast<ToolPart>();
          widgets.add(_CollapsedToolGroup(tools: toolParts));
          i = j;
          continue;
        }
      }

      widgets.add(_buildPart(part));
      i++;
    }

    return widgets;
  }

  Widget _buildPart(Part p) => switch (p) {
        TextPart() => TextPartView(part: p),
        ReasoningPart() => ReasoningPartView(part: p),
        ToolPart() => ToolPartView(part: p),
        ImagePart() => ImagePartView(part: p),
        FilePart() => _FilePartView(part: p),
        StepStartPart() => const StepPartView(start: true),
        StepFinishPart() => const StepPartView(start: false),
        UnknownPart() => _UnknownPartView(part: p),
      };
}

class _RoleAvatar extends StatelessWidget {
  const _RoleAvatar({required this.role});
  final MessageRole role;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = role == MessageRole.user;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: isUser
            ? scheme.primary.withValues(alpha: 0.1)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        isUser ? Icons.person : Icons.auto_awesome,
        size: 14,
        color: isUser ? scheme.primary : scheme.onSurfaceVariant,
      ),
    );
  }
}

class _CollapsedToolGroup extends StatefulWidget {
  const _CollapsedToolGroup({required this.tools});
  final List<ToolPart> tools;

  @override
  State<_CollapsedToolGroup> createState() => _CollapsedToolGroupState();
}

class _CollapsedToolGroupState extends State<_CollapsedToolGroup> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final errorCount = widget.tools.where((t) => t.status == ToolStatus.error).length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.2),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    size: 14,
                    color: errorCount > 0 ? scheme.error : Colors.green,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${widget.tools.length} operations completed',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (errorCount > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '($errorCount failed)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: scheme.error,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(
              height: 0,
              color: scheme.outlineVariant.withValues(alpha: 0.2),
            ),
            Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  for (final tool in widget.tools)
                    ToolPartView(part: tool),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            _Dot(
              delay: Duration(milliseconds: i * 180),
              color: scheme.primary.withValues(alpha: 0.7),
            ),
          ],
        ],
      ),
    );
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.delay, required this.color});
  final Duration delay;
  final Color color;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _anim = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Transform.translate(
        offset: Offset(0, -2 * _anim.value),
        child: Opacity(
          opacity: 0.35 + 0.65 * _anim.value,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: widget.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders a file attachment as a compact card.
class _FilePartView extends StatelessWidget {
  const _FilePartView({required this.part});
  final FilePart part;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconForMime(part.mimeType),
            size: 28,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  part.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  part.mimeType,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForMime(String mime) {
    if (mime.startsWith('image/')) return Icons.image;
    if (mime.startsWith('video/')) return Icons.videocam;
    if (mime.startsWith('audio/')) return Icons.audiotrack;
    if (mime.contains('pdf')) return Icons.picture_as_pdf;
    if (mime.contains('zip') || mime.contains('tar') || mime.contains('gz')) {
      return Icons.folder_zip;
    }
    if (mime.startsWith('text/')) return Icons.description;
    return Icons.insert_drive_file;
  }
}

class _UnknownPartView extends StatelessWidget {
  const _UnknownPartView({required this.part});
  final UnknownPart part;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'Unknown part: ${part.rawType}',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      );
}
