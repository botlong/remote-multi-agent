import 'package:flutter/material.dart';

import '../../../models/part.dart';

/// Collapsible "reasoning trace" view. Mirrors how OpenCode TUI / Claude
/// Console show internal thinking — collapsed by default, click to expand.
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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.tertiaryContainer.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 14,
                    color: scheme.tertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Thinking',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.tertiary,
                      ),
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
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
