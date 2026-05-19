import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/codex_thread_store.dart';
import '../../state/settings_store.dart';
import '../widgets/directory_picker.dart';
import 'codex_chat_page.dart';

class CodexThreadListPage extends ConsumerWidget {
  const CodexThreadListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(codexThreadListProvider);
    final settings = ref.watch(settingsControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Codex'),
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              'QQBot relay: ${Uri.parse(settings.baseUrl).host}:8787',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
      body: state.items.isEmpty
          ? _buildEmpty(context)
          : ListView.separated(
              itemCount: state.items.length,
              separatorBuilder: (_, __) => const Divider(height: 0),
              itemBuilder: (_, i) => _ThreadTile(thread: state.items[i]),
            ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New thread'),
        onPressed: () => _create(context, ref),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.terminal, size: 48),
              const SizedBox(height: 12),
              Text(
                'No threads yet — tap "New thread" to start.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsControllerProvider);
    final qqbotUrl =
        'http://${Uri.parse(settings.baseUrl).host}:8787';
    final dir = await showDirectoryPicker(
      context,
      qqbotBaseUrl: qqbotUrl,
      bearerToken: settings.bearerToken,
      initialPath: 'D:\\',
    );
    if (dir == null || !context.mounted) return;

    final ctrl = ref.read(codexThreadListProvider.notifier);
    final t = await ctrl.create(
      directory: dir,
      initialTitle: _shortDirName(dir),
    );
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CodexChatPage(localKey: t.localKey),
      ),
    );
  }

  static String _shortDirName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.where((p) => p.isNotEmpty).lastOrNull ?? path;
  }
}

class _ThreadTile extends ConsumerWidget {
  const _ThreadTile({required this.thread});
  final CodexThread thread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(
        thread.title.isEmpty ? '(untitled)' : thread.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${thread.directory}\n${_relativeTime(thread.updatedAtMs)}'
        '${thread.threadId == null ? " · not started" : ""}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CodexChatPage(localKey: thread.localKey),
        ),
      ),
      onLongPress: () => _showContextMenu(context, ref),
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref) {
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
                _showRenameDialog(context, ref);
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
                _confirmDelete(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController(text: thread.title);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename thread'),
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
              await ref
                  .read(codexThreadListProvider.notifier)
                  .rename(thread.localKey, newTitle);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete thread?'),
        content: Text(
          'This will remove "${thread.title.isEmpty ? "(untitled)" : thread.title}" '
          'from this device. The codex session file on the host stays put.',
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
              await ref
                  .read(codexThreadListProvider.notifier)
                  .delete(thread.localKey);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

String _relativeTime(int ms) {
  if (ms == 0) return '';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.yMd().format(dt);
}

extension _Iterable<E> on Iterable<E> {
  E? get lastOrNull {
    E? last;
    for (final e in this) {
      last = e;
    }
    return last;
  }
}
