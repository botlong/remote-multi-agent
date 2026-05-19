/// Bottom-sheet directory picker that browses the gateway host's file system
/// via the gateway `/files/dirs` endpoint.
///
/// Features:
///   - Browse directories on the remote machine
///   - Create new folders (with inline rename)
///   - Select a directory as the working directory for a new session
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Shows a directory picker bottom sheet and returns the selected path,
/// or null if dismissed.
Future<String?> showDirectoryPicker(
  BuildContext context, {
  required String gatewayBaseUrl,
  required String bearerToken,
  String? initialPath,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _DirectoryPickerSheet(
      gatewayBaseUrl: gatewayBaseUrl,
      bearerToken: bearerToken,
      initialPath: initialPath ?? 'D:\\',
    ),
  );
}

class _DirectoryPickerSheet extends StatefulWidget {
  const _DirectoryPickerSheet({
    required this.gatewayBaseUrl,
    required this.bearerToken,
    required this.initialPath,
  });

  final String gatewayBaseUrl;
  final String bearerToken;
  final String initialPath;

  @override
  State<_DirectoryPickerSheet> createState() => _DirectoryPickerSheetState();
}

class _DirectoryPickerSheetState extends State<_DirectoryPickerSheet> {
  late String _currentPath;
  List<_DirEntry> _dirs = [];
  bool _loading = true;
  String? _error;
  bool _creatingFolder = false;
  final _newFolderController = TextEditingController();

  late final Dio _dio;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _dio = Dio(
      BaseOptions(
        baseUrl: widget.gatewayBaseUrl.replaceAll(RegExp(r'/$'), ''),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          if (widget.bearerToken.isNotEmpty)
            'Authorization': 'Bearer ${widget.bearerToken}',
        },
      ),
    );
    _loadDirs();
  }

  @override
  void dispose() {
    _newFolderController.dispose();
    _dio.close();
    super.dispose();
  }

  Future<void> _loadDirs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '/files/dirs',
        queryParameters: {'path': _currentPath},
      );
      final data = res.data ?? {};
      final dirs = (data['dirs'] as List<dynamic>?)
              ?.map(
                (d) => _DirEntry(
                  name: (d as Map)['name'] as String? ?? '',
                  path: d['path'] as String? ?? '',
                ),
              )
              .toList() ??
          [];
      if (!mounted) return;
      setState(() {
        _dirs = dirs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load: $e';
      });
    }
  }

  void _navigateTo(String path) {
    setState(() => _currentPath = path);
    _loadDirs();
  }

  void _goUp() {
    // Go to parent directory
    final sep = _currentPath.contains('/') ? '/' : '\\';
    final parts = _currentPath.split(RegExp(r'[/\\]'));
    if (parts.length <= 1) return;
    parts.removeLast();
    if (parts.length == 1 && parts[0].endsWith(':')) {
      // Windows drive root: "D:" → "D:\"
      _navigateTo('${parts[0]}\\');
    } else {
      _navigateTo(parts.join(sep));
    }
  }

  Future<void> _createFolder() async {
    final name = _newFolderController.text.trim();
    if (name.isEmpty) return;

    final sep = _currentPath.contains('/') ? '/' : '\\';
    final newPath = '$_currentPath$sep$name';

    setState(() => _creatingFolder = true);
    try {
      await _dio.post<dynamic>(
        '/files/mkdir',
        data: {'path': newPath},
      );
      _newFolderController.clear();
      if (!mounted) return;
      setState(() => _creatingFolder = false);
      _loadDirs();
    } catch (e) {
      if (!mounted) return;
      setState(() => _creatingFolder = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to create folder: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Choose working directory',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),

            // Current path + up button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: theme.colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    onPressed: _goUp,
                    tooltip: 'Parent directory',
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _currentPath,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // New folder row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newFolderController,
                      decoration: InputDecoration(
                        hintText: 'New folder name',
                        isDense: true,
                        prefixIcon: const Icon(
                          Icons.create_new_folder_outlined,
                          size: 20,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onSubmitted: (_) => _createFolder(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: _creatingFolder
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add, size: 20),
                    onPressed: _creatingFolder ? null : _createFolder,
                    tooltip: 'Create folder',
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Directory list
            Flexible(
              child: _buildList(theme),
            ),

            // Select button
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: const Text('Select this directory'),
                  onPressed: () => Navigator.of(context).pop(_currentPath),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              const SizedBox(height: 8),
              TextButton(onPressed: _loadDirs, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_dirs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No subdirectories',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _dirs.length,
      itemBuilder: (_, i) {
        final dir = _dirs[i];
        return ListTile(
          leading: Icon(Icons.folder, color: theme.colorScheme.primary),
          title: Text(dir.name),
          trailing: const Icon(Icons.chevron_right, size: 20),
          dense: true,
          onTap: () => _navigateTo(dir.path),
        );
      },
    );
  }
}

class _DirEntry {
  const _DirEntry({required this.name, required this.path});
  final String name;
  final String path;
}
