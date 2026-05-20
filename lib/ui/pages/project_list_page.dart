import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../state/gateway_providers.dart';
import '../../state/settings_store.dart';
import '../widgets/directory_picker.dart';
import 'gateway_ui_adapters.dart';
import 'project_detail_page.dart';
import 'search_page.dart';

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
            icon: const Icon(Icons.search),
            tooltip: 'Search messages',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const SearchPage()),
            ),
          ),
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
      return _ErrorEmpty(error: error!);
    }
    if (projects.isEmpty) {
      return const _ProjectsEmpty();
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: projects.length,
      itemBuilder: (context, index) => _ProjectCard(project: projects[index]),
    );
  }
}

class _ProjectsEmpty extends StatelessWidget {
  const _ProjectsEmpty();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 120),
      children: [
        Icon(
          Icons.folder_outlined,
          size: 48,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
        ),
        const SizedBox(height: 20),
        Text(
          'No projects yet',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 6),
        Text(
          'Add a project directory to get started.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ErrorEmpty extends StatelessWidget {
  const _ErrorEmpty({required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.cloud_off, size: 36, color: scheme.error),
        ),
        const SizedBox(height: 20),
        Text(
          'Connection failed',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          error,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.error,
              ),
        ),
        const SizedBox(height: 16),
        Text(
          'Pull to retry, or check Settings.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project});

  final GatewayProjectView project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openProject(context, project),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.folder_outlined,
                    color: scheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        project.directory,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _relativeTime(project.updatedAtMs),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
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
