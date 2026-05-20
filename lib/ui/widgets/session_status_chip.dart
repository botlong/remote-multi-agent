import 'package:flutter/material.dart';

class SessionStatusChip extends StatelessWidget {
  const SessionStatusChip({
    super.key,
    required this.status,
    this.compact = false,
  });

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalized = status.trim().isEmpty ? 'idle' : status.trim();
    final spec = _StatusSpec.forStatus(normalized, Theme.of(context));

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: spec.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: compact ? 11 : 13, color: spec.color),
          const SizedBox(width: 4),
          Text(
            spec.label,
            style: TextStyle(
              color: spec.color,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusSpec {
  const _StatusSpec({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  static _StatusSpec forStatus(String status, ThemeData theme) {
    switch (status) {
      case 'running':
        return _StatusSpec(
          label: 'Running',
          icon: Icons.play_arrow,
          color: theme.colorScheme.primary,
        );
      case 'waiting-for-approval':
        return const _StatusSpec(
          label: 'Approval',
          icon: Icons.rule,
          color: Color(0xFF8A5B00),
        );
      case 'error':
        return _StatusSpec(
          label: 'Error',
          icon: Icons.error_outline,
          color: theme.colorScheme.error,
        );
      case 'completed':
        return const _StatusSpec(
          label: 'Done',
          icon: Icons.check_circle_outline,
          color: Color(0xFF2E7D32),
        );
      case 'idle':
      default:
        return _StatusSpec(
          label: 'Idle',
          icon: Icons.circle_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        );
    }
  }
}
