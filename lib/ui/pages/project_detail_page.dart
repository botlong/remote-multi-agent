import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/gateway_providers.dart';
import '../widgets/agent_badge.dart';
import '../widgets/session_status_chip.dart';
import 'agent_group_page.dart';
import 'gateway_chat_page.dart';
import 'gateway_ui_adapters.dart';
import 'search_page.dart';

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
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search in project',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SearchPage(projectId: project.id),
              ),
            ),
          ),
        ],
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

class _ModelSection extends ConsumerWidget {
  const _ModelSection({
    required this.project,
    required this.modelId,
    required this.sessions,
  });

  final GatewayProjectView project;
  final String modelId;
  final List<GatewaySessionView> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      initiallyExpanded: true,
      title: Text(modelId == '_default' ? 'Default model' : modelId),
      children: [
        for (final session in sessions)
          Dismissible(
            key: ValueKey(session.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Theme.of(context).colorScheme.error,
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (_) => _confirmSwipeDelete(context),
            onDismissed: (_) => ref
                .read(gatewaySessionStoreProvider(project.id).notifier)
                .deleteSession(session.id),
            child: ListTile(
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
              onLongPress: () => _showSessionMenu(context, ref, session),
            ),
          ),
      ],
    );
  }

  void _showSessionMenu(
    BuildContext context,
    WidgetRef ref,
    GatewaySessionView session,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                Navigator.pop(ctx);
                _showRenameDialog(context, ref, session);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Export as Markdown'),
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final client = ref.read(gatewayClientProvider);
                  final md = await client.exportSession(session.id);
                  await Clipboard.setData(ClipboardData(text: md));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Markdown copied')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Export failed: $e')),
                    );
                  }
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Delete',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _confirmDelete(context, ref, session);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    GatewaySessionView session,
  ) {
    final controller = TextEditingController(text: session.title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename session'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'New title',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isEmpty) return;
              Navigator.pop(ctx);
              try {
                await ref
                    .read(gatewaySessionStoreProvider(project.id).notifier)
                    .renameSession(session.id, newTitle);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Rename failed: $e')),
                  );
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _confirmSwipeDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    GatewaySessionView session,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
          'This will permanently delete "${session.title}".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref
                    .read(gatewaySessionStoreProvider(project.id).notifier)
                    .deleteSession(session.id);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Delete failed: $e')),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
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
