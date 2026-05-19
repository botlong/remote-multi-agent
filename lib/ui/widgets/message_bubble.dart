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
  });
  final Message message;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;

    final partWidgets = <Widget>[];
    for (final part in message.orderedParts) {
      partWidgets.add(_buildPart(part));
    }

    if (partWidgets.isEmpty && message.role == MessageRole.assistant) {
      // Stream just started — show a typing indicator.
      partWidgets.add(const _TypingIndicator());
    }

    return GestureDetector(
      onLongPress: () => _showContextMenu(context),
      child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) const _RoleAvatar(role: MessageRole.assistant),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 720),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isUser
                        ? Theme.of(context).colorScheme.primaryContainer
                        : Theme.of(context).colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isUser ? 16 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final w in partWidgets) ...[
                        w,
                        // No spacer below empty step parts
                        if (w is! StepPartView) const SizedBox(height: 4),
                      ],
                    ],
                  ),
                ),
                if (message.modelId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                    child: Text(
                      message.modelId!,
                      style: Theme.of(context).textTheme.labelSmall,
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
                Clipboard.setData(ClipboardData(text: _plainText()));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
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
    return CircleAvatar(
      radius: 14,
      backgroundColor: isUser ? scheme.primary : scheme.tertiary,
      child: Icon(
        isUser ? Icons.person_outline : Icons.smart_toy_outlined,
        size: 16,
        color: isUser ? scheme.onPrimary : scheme.onTertiary,
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _Dot(delay: Duration(milliseconds: i * 200), color: scheme.primary),
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
      builder: (_, __) => Opacity(
        opacity: 0.3 + 0.7 * _anim.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
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
