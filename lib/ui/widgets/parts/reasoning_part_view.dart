import 'package:flutter/material.dart';

import '../../../models/part.dart';

class ReasoningPartView extends StatefulWidget {
  const ReasoningPartView({super.key, required this.part});
  final ReasoningPart part;

  @override
  State<ReasoningPartView> createState() => _ReasoningPartViewState();
}

class _ReasoningPartViewState extends State<ReasoningPartView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final charCount = widget.part.text.length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.tertiaryContainer.withValues(alpha: 0.2),
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 13,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Thinking',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.tertiary,
                    ),
                  ),
                  if (!_expanded && charCount > 0) ...[
                    const SizedBox(width: 6),
                    Text(
                      '($charCount chars)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
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
              if (_expanded) ...[
                const SizedBox(height: 6),
                Text(
                  widget.part.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
