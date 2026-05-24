import 'package:flutter/material.dart';

import '../../state/gateway_chat_store.dart';

class ActivityTimeline extends StatelessWidget {
  const ActivityTimeline({
    super.key,
    required this.activities,
  });

  final List<ActivityItem> activities;

  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) return const SizedBox.shrink();
    final sorted = [...activities]
      ..sort((a, b) {
        final bySequence = a.sequence.compareTo(b.sequence);
        if (bySequence != 0) return bySequence;
        return (a.timestampMs ?? 0).compareTo(b.timestampMs ?? 0);
      });
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.35)),
          bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final activity in sorted) _ActivityRow(activity: activity),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityRow extends StatefulWidget {
  const _ActivityRow({required this.activity});

  final ActivityItem activity;

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant _ActivityRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activity.id != widget.activity.id) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final output = widget.activity.output.trimRight();
    final hasOutput = output.isNotEmpty;
    final preview = _previewOutput(output);
    final canExpand = hasOutput && preview != output;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusIcon(status: widget.activity.status),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.activity.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _StatusLabel(status: widget.activity.status),
              if (hasOutput) ...[
                const SizedBox(width: 2),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: canExpand
                      ? () => setState(() => _expanded = !_expanded)
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: canExpand
                          ? scheme.onSurfaceVariant
                          : scheme.onSurfaceVariant.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (hasOutput)
            Padding(
              padding: const EdgeInsets.only(left: 24, top: 4, bottom: 3),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  _expanded ? output : preview,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    height: 1.35,
                    color: scheme.onSurface.withValues(alpha: 0.82),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _previewOutput(String output) {
    if (output.isEmpty) return '';
    final lines = output.split('\n');
    if (lines.length <= 3) return output;
    return '${lines.take(3).join('\n')}\n...';
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});

  final ActivityStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      ActivityStatus.running => scheme.primary,
      ActivityStatus.completed => Colors.green,
      ActivityStatus.error => scheme.error,
      ActivityStatus.info => scheme.onSurfaceVariant,
    };
    if (status == ActivityStatus.running) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 1.6,
          color: color,
        ),
      );
    }
    return Icon(
      switch (status) {
        ActivityStatus.completed => Icons.check_circle_outline,
        ActivityStatus.error => Icons.error_outline,
        ActivityStatus.running => Icons.radio_button_checked,
        ActivityStatus.info => Icons.info_outline,
      },
      size: 14,
      color: color,
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final ActivityStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) {
      ActivityStatus.running => scheme.primary,
      ActivityStatus.completed => Colors.green,
      ActivityStatus.error => scheme.error,
      ActivityStatus.info => scheme.onSurfaceVariant,
    };
    return Text(
      status.name,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
    );
  }
}
