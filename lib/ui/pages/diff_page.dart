import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/gateway_providers.dart';

// ─── Data model ──────────────────────────────────────────────────────

class _FileDiff {
  _FileDiff({required this.path, required this.lines});
  final String path;
  final List<_DiffLine> lines;

  int get additions => lines.where((l) => l.kind == _LineKind.add).length;
  int get deletions => lines.where((l) => l.kind == _LineKind.del).length;
}

enum _LineKind { context, add, del, hunk, meta }

class _DiffLine {
  const _DiffLine({
    required this.text,
    required this.kind,
    this.oldNo,
    this.newNo,
  });
  final String text;
  final _LineKind kind;
  final int? oldNo;
  final int? newNo;
}

List<_FileDiff> _parseDiff(String raw) {
  final files = <_FileDiff>[];
  final allLines = raw.split('\n');
  String currentPath = '';
  List<_DiffLine> currentLines = [];
  int oldLine = 0, newLine = 0;

  void flush() {
    if (currentPath.isNotEmpty || currentLines.isNotEmpty) {
      files.add(_FileDiff(
        path: currentPath.isEmpty ? 'unknown' : currentPath,
        lines: List.unmodifiable(currentLines),
      ));
    }
  }

  for (final line in allLines) {
    if (line.startsWith('diff ')) {
      flush();
      currentLines = [];
      // Extract file path: "diff --git a/foo b/foo" → "foo"
      final m = RegExp(r'b/(.+)$').firstMatch(line);
      currentPath = m?.group(1) ?? line;
      currentLines.add(_DiffLine(text: line, kind: _LineKind.meta));
    } else if (line.startsWith('index ') ||
        line.startsWith('---') ||
        line.startsWith('+++') ||
        line.startsWith('new file') ||
        line.startsWith('deleted file') ||
        line.startsWith('rename') ||
        line.startsWith('similarity') ||
        line.startsWith('Binary')) {
      currentLines.add(_DiffLine(text: line, kind: _LineKind.meta));
    } else if (line.startsWith('@@')) {
      // Parse hunk header: @@ -oldStart,oldLen +newStart,newLen @@
      final hunk = RegExp(r'@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@')
          .firstMatch(line);
      if (hunk != null) {
        oldLine = int.parse(hunk.group(1)!);
        newLine = int.parse(hunk.group(2)!);
      }
      currentLines.add(_DiffLine(text: line, kind: _LineKind.hunk));
    } else if (line.startsWith('+')) {
      currentLines.add(_DiffLine(
        text: line,
        kind: _LineKind.add,
        newNo: newLine++,
      ));
    } else if (line.startsWith('-')) {
      currentLines.add(_DiffLine(
        text: line,
        kind: _LineKind.del,
        oldNo: oldLine++,
      ));
    } else {
      currentLines.add(_DiffLine(
        text: line,
        kind: _LineKind.context,
        oldNo: oldLine++,
        newNo: newLine++,
      ));
    }
  }
  flush();
  return files;
}

// ─── Page ────────────────────────────────────────────────────────────

/// GitHub-style git diff viewer with file grouping, line numbers, and stats.
class DiffPage extends ConsumerStatefulWidget {
  const DiffPage({super.key, required this.sessionId});
  final String sessionId;

  @override
  ConsumerState<DiffPage> createState() => _DiffPageState();
}

class _DiffPageState extends ConsumerState<DiffPage> {
  String? _diff;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDiff();
  }

  Future<void> _loadDiff() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(gatewayClientProvider);
      final result = await client.getSessionDiff(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _diff = result['diff'] as String? ?? '';
        _error = result['error'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Changes'),
        actions: [
          if (_diff != null && _diff!.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_rounded, size: 20),
              tooltip: 'Copy diff',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _diff!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Diff copied'),
                    duration: Duration(seconds: 1),
                  ),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            tooltip: 'Refresh',
            onPressed: _loadDiff,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator.adaptive())
          : _error != null && (_diff == null || _diff!.isEmpty)
              ? _ErrorView(error: _error!, onRetry: _loadDiff)
              : _diff != null && _diff!.isEmpty
                  ? _EmptyView()
                  : _DiffContent(diff: _diff!),
    );
  }
}

// ─── Empty state ─────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'No uncommitted changes',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Working tree is clean',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 40, color: scheme.error),
            const SizedBox(height: 12),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Diff content with file sections ─────────────────────────────────

class _DiffContent extends StatelessWidget {
  const _DiffContent({required this.diff});
  final String diff;

  @override
  Widget build(BuildContext context) {
    final files = _parseDiff(diff);
    final totalAdd = files.fold<int>(0, (s, f) => s + f.additions);
    final totalDel = files.fold<int>(0, (s, f) => s + f.deletions);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: files.length + 1, // +1 for summary header
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SummaryBar(
            fileCount: files.length,
            additions: totalAdd,
            deletions: totalDel,
          );
        }
        return _FileDiffCard(file: files[index - 1]);
      },
    );
  }
}

// ─── Summary bar ─────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.fileCount,
    required this.additions,
    required this.deletions,
  });
  final int fileCount;
  final int additions;
  final int deletions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              '$fileCount file${fileCount == 1 ? '' : 's'} changed',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            _StatChip(
              value: '+$additions',
              color: const Color(0xFF2DA44E),
            ),
            const SizedBox(width: 8),
            _StatChip(
              value: '-$deletions',
              color: const Color(0xFFCF222E),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.value, required this.color});
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        value,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ─── Per-file card ───────────────────────────────────────────────────

class _FileDiffCard extends StatefulWidget {
  const _FileDiffCard({required this.file});
  final _FileDiff file;

  @override
  State<_FileDiffCard> createState() => _FileDiffCardState();
}

class _FileDiffCardState extends State<_FileDiffCard> {
  bool _expanded = true;

  String get _fileName {
    final parts = widget.file.path.split('/');
    return parts.last;
  }

  String get _dirPath {
    final parts = widget.file.path.split('/');
    if (parts.length <= 1) return '';
    return '${parts.sublist(0, parts.length - 1).join('/')}/';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final file = widget.file;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── File header ──
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: scheme.surfaceContainerLow,
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.insert_drive_file_outlined,
                    size: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (_dirPath.isNotEmpty)
                            TextSpan(
                              text: _dirPath,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: scheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          TextSpan(
                            text: _fileName,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _DiffBar(
                    additions: file.additions,
                    deletions: file.deletions,
                  ),
                ],
              ),
            ),
          ),

          // ── Diff lines ──
          if (_expanded) _DiffLines(lines: file.lines),
        ],
      ),
    );
  }
}

// ─── Mini diff bar (GitHub-style 5-block indicator) ──────────────────

class _DiffBar extends StatelessWidget {
  const _DiffBar({required this.additions, required this.deletions});
  final int additions;
  final int deletions;

  @override
  Widget build(BuildContext context) {
    final total = additions + deletions;
    if (total == 0) return const SizedBox.shrink();
    const blocks = 5;
    final addBlocks = total == 0 ? 0 : (additions * blocks / total).round();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '+$additions',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: Color(0xFF2DA44E),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          '-$deletions',
          style: const TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: Color(0xFFCF222E),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(blocks, (i) {
            final isAdd = i < addBlocks;
            return Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 0.5),
              decoration: BoxDecoration(
                color: isAdd ? const Color(0xFF2DA44E) : const Color(0xFFCF222E),
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        ),
      ],
    );
  }
}

// ─── Diff lines with line numbers ────────────────────────────────────

class _DiffLines extends StatelessWidget {
  const _DiffLines({required this.lines});
  final List<_DiffLine> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Filter out meta lines (diff --git, index, etc.) for cleaner view
    final visibleLines = lines
        .where((l) => l.kind != _LineKind.meta)
        .toList(growable: false);

    if (visibleLines.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: MediaQuery.of(context).size.width - 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in visibleLines)
              _DiffLineRow(line: line, isDark: isDark),
          ],
        ),
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  const _DiffLineRow({required this.line, required this.isDark});
  final _DiffLine line;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _colors();
    final gutterStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.2)
          : Colors.black.withValues(alpha: 0.2),
    );

    return Container(
      color: bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Old line number
          SizedBox(
            width: 42,
            child: Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(
                line.oldNo?.toString() ?? '',
                textAlign: TextAlign.right,
                style: gutterStyle,
              ),
            ),
          ),
          // New line number
          SizedBox(
            width: 42,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                line.newNo?.toString() ?? '',
                textAlign: TextAlign.right,
                style: gutterStyle,
              ),
            ),
          ),
          // Content
          Flexible(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                line.text,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.5,
                  color: fg,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  (Color?, Color) _colors() {
    switch (line.kind) {
      case _LineKind.add:
        return (
          isDark ? const Color(0x1A2DA44E) : const Color(0x1A2DA44E),
          isDark ? const Color(0xFF7EE787) : const Color(0xFF1A7F37),
        );
      case _LineKind.del:
        return (
          isDark ? const Color(0x1ACF222E) : const Color(0x1ACF222E),
          isDark ? const Color(0xFFFF7B72) : const Color(0xFFCF222E),
        );
      case _LineKind.hunk:
        return (
          isDark ? const Color(0x0DFFFFFF) : const Color(0x08000000),
          isDark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
        );
      case _LineKind.meta:
        return (
          null,
          isDark ? const Color(0xFF8B949E) : const Color(0xFF57606A),
        );
      case _LineKind.context:
        return (
          null,
          isDark ? const Color(0xFFD0D7DE) : const Color(0xFF24292F),
        );
    }
  }
}
