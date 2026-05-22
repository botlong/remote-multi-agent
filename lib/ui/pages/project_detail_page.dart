import 'package:flutter/material.dart';
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
          preferredSize: const Size.fromHeight(32),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    project.directory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: _SessionTimeline(sessions: sessions, project: project),
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

class _SessionTimeline extends ConsumerWidget {
  const _SessionTimeline({
    required this.sessions,
    required this.project,
  });

  final List<GatewaySessionView> sessions;
  final GatewayProjectView project;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (sessions.isEmpty) {
      return _EmptySessionsView();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 96),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final session = sessions[index];
        return _SessionTile(
          session: session,
          project: project,
          onDelete: () => ref
              .read(gatewaySessionStoreProvider(project.id).notifier)
              .deleteSession(session.id),
          onRename: () => _showRenameDialog(context, ref, session),
        );
      },
    );
  }
}

class _EmptySessionsView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 44,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
        ),
        const SizedBox(height: 20),
        Text(
          'No conversations yet',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Start a new conversation with\nany of your coding agents.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.project,
    required this.onDelete,
    required this.onRename,
  });

  final GatewaySessionView session;
  final GatewayProjectView project;
  final VoidCallback onDelete;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey(session.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: scheme.error,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmSwipeDelete(context),
      onDismissed: (_) => onDelete(),
      child: Material(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GatewayChatPage(
                session: session,
                project: project,
              ),
            ),
          ),
          onLongPress: () => _showMenu(context),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          AgentBadge(
                            agentId: session.agentId,
                            compact: true,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _relativeTime(session.updatedAtMs),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SessionStatusChip(status: session.status, compact: true),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
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
                onRename();
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Export as Markdown'),
              onTap: () async {
                Navigator.pop(ctx);
                // handled by parent
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
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

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
              final notifier = ref.read(
                gatewaySessionStoreProvider(session.projectId).notifier,
              );
              await notifier.renameSession(session.id, newTitle);
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
