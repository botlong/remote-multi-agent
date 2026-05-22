import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Represents a user-selected attachment ready to be sent.
class Attachment {
  const Attachment({
    required this.fileName,
    required this.mimeType,
    required this.base64Data,
    this.bytes,
  });

  final String fileName;
  final String mimeType;

  /// Base64-encoded file content.
  final String base64Data;

  /// Raw bytes for thumbnail preview.
  final List<int>? bytes;

  /// Whether this attachment is an image.
  bool get isImage => mimeType.startsWith('image/');

  /// Returns the data URL format for the API: `data:<mime>;base64,<data>`
  String get dataUrl => 'data:$mimeType;base64,$base64Data';

  /// Convert to the API part format.
  Map<String, dynamic> toPartJson() {
    if (isImage) {
      return {
        'type': 'image',
        'image': dataUrl,
      };
    }
    return {
      'type': 'file',
      'fileName': fileName,
      'mimeType': mimeType,
      'data': base64Data,
    };
  }
}

/// Shows a bottom sheet allowing the user to pick images (camera/gallery)
/// or files from the device. Returns a list of [Attachment]s or null if
/// cancelled.
Future<List<Attachment>?> showAttachmentPicker(BuildContext context) {
  return showModalBottomSheet<List<Attachment>>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _AttachmentPickerSheet(),
  );
}

class _AttachmentPickerSheet extends StatelessWidget {
  const _AttachmentPickerSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Add Attachment',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _PickerOption(
              icon: Icons.camera_alt_outlined,
              label: 'Take Photo',
              onTap: () => _pickFromCamera(context),
            ),
            _PickerOption(
              icon: Icons.photo_library_outlined,
              label: 'Choose from Gallery',
              onTap: () => _pickFromGallery(context),
            ),
            _PickerOption(
              icon: Icons.attach_file,
              label: 'Choose File',
              onTap: () => _pickFile(context),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFromCamera(BuildContext context) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (image == null) return;
    if (!context.mounted) return;

    final attachment = await _xFileToAttachment(image);
    if (attachment != null && context.mounted) {
      Navigator.of(context).pop([attachment]);
    }
  }

  Future<void> _pickFromGallery(BuildContext context) async {
    final picker = ImagePicker();
    final images = await picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 2048,
      maxHeight: 2048,
    );
    if (images.isEmpty) return;
    if (!context.mounted) return;

    final attachments = <Attachment>[];
    for (final img in images) {
      final a = await _xFileToAttachment(img);
      if (a != null) attachments.add(a);
    }
    if (attachments.isNotEmpty && context.mounted) {
      Navigator.of(context).pop(attachments);
    }
  }

  Future<void> _pickFile(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;

    final attachments = <Attachment>[];
    for (final file in result.files) {
      if (file.bytes != null) {
        attachments.add(
          Attachment(
            fileName: file.name,
            mimeType: _guessMimeType(file.name, file.extension),
            base64Data: base64Encode(file.bytes!),
            bytes: file.bytes,
          ),
        );
      } else if (file.path != null) {
        // On mobile, read from path
        final bytes = await File(file.path!).readAsBytes();
        attachments.add(
          Attachment(
            fileName: file.name,
            mimeType: _guessMimeType(file.name, file.extension),
            base64Data: base64Encode(bytes),
            bytes: bytes,
          ),
        );
      }
    }
    if (attachments.isNotEmpty && context.mounted) {
      Navigator.of(context).pop(attachments);
    }
  }

  Future<Attachment?> _xFileToAttachment(XFile xFile) async {
    try {
      final bytes = await xFile.readAsBytes();
      final mime = xFile.mimeType ?? _guessMimeType(xFile.name, null);
      return Attachment(
        fileName: xFile.name,
        mimeType: mime,
        base64Data: base64Encode(bytes),
        bytes: bytes,
      );
    } catch (_) {
      return null;
    }
  }

  String _guessMimeType(String fileName, String? extension) {
    final ext = (extension ?? fileName.split('.').last).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'pdf' => 'application/pdf',
      'json' => 'application/json',
      'txt' => 'text/plain',
      'md' => 'text/markdown',
      'dart' => 'text/x-dart',
      'ts' || 'tsx' => 'text/typescript',
      'js' || 'jsx' => 'text/javascript',
      'html' => 'text/html',
      'css' => 'text/css',
      'yaml' || 'yml' => 'text/yaml',
      'xml' => 'text/xml',
      'zip' => 'application/zip',
      _ => 'application/octet-stream',
    };
  }
}

class _PickerOption extends StatelessWidget {
  const _PickerOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onTap: onTap,
    );
  }
}

/// A preview strip shown above the input bar when attachments are pending.
class AttachmentPreviewStrip extends StatelessWidget {
  const AttachmentPreviewStrip({
    super.key,
    required this.attachments,
    required this.onRemove,
  });

  final List<Attachment> attachments;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, index) {
          final attachment = attachments[index];
          return _AttachmentThumbnail(
            attachment: attachment,
            onRemove: () => onRemove(index),
          );
        },
      ),
    );
  }
}

class _AttachmentThumbnail extends StatelessWidget {
  const _AttachmentThumbnail({
    required this.attachment,
    required this.onRemove,
  });

  final Attachment attachment;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: attachment.isImage && attachment.bytes != null
              ? Image.memory(
                  Uint8List.fromList(attachment.bytes!),
                  fit: BoxFit.cover,
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.insert_drive_file,
                      size: 24,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        attachment.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        // Remove button
        Positioned(
          top: -4,
          right: -4,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 12,
                color: theme.colorScheme.onError,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
