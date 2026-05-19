import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/gateway_providers.dart';
import '../widgets/agent_badge.dart';
import '../widgets/session_status_chip.dart';
import 'agent_group_page.dart';
import 'gateway_chat_page.dart';
import 'gateway_ui_adapters.dart';

class ProjectDetailPage extends ConsumerWidget {
  const ProjectDetailPage({
    super.key,
    required this.project,
  });

  final GatewayProjectView project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(gatewaySessionListProvider(project.id));
    final sessions = readSessions(state);
    final grouped = _groupSessions(sessions);

    return Scaffold(
      appBar: AppBar(
        title: Text(project.name),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                project.directory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: _SessionGroups(grouped: grouped, project: project),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New conversation'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AgentGroupPage(project: project),
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    final notifier = ref.read(gatewaySessionListProvider(project.id).notifier);
    await notifier.refresh();
  }
}

class _SessionGroups extends StatelessWidget {
  const _SessionGroups({
    required this.grouped,
    required this.project,
  });

  final Map<String, Map<String, List<GatewaySessionView>>> grouped;
  final GatewayProjectView project;

  @override
  Widget build(BuildContext context) {
    if (grouped.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No conversations in this project.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      );
    }

    final agents = grouped.keys.toList()..sort();
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: agents.length,
      itemBuilder: (context, agentIndex) {
        final agentId = agents[agentIndex];
        final models = grouped[agentId]!;
        return _AgentSection(
          project: project,
          agentId: agentId,
          modelGroups: models,
        );
      },
    );
  }
}

class _AgentSection extends StatelessWidget {
  const _AgentSection({
    required this.project,
    required this.agentId,
    required this.modelGroups,
  });

  final GatewayProjectView project;
  final String agentId;
  final Map<String, List<GatewaySessionView>> modelGroups;

  @override
  Widget build(BuildContext context) {
    final modelIds = modelGroups.keys.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AgentBadge(agentId: agentId),
          const SizedBox(height: 8),
          for (final modelId in modelIds)
            _ModelSection(
              project: project,
              modelId: modelId,
              sessions: modelGroups[modelId]!,
            ),
        ],
      ),
    );
  }
}

class _ModelSection extends StatelessWidget {
  const _ModelSection({
    required this.project,
    required this.modelId,
    required this.sessions,
  });

  final GatewayProjectView project;
  final String modelId;
  final List<GatewaySessionView> sessions;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: true,
      title: Text(modelId == '_default' ? 'Default model' : modelId),
      children: [
        for (final session in sessions)
          ListTile(
            contentPadding: const EdgeInsets.only(left: 8, right: 0),
            title: Text(
              session.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(_relativeTime(session.updatedAtMs)),
            trailing: SessionStatusChip(status: session.status, compact: true),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GatewayChatPage(
                  session: session,
                  project: project,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Map<String, Map<String, List<GatewaySessionView>>> _groupSessions(
  List<GatewaySessionView> sessions,
) {
  final grouped = <String, Map<String, List<GatewaySessionView>>>{};
  for (final session in sessions) {
    final models = grouped.putIfAbsent(session.agentId, () => {});
    final modelId =
        session.modelId?.isNotEmpty == true ? session.modelId! : '_default';
    models.putIfAbsent(modelId, () => []).add(session);
  }
  return grouped;
}

String _relativeTime(int ms) {
  if (ms == 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.yMd().format(dt);
}
