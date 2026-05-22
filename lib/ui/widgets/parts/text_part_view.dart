import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../../../models/part.dart';

/// Renders a [TextPart] as rich Markdown with:
/// - Syntax-highlighted code blocks (with copy button)
/// - Inline images
/// - Tappable links (opened in external browser)
/// - Tables, blockquotes, lists
class TextPartView extends StatelessWidget {
  const TextPartView({super.key, required this.part});
  final TextPart part;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MarkdownBody(
      data: part.text,
      selectable: true,
      shrinkWrap: true,
      onTapLink: (text, href, title) => _openLink(context, href),
      imageBuilder: (uri, title, alt) => _buildImage(context, uri, alt),
      builders: {
        'pre': _CodeBlockBuilder(isDark: isDark),
      },
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        p: theme.textTheme.bodyMedium,
        code: TextStyle(
          fontFamily: 'monospace',
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          fontSize: 13,
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? const Color(0xFF282C34) : const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(8),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        h1: theme.textTheme.titleLarge,
        h2: theme.textTheme.titleMedium,
        h3: theme.textTheme.titleSmall,
        blockquoteDecoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
              width: 3,
            ),
          ),
        ),
        blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
        tableBorder: TableBorder.all(
          color: theme.colorScheme.outlineVariant,
          width: 1,
          borderRadius: BorderRadius.circular(4),
        ),
        tableHead: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        tableBody: theme.textTheme.bodyMedium,
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
      ),
    );
  }

  void _openLink(BuildContext context, String? href) {
    if (href == null || href.isEmpty) return;
    final uri = Uri.tryParse(href);
    if (uri == null) return;
    launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _buildImage(BuildContext context, Uri uri, String? alt) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          uri.toString(),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.broken_image,
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    alt ?? 'Image failed to load',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Custom builder for fenced code blocks — adds syntax highlighting and a
/// copy-to-clipboard button.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.isDark});
  final bool isDark;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // For <pre> blocks, the code is inside a <code> child element
    String? language;
    var code = element.textContent;

    // Try to extract language from the nested <code> element's class
    if (element.children != null && element.children!.isNotEmpty) {
      final codeElement = element.children!.first;
      if (codeElement is md.Element) {
        final className = codeElement.attributes['class'] ?? '';
        if (className.startsWith('language-')) {
          language = className.substring('language-'.length);
        }
        code = codeElement.textContent;
      }
    }

    return _CodeBlockWidget(
      code: code,
      language: language,
      isDark: isDark,
    );
  }
}

class _CodeBlockWidget extends StatelessWidget {
  const _CodeBlockWidget({
    required this.code,
    this.language,
    required this.isDark,
  });

  final String code;
  final String? language;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlightTheme = isDark ? atomOneDarkTheme : atomOneLightTheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF282C34) : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with language label and copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.5,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                if (language != null)
                  Text(
                    language!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                _CopyButton(code: code),
              ],
            ),
          ),
          // Code content
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: HighlightView(
              code.trimRight(),
              language: language ?? 'plaintext',
              theme: highlightTheme,
              padding: EdgeInsets.zero,
              textStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.code});
  final String code;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: _copy,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check : Icons.copy,
              size: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Copied' : 'Copy',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
