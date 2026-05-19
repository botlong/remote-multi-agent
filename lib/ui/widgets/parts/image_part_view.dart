import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/part.dart';
import '../../../state/settings_store.dart';

/// Renders an [ImagePart] — supports base64 data URLs, server file paths,
/// and regular HTTP URLs. Tappable to view full-screen.
class ImagePartView extends ConsumerWidget {
  const ImagePartView({super.key, required this.part});
  final ImagePart part;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _openFullScreen(context, ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 400,
              maxHeight: 300,
            ),
            child: _buildImage(context, ref),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(BuildContext context, WidgetRef ref) {
    if (part.isDataUrl) {
      final bytes = _decodeDataUrl(part.image);
      if (bytes == null) return _errorWidget(context, 'Invalid data URL');
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _errorWidget(context, null),
      );
    }

    final url = _resolveUrl(ref);
    return Image.network(
      url,
      fit: BoxFit.contain,
      loadingBuilder: (_, child, progress) {
        if (progress == null) return child;
        return Container(
          width: 200,
          height: 150,
          alignment: Alignment.center,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: CircularProgressIndicator(
            value: progress.expectedTotalBytes != null
                ? progress.cumulativeBytesLoaded /
                    progress.expectedTotalBytes!
                : null,
            strokeWidth: 2,
          ),
        );
      },
      errorBuilder: (_, __, ___) => _errorWidget(context, null),
    );
  }

  /// Resolve the image URL. For server file paths, construct the
  /// `/files/read?path=<path>` endpoint URL.
  String _resolveUrl(WidgetRef ref) {
    if (!part.isFilePath) return part.image;

    // Build URL from server base
    final settings = ref.read(settingsControllerProvider);
    final base = settings.baseUrl.replaceAll(RegExp(r'/$'), '');
    final encodedPath = Uri.encodeComponent(part.image);
    return '$base/files/read?path=$encodedPath';
  }

  /// Decode a `data:image/...;base64,...` URL into bytes.
  Uint8List? _decodeDataUrl(String dataUrl) {
    try {
      final commaIndex = dataUrl.indexOf(',');
      if (commaIndex < 0) return null;
      final b64 = dataUrl.substring(commaIndex + 1);
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Widget _errorWidget(BuildContext context, String? message) {
    final theme = Theme.of(context);
    return Container(
      width: 200,
      height: 100,
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image, color: theme.colorScheme.onErrorContainer),
          const SizedBox(height: 4),
          Text(
            message ?? 'Failed to load image',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ],
      ),
    );
  }

  void _openFullScreen(BuildContext context, WidgetRef ref) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullScreenImagePage(
          part: part,
          imageUrl: part.isDataUrl ? null : _resolveUrl(ref),
          imageBytes: part.isDataUrl ? _decodeDataUrl(part.image) : null,
        ),
      ),
    );
  }
}

/// Full-screen image viewer with pinch-to-zoom.
class _FullScreenImagePage extends StatelessWidget {
  const _FullScreenImagePage({
    required this.part,
    this.imageUrl,
    this.imageBytes,
  });

  final ImagePart part;
  final String? imageUrl;
  final Uint8List? imageBytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          part.alt ?? 'Image',
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: _buildFullImage(),
        ),
      ),
    );
  }

  Widget _buildFullImage() {
    if (imageBytes != null) {
      return Image.memory(imageBytes!, fit: BoxFit.contain);
    }
    if (imageUrl != null) {
      return Image.network(
        imageUrl!,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: CircularProgressIndicator(color: Colors.white),
          );
        },
      );
    }
    return const Icon(Icons.broken_image, color: Colors.white54, size: 64);
  }
}
