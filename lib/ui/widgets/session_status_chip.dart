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
          if (normalized == 'running')
            _PulsingDot(color: spec.color, size: compact ? 8 : 10)
          else
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

/// Animated pulsing dot for running state.
class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _anim = Tween(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
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
      builder: (_, __) => Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: _anim.value),
          shape: BoxShape.circle,
        ),
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
    return switch (status) {
      'running' => _StatusSpec(
          label: 'Running',
          icon: Icons.play_arrow,
          color: theme.colorScheme.onSurface,
        ),
      'waiting-for-approval' => _StatusSpec(
          label: 'Approval',
          icon: Icons.rule,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      'error' => _StatusSpec(
          label: 'Error',
          icon: Icons.error_outline,
          color: theme.colorScheme.error,
        ),
      'completed' => const _StatusSpec(
          label: 'Done',
          icon: Icons.check_circle_outline,
          color: Color(0xFF4CAF50),
        ),
      _ => _StatusSpec(
          label: 'Idle',
          icon: Icons.circle_outlined,
          color: theme.colorScheme.onSurfaceVariant,
        ),
    };
  }
}
