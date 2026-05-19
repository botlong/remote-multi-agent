/// Git tab page — shows git status and diff for the current session's
/// working directory, with action buttons for commit/pull/push.
///
/// Connects to the QQBot server's `/git/*` endpoints.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/git_client.dart';
import '../../state/codex_thread_store.dart';
import '../../state/settings_store.dart';

// ---------------------------------------------------------------------------
// Provider for GitClient — uses QQBot server URL from settings.
// For now we derive it: same host as OpenCode but port 8787.
// TODO: add a dedicated qqBotUrl field to AppSettings when needed.
// ---------------------------------------------------------------------------

final _qqBotUrlProvider = Provider<String>((ref) {
  final s = ref.watch(settingsControllerProvider);
  // Default QQBot server: same host, port 8787
  final openCodeUri = Uri.parse(s.baseUrl);
  return 'http://${openCodeUri.host}:8787';
});

final gitClientProvider = Provider<GitClient>((ref) {
  final url = ref.watch(_qqBotUrlProvider);
  final s = ref.watch(settingsControllerProvider);
  final client = GitClient(
    baseUrl: Uri.parse(url),
    bearerToken: s.bearerToken,
  );
  ref.onDispose(client.close);
  return client;
});

// ---------------------------------------------------------------------------
// Git Page
// ---------------------------------------------------------------------------

class GitPage extends ConsumerStatefulWidget {
  const GitPage({super.key, this.sessionId});

  /// If provided, we look up the session's directory. Otherwise we use the
  /// first (most recent) session's directory.
  final String? sessionId;

  @override
  ConsumerState<GitPage> createState() => _GitPageState();
}

class _GitPageState extends ConsumerState<GitPage> {
  String _statusOutput = '';
  String _diffOutput = '';
  bool _loading = false;
  String? _error;
  String? _actionResult;

  String get _directory {
    final threads = ref.read(codexThreadListProvider).items;
    if (widget.sessionId != null) {
      final match = threads.where((t) => t.localKey == widget.sessionId);
      if (match.isNotEmpty) return match.first.directory;
    }
    if (threads.isNotEmpty) return threads.first.directory;
    return '';
  }

  @override
  void initState() {
    super.initState();
    // Delay so ref is available
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final dir = _directory;
    if (dir.isEmpty) {
      setState(() => _error = 'No session directory available.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _actionResult = null;
    });

    try {
      final git = ref.read(gitClientProvider);
      final results = await Future.wait([
        git.status(dir),
        git.diff(dir),
      ]);
      if (!mounted) return;
      setState(() {
        _statusOutput = results[0];
        _diffOutput = results[1];
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message ?? 'Network error';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _commitAll() async {
    final dir = _directory;
    if (dir.isEmpty) return;

    final message = await _showCommitDialog();
    if (message == null || message.trim().isEmpty) return;

    setState(() {
      _loading = true;
      _actionResult = null;
    });
    try {
      final git = ref.read(gitClientProvider);
      final result = await git.commit(dir, message.trim());
      if (!mounted) return;
      setState(() {
        _actionResult = result;
        _loading = false;
      });
      _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _pull() async {
    final dir = _directory;
    if (dir.isEmpty) return;

    setState(() {
      _loading = true;
      _actionResult = null;
    });
    try {
      final git = ref.read(gitClientProvider);
      final result = await git.pull(dir);
      if (!mounted) return;
      setState(() {
        _actionResult = result;
        _loading = false;
      });
      _refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _push() async {
    final dir = _directory;
    if (dir.isEmpty) return;

    setState(() {
      _loading = true;
      _actionResult = null;
    });
    try {
      final git = ref.read(gitClientProvider);
      final result = await git.push(dir);
      if (!mounted) return;
      setState(() {
        _actionResult = result;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<String?> _showCommitDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Commit Message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Describe your changes…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Commit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final dir = _directory;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Git'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Directory header
          _DirectoryHeader(directory: dir),

          // Action buttons
          _ActionBar(
            loading: _loading,
            onCommit: _commitAll,
            onPull: _pull,
            onPush: _push,
          ),

          // Loading indicator
          if (_loading) const LinearProgressIndicator(),

          // Error banner
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: colorScheme.errorContainer,
              child: Text(
                _error!,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),

          // Action result banner
          if (_actionResult != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: colorScheme.primaryContainer,
              child: Text(
                _actionResult!,
                style: TextStyle(color: colorScheme.onPrimaryContainer),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // Content
          Expanded(
            child: _loading && _statusOutput.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Git Status section
                      _StatusCard(statusOutput: _statusOutput),
                      const SizedBox(height: 16),
                      // Git Diff section
                      _DiffCard(diffOutput: _diffOutput),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _DirectoryHeader extends StatelessWidget {
  const _DirectoryHeader({required this.directory});
  final String directory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              directory.isEmpty ? 'No directory' : directory,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.loading,
    required this.onCommit,
    required this.onPull,
    required this.onPush,
  });

  final bool loading;
  final VoidCallback onCommit;
  final VoidCallback onPull;
  final VoidCallback onPush;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _ActionChip(
            icon: Icons.check_circle_outline,
            label: 'Commit All',
            onPressed: loading ? null : onCommit,
          ),
          const SizedBox(width: 8),
          _ActionChip(
            icon: Icons.download_outlined,
            label: 'Pull',
            onPressed: loading ? null : onPull,
          ),
          const SizedBox(width: 8),
          _ActionChip(
            icon: Icons.upload_outlined,
            label: 'Push',
            onPressed: loading ? null : onPush,
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

// ---------------------------------------------------------------------------
// Status Card — parses porcelain output into colored file list
// ---------------------------------------------------------------------------

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.statusOutput});
  final String statusOutput;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines =
        statusOutput.split('\n').where((l) => l.trim().isNotEmpty).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.list_alt,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Status', style: theme.textTheme.titleSmall),
                const Spacer(),
                if (lines.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${lines.length} file${lines.length == 1 ? '' : 's'}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (lines.isEmpty)
              Text(
                'Working tree clean',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              ...lines.map((line) => _StatusLine(line: line)),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.line});
  final String line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Parse git status --porcelain format: "XY filename"
    final statusCode = line.length >= 2 ? line.substring(0, 2) : '??';
    final fileName = line.length > 3 ? line.substring(3) : line;

    final (Color color, IconData icon, String label) =
        switch (statusCode.trim()) {
      'M' || 'MM' => (Colors.orange, Icons.edit_outlined, 'Modified'),
      'A' || 'AM' => (Colors.green, Icons.add_circle_outline, 'Added'),
      'D' => (Colors.red, Icons.remove_circle_outline, 'Deleted'),
      'R' => (Colors.blue, Icons.drive_file_rename_outline, 'Renamed'),
      'C' => (Colors.purple, Icons.copy_outlined, 'Copied'),
      '??' => (Colors.grey, Icons.help_outline, 'Untracked'),
      'U' || 'UU' => (Colors.deepOrange, Icons.warning_outlined, 'Conflict'),
      _ => (theme.colorScheme.onSurface, Icons.circle_outlined, statusCode),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fileName,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Diff Card — scrollable code block with +/- coloring
// ---------------------------------------------------------------------------

class _DiffCard extends StatelessWidget {
  const _DiffCard({required this.diffOutput});
  final String diffOutput;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = diffOutput.split('\n');

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.difference_outlined,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text('Diff', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            if (diffOutput.trim().isEmpty)
              Text(
                'No unstaged changes',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 500),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:
                            lines.map((line) => _DiffLine(line: line)).toList(),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({required this.line});
  final String line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final (Color? bgColor, Color textColor) = _lineColors(isDark);

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minWidth: 600),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      color: bgColor,
      child: Text(
        line,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.5,
          color: textColor,
        ),
      ),
    );
  }

  (Color?, Color) _lineColors(bool isDark) {
    if (line.startsWith('+++') || line.startsWith('---')) {
      // File header lines
      return (
        isDark
            ? Colors.blue.shade900.withValues(alpha: 0.3)
            : Colors.blue.shade50,
        isDark ? Colors.blue.shade200 : Colors.blue.shade900,
      );
    }
    if (line.startsWith('+')) {
      return (
        isDark
            ? Colors.green.shade900.withValues(alpha: 0.3)
            : Colors.green.shade50,
        isDark ? Colors.green.shade300 : Colors.green.shade900,
      );
    }
    if (line.startsWith('-')) {
      return (
        isDark
            ? Colors.red.shade900.withValues(alpha: 0.3)
            : Colors.red.shade50,
        isDark ? Colors.red.shade300 : Colors.red.shade900,
      );
    }
    if (line.startsWith('@@')) {
      return (
        isDark
            ? Colors.purple.shade900.withValues(alpha: 0.2)
            : Colors.purple.shade50,
        isDark ? Colors.purple.shade200 : Colors.purple.shade700,
      );
    }
    if (line.startsWith('diff ') || line.startsWith('index ')) {
      return (
        null,
        isDark ? Colors.grey.shade400 : Colors.grey.shade600,
      );
    }
    return (null, isDark ? Colors.grey.shade300 : Colors.grey.shade800);
  }
}
