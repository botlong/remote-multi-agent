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
    final scheme = theme.colorScheme;
    final spec = _AgentSpec.forId(agentId);
    final text = label?.trim().isNotEmpty == true ? label!.trim() : spec.label;
    final fg = scheme.onSurface;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(spec.icon, size: compact ? 13 : 15, color: fg),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
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
  const _AgentSpec({required this.label, required this.icon});

  final String label;
  final IconData icon;

  static _AgentSpec forId(String id) {
    return switch (id) {
      'codex' => const _AgentSpec(label: 'Codex', icon: Icons.terminal),
      'claude-code' => const _AgentSpec(label: 'Claude Code', icon: Icons.auto_awesome),
      'opencode' => const _AgentSpec(label: 'OpenCode', icon: Icons.code),
      _ => const _AgentSpec(label: 'Agent', icon: Icons.smart_toy_outlined),
    };
  }
}
