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
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Thinking',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (_expanded) ...[
                const SizedBox(height: 6),
                Text(
                  widget.part.text,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
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
