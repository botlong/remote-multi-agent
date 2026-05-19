import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/gateway_providers.dart';
import '../../state/settings_store.dart';
import '../widgets/directory_picker.dart';
import 'gateway_ui_adapters.dart';
import 'project_detail_page.dart';

class ProjectListPage extends ConsumerWidget {
  const ProjectListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(projectStoreProvider);
    final projects = readProjects(state);
    final loading = readLoading(state);
    final error = readError(state);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh projects',
            onPressed: () => _refresh(ref),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => _refresh(ref),
        child: _ProjectListBody(
          projects: projects,
          loading: loading,
          error: error,
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.create_new_folder_outlined),
        label: const Text('Add project'),
        onPressed: () => _addProject(context, ref),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    final notifier = ref.read(projectStoreProvider.notifier);
    await notifier.refresh();
  }

  Future<void> _addProject(BuildContext context, WidgetRef ref) async {
    final settings = ref.read(settingsControllerProvider);
    final directory = await showDirectoryPicker(
      context,
      gatewayBaseUrl: settings.baseUrl,
      bearerToken: settings.bearerToken,
      initialPath: 'D:\\',
    );
    if (directory == null || !context.mounted) return;

    try {
      final notifier = ref.read(projectStoreProvider.notifier);
      final created = await notifier.addProject(directory);
      if (!context.mounted) return;
      final project = readProject(created);
      if (project.id.isNotEmpty) {
        _openProject(context, project);
      }
    } catch (err) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add project: $err')),
      );
    }
  }
}

class _ProjectListBody extends StatelessWidget {
  const _ProjectListBody({
    required this.projects,
    required this.loading,
    required this.error,
  });

  final List<GatewayProjectView> projects;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    if (loading && projects.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && projects.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Projects unavailable',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      );
    }
    if (projects.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Icon(
            Icons.folder_open,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No projects yet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: projects.length,
      separatorBuilder: (_, __) => const Divider(height: 0),
      itemBuilder: (context, index) => _ProjectTile(project: projects[index]),
    );
  }
}

class _ProjectTile extends StatelessWidget {
  const _ProjectTile({required this.project});

  final GatewayProjectView project;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        child: const Icon(Icons.folder_outlined),
      ),
      title: Text(
        project.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${project.directory}\n${_relativeTime(project.updatedAtMs)}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _openProject(context, project),
    );
  }
}

void _openProject(BuildContext context, GatewayProjectView project) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ProjectDetailPage(project: project),
    ),
  );
}

String _relativeTime(int ms) {
  if (ms == 0) return 'not synced';
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return DateFormat.yMd().format(dt);
}
