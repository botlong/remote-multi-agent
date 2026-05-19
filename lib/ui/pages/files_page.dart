// ignore_for_file: unintended_html_in_doc_comment

/// File tree browser for the current session's working directory.
///
/// Shows a recursive file/folder tree fetched from the QQBot server endpoint:
///   GET http://<qqbot-url>/files?path=<directory>
///
/// Tapping a file navigates to [FileViewerPage] which displays the content
/// with basic syntax highlighting.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/session.dart';
import '../../state/codex_thread_store.dart';
import '../../state/settings_store.dart';

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

class FileNode {
  const FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.children = const [],
  });

  final String name;
  final String path;
  final bool isDirectory;
  final List<FileNode> children;

  factory FileNode.fromJson(Map<String, dynamic> json) {
    final children = (json['children'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map(FileNode.fromJson)
            .toList(growable: false) ??
        const [];
    return FileNode(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      isDirectory: json['isDirectory'] as bool? ?? false,
      children: children,
    );
  }
}

// ---------------------------------------------------------------------------
// API client helper
// ---------------------------------------------------------------------------

/// Fetches the file tree from the QQBot relay server.
///
/// The endpoint doesn't exist yet — this will gracefully fail and the UI
/// shows an appropriate error state.
class FileListClient {
  FileListClient({required this.qqbotBaseUrl});

  final String qqbotBaseUrl;

  late final _dio = Dio(
    BaseOptions(
      baseUrl: qqbotBaseUrl.replaceAll(RegExp(r'/$'), ''),
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
    ),
  );

  /// Returns the root-level list of [FileNode]s for [directoryPath].
  Future<List<FileNode>> listFiles(String directoryPath) async {
    final res = await _dio.get<dynamic>(
      '/files',
      queryParameters: {'path': directoryPath},
    );
    final data = res.data;
    if (data is List) {
      return data
          .whereType<Map<String, dynamic>>()
          .map(FileNode.fromJson)
          .toList(growable: false);
    }
    return const [];
  }

  /// Reads the content of a single file.
  Future<String> readFile(String filePath) async {
    final res = await _dio.get<dynamic>(
      '/files/read',
      queryParameters: {'path': filePath},
    );
    final data = res.data;
    if (data is Map) {
      return data['content'] as String? ?? '';
    }
    if (data is String) return data;
    return '';
  }

  void close() => _dio.close(force: true);
}

// ---------------------------------------------------------------------------
// Riverpod provider for the file client
// ---------------------------------------------------------------------------

/// The QQBot server URL. Defaults to the same host as the OpenCode server
/// but on port 8787.
final _qqbotUrlProvider = Provider<String>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  // Derive QQBot URL from OpenCode base URL — same host, port 8787.
  final uri = Uri.tryParse(settings.baseUrl);
  if (uri == null) return 'http://127.0.0.1:8787';
  return '${uri.scheme}://${uri.host}:8787';
});

final fileListClientProvider = Provider<FileListClient>((ref) {
  final url = ref.watch(_qqbotUrlProvider);
  final client = FileListClient(qqbotBaseUrl: url);
  ref.onDispose(client.close);
  return client;
});

// ---------------------------------------------------------------------------
// FilesPage
// ---------------------------------------------------------------------------

class FilesPage extends ConsumerStatefulWidget {
  const FilesPage({super.key, this.session});

  /// Optional. If null, defaults to the most recently updated session
  /// (so the page can be used as a top-level tab).
  final Session? session;

  @override
  ConsumerState<FilesPage> createState() => _FilesPageState();
}

class _FilesPageState extends ConsumerState<FilesPage> {
  List<FileNode>? _nodes;
  bool _loading = true;
  String? _error;

  Session? get _session {
    if (widget.session != null) return widget.session;
    // Codex backend: synthesize a Session from the most recent thread so
    // the existing _DirectoryHeader / FileViewerPage signatures still work.
    final list = ref.read(codexThreadListProvider).items;
    if (list.isEmpty) return null;
    final t = list.first;
    return Session(
      id: t.threadId ?? t.localKey,
      slug: t.localKey,
      title: t.title,
      directory: t.directory,
      createdAtMs: t.createdAtMs,
      updatedAtMs: t.updatedAtMs,
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadFiles());
  }

  Future<void> _loadFiles() async {
    final session = _session;
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No session yet — create one in the Chat tab.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(fileListClientProvider);
      final nodes = await client.listFiles(session.directory);
      if (!mounted) return;
      setState(() {
        _nodes = _sortNodes(nodes);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load files: $e';
      });
    }
  }

  /// Sort: directories first, then alphabetical.
  List<FileNode> _sortNodes(List<FileNode> nodes) {
    final sorted = [...nodes];
    sorted.sort((a, b) {
      if (a.isDirectory && !b.isDirectory) return -1;
      if (!a.isDirectory && b.isDirectory) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return sorted.map((node) {
      if (node.isDirectory && node.children.isNotEmpty) {
        return FileNode(
          name: node.name,
          path: node.path,
          isDirectory: true,
          children: _sortNodes(node.children),
        );
      }
      return node;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Files'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadFiles,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: session name + directory path
          if (_session != null) _DirectoryHeader(session: _session!),
          const Divider(height: 1),
          // File tree
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_off_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                'Could not load files',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _loadFiles,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_nodes == null || _nodes!.isEmpty) {
      return Center(
        child: Text(
          'No files found',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: _nodes!.length,
      itemBuilder: (context, index) => _FileTreeTile(
        node: _nodes![index],
        depth: 0,
        onFileTap: _openFile,
      ),
    );
  }

  void _openFile(FileNode file) {
    final s = _session;
    if (s == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FileViewerPage(
          filePath: file.path,
          fileName: file.name,
          session: s,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Directory header widget
// ---------------------------------------------------------------------------

class _DirectoryHeader extends StatelessWidget {
  const _DirectoryHeader({required this.session});
  final Session session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.title.isNotEmpty ? session.title : session.slug,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 14,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  session.directory,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.outline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recursive file tree tile
// ---------------------------------------------------------------------------

class _FileTreeTile extends StatelessWidget {
  const _FileTreeTile({
    required this.node,
    required this.depth,
    required this.onFileTap,
  });

  final FileNode node;
  final int depth;
  final void Function(FileNode) onFileTap;

  @override
  Widget build(BuildContext context) {
    if (node.isDirectory) {
      return _DirectoryTile(node: node, depth: depth, onFileTap: onFileTap);
    }
    return _FileTile(node: node, depth: depth, onTap: () => onFileTap(node));
  }
}

class _DirectoryTile extends StatelessWidget {
  const _DirectoryTile({
    required this.node,
    required this.depth,
    required this.onFileTap,
  });

  final FileNode node;
  final int depth;
  final void Function(FileNode) onFileTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExpansionTile(
      leading: Icon(Icons.folder_outlined, color: theme.colorScheme.primary),
      title: Text(
        node.name,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      tilePadding: EdgeInsets.only(left: 16.0 + depth * 16.0, right: 16),
      childrenPadding: EdgeInsets.zero,
      children: node.children.map((child) {
        return _FileTreeTile(
          node: child,
          depth: depth + 1,
          onFileTap: onFileTap,
        );
      }).toList(),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.node,
    required this.depth,
    required this.onTap,
  });

  final FileNode node;
  final int depth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(_iconForFile(node.name), color: theme.colorScheme.outline),
      title: Text(
        node.name,
        style: theme.textTheme.bodyMedium,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      contentPadding: EdgeInsets.only(left: 16.0 + depth * 16.0, right: 16),
      dense: true,
      onTap: onTap,
    );
  }

  static IconData _iconForFile(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'dart' => Icons.code,
      'ts' || 'tsx' || 'js' || 'jsx' => Icons.javascript,
      'json' => Icons.data_object,
      'yaml' || 'yml' => Icons.settings,
      'md' || 'mdx' => Icons.article_outlined,
      'html' || 'htm' => Icons.web,
      'css' || 'scss' || 'sass' => Icons.style,
      'png' || 'jpg' || 'jpeg' || 'gif' || 'svg' || 'webp' => Icons.image,
      'pdf' => Icons.picture_as_pdf,
      'lock' => Icons.lock_outline,
      'sh' || 'bat' || 'ps1' => Icons.terminal,
      'toml' || 'ini' || 'cfg' || 'conf' => Icons.tune,
      'txt' || 'log' => Icons.description_outlined,
      'xml' => Icons.code,
      'sql' => Icons.storage,
      'env' => Icons.vpn_key_outlined,
      'gitignore' || 'dockerignore' => Icons.visibility_off_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
  }
}

// ---------------------------------------------------------------------------
// FileViewerPage — shows file content with syntax highlighting
// ---------------------------------------------------------------------------

class FileViewerPage extends ConsumerStatefulWidget {
  const FileViewerPage({
    super.key,
    required this.filePath,
    required this.fileName,
    required this.session,
  });

  final String filePath;
  final String fileName;
  final Session session;

  @override
  ConsumerState<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends ConsumerState<FileViewerPage> {
  String? _content;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadContent();
  }

  Future<void> _loadContent() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(fileListClientProvider);
      final content = await client.readFile(widget.filePath);
      if (!mounted) return;
      setState(() {
        _content = content;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not read file: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _loading ? null : _loadContent,
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _loadContent,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_content == null) {
      return const Center(child: Text('No content'));
    }

    return _CodeView(
      content: _content!,
      fileName: widget.fileName,
    );
  }
}

// ---------------------------------------------------------------------------
// Code viewer with basic syntax highlighting
// ---------------------------------------------------------------------------

class _CodeView extends StatelessWidget {
  const _CodeView({required this.content, required this.fileName});

  final String content;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lines = content.split('\n');
    final lineNumberWidth = '${lines.length}'.length * 10.0 + 16;

    return Container(
      color: theme.colorScheme.surfaceContainerLowest,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // File path bar
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: theme.colorScheme.surfaceContainerLow,
                  child: Text(
                    fileName,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
                // Code lines
                ...List.generate(lines.length, (i) {
                  return _CodeLine(
                    lineNumber: i + 1,
                    text: lines[i],
                    lineNumberWidth: lineNumberWidth,
                    language: _languageFromFileName(fileName),
                  );
                }),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _languageFromFileName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'dart' => 'dart',
      'ts' || 'tsx' => 'typescript',
      'js' || 'jsx' => 'javascript',
      'json' => 'json',
      'yaml' || 'yml' => 'yaml',
      'md' || 'mdx' => 'markdown',
      'html' || 'htm' => 'html',
      'css' => 'css',
      'py' => 'python',
      'go' => 'go',
      'rs' => 'rust',
      'sh' || 'bash' => 'bash',
      'sql' => 'sql',
      'xml' => 'xml',
      _ => 'text',
    };
  }
}

class _CodeLine extends StatelessWidget {
  const _CodeLine({
    required this.lineNumber,
    required this.text,
    required this.lineNumberWidth,
    required this.language,
  });

  final int lineNumber;
  final String text;
  final double lineNumberWidth;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Line number gutter
        SizedBox(
          width: lineNumberWidth,
          child: Padding(
            padding: const EdgeInsets.only(right: 12, top: 1),
            child: Text(
              '$lineNumber',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 12,
                color: theme.colorScheme.outline.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        // Code text with basic keyword highlighting
        Flexible(
          child: Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _HighlightedText(text: text, language: language),
          ),
        ),
      ],
    );
  }
}

/// Very basic keyword-level syntax highlighting.
/// For a production app you'd use flutter_highlight or similar, but this
/// keeps the dependency footprint minimal and works offline.
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.language});

  final String text;
  final String language;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spans = _highlight(text, language, theme);
    return RichText(
      text: TextSpan(
        style: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.5,
        ),
        children: spans,
      ),
    );
  }

  static List<TextSpan> _highlight(
    String text,
    String language,
    ThemeData theme,
  ) {
    if (text.isEmpty) return [const TextSpan(text: ' ')];

    final colorScheme = theme.colorScheme;
    final keywordColor = colorScheme.primary;
    final stringColor = Colors.green.shade700;
    final commentColor = colorScheme.outline;
    final numberColor = Colors.orange.shade800;
    final defaultColor = colorScheme.onSurface;

    // Comment detection
    if (text.trimLeft().startsWith('//') || text.trimLeft().startsWith('#')) {
      return [
        TextSpan(text: text, style: TextStyle(color: commentColor)),
      ];
    }

    // Simple keyword-based highlighting
    final keywords = _keywordsFor(language);
    if (keywords.isEmpty) {
      return [TextSpan(text: text, style: TextStyle(color: defaultColor))];
    }

    final spans = <TextSpan>[];
    final pattern = RegExp(
      '($_stringPattern)|'
      '(\\b(?:${keywords.join('|')})\\b)|'
      '(\\b\\d+\\.?\\d*\\b)',
    );

    int lastEnd = 0;
    for (final match in pattern.allMatches(text)) {
      // Text before match
      if (match.start > lastEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastEnd, match.start),
            style: TextStyle(color: defaultColor),
          ),
        );
      }
      final matched = match.group(0)!;
      Color color;
      if (match.group(1) != null) {
        color = stringColor;
      } else if (match.group(2) != null) {
        color = keywordColor;
      } else {
        color = numberColor;
      }
      spans.add(
        TextSpan(
          text: matched,
          style: TextStyle(
            color: color,
            fontWeight:
                match.group(2) != null ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastEnd),
          style: TextStyle(color: defaultColor),
        ),
      );
    }
    return spans.isEmpty
        ? [TextSpan(text: text, style: TextStyle(color: defaultColor))]
        : spans;
  }

  static const _stringPattern = r"""('[^']*'|"[^"]*")""";

  static List<String> _keywordsFor(String language) {
    return switch (language) {
      'dart' => [
          'import',
          'export',
          'library',
          'part',
          'class',
          'abstract',
          'extends',
          'implements',
          'mixin',
          'enum',
          'typedef',
          'final',
          'const',
          'var',
          'late',
          'static',
          'dynamic',
          'void',
          'int',
          'double',
          'String',
          'bool',
          'List',
          'Map',
          'Set',
          'if',
          'else',
          'for',
          'while',
          'do',
          'switch',
          'case',
          'default',
          'break',
          'continue',
          'return',
          'throw',
          'try',
          'catch',
          'finally',
          'async',
          'await',
          'yield',
          'sync',
          'true',
          'false',
          'null',
          'this',
          'super',
          'new',
          'required',
          'override',
          'factory',
          'get',
          'set',
          'with',
        ],
      'typescript' || 'javascript' => [
          'import',
          'export',
          'from',
          'default',
          'as',
          'const',
          'let',
          'var',
          'function',
          'class',
          'extends',
          'interface',
          'type',
          'enum',
          'namespace',
          'if',
          'else',
          'for',
          'while',
          'do',
          'switch',
          'case',
          'break',
          'continue',
          'return',
          'throw',
          'try',
          'catch',
          'finally',
          'async',
          'await',
          'yield',
          'true',
          'false',
          'null',
          'undefined',
          'this',
          'new',
          'void',
          'string',
          'number',
          'boolean',
          'any',
          'never',
        ],
      'json' => [],
      'yaml' => ['true', 'false', 'null'],
      'python' => [
          'import',
          'from',
          'as',
          'class',
          'def',
          'lambda',
          'if',
          'elif',
          'else',
          'for',
          'while',
          'break',
          'continue',
          'return',
          'yield',
          'raise',
          'try',
          'except',
          'finally',
          'with',
          'True',
          'False',
          'None',
          'self',
          'and',
          'or',
          'not',
          'in',
          'is',
          'async',
          'await',
          'pass',
          'global',
          'nonlocal',
        ],
      'go' => [
          'package',
          'import',
          'func',
          'type',
          'struct',
          'interface',
          'var',
          'const',
          'map',
          'chan',
          'range',
          'if',
          'else',
          'for',
          'switch',
          'case',
          'default',
          'select',
          'break',
          'continue',
          'return',
          'go',
          'defer',
          'fallthrough',
          'true',
          'false',
          'nil',
          'iota',
        ],
      'rust' => [
          'use',
          'mod',
          'pub',
          'fn',
          'struct',
          'enum',
          'trait',
          'impl',
          'let',
          'mut',
          'const',
          'static',
          'type',
          'where',
          'if',
          'else',
          'for',
          'while',
          'loop',
          'match',
          'break',
          'continue',
          'return',
          'async',
          'await',
          'move',
          'true',
          'false',
          'self',
          'Self',
          'super',
          'crate',
        ],
      _ => [],
    };
  }
}
