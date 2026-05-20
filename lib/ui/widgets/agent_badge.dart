import 'package:flutter/material.dart';

class AgentBadge extends StatelessWidget {
  const AgentBadge({
    super.key,
    required this.agentId,
    this.label,
    this.compact = false,
  });

  final String agentId;
  final String? label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spec = _AgentSpec.forId(agentId);
    final text = label?.trim().isNotEmpty == true ? label!.trim() : spec.label;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: spec.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: spec.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: compact ? 13 : 15, color: spec.color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: spec.color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentSpec {
  const _AgentSpec({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  static _AgentSpec forId(String id) {
    switch (id) {
      case 'codex':
        return const _AgentSpec(
          label: 'Codex',
          icon: Icons.terminal,
          color: Color(0xFF2E7D32),
        );
      case 'claude-code':
        return const _AgentSpec(
          label: 'Claude Code',
          icon: Icons.auto_awesome,
          color: Color(0xFFB05A2A),
        );
      case 'opencode':
        return const _AgentSpec(
          label: 'OpenCode',
          icon: Icons.code,
          color: Color(0xFF1565C0),
        );
      default:
        return const _AgentSpec(
          label: 'Agent',
          icon: Icons.smart_toy_outlined,
          color: Color(0xFF546E7A),
        );
    }
  }
}
