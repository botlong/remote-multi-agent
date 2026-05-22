/// Domain model for the *parts* an OpenCode message is composed of.
///
/// Wire reference (from /event SSE):
///   message.part.updated → properties.part: {
///     id, messageID, sessionID, type, ...payload
///   }
///
/// We model `Part` as a sealed class so the UI can pattern-match on type.
/// New part types are easy to add — extend `Part` with another subclass.
library;

import 'package:flutter/foundation.dart';

@immutable
sealed class Part {
  const Part({
    required this.id,
    required this.messageId,
    required this.sessionId,
  });

  final String id;
  final String messageId;
  final String sessionId;

  /// Best-effort decoder from raw JSON payload (the `properties.part` field
  /// of `message.part.updated`). Falls back to [UnknownPart] when the type is
  /// unrecognised so we never drop unfamiliar events on the floor.
  factory Part.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final messageId = json['messageID'] as String? ?? '';
    final sessionId = json['sessionID'] as String? ?? '';
    final type = json['type'] as String?;

    switch (type) {
      case 'text':
        return TextPart(
          id: id,
          messageId: messageId,
          sessionId: sessionId,
          text: json['text'] as String? ?? '',
        );
      case 'reasoning':
        return ReasoningPart(
          id: id,
          messageId: messageId,
          sessionId: sessionId,
          text: json['text'] as String? ?? '',
        );
      case 'tool':
        final state = json['state'] as Map<String, dynamic>?;
        final toolName = json['tool'] as String?
            ?? json['name'] as String?
            ?? state?['tool'] as String?
            ?? 'unknown';
        final toolStatus = json['status'] as String?
            ?? state?['status'] as String?;
        final inputRaw = json['input'] ?? state?['input'];
        final Map<String, dynamic>? inputMap = inputRaw is Map
            ? inputRaw.cast<String, dynamic>()
            : inputRaw is String && inputRaw.isNotEmpty
                ? <String, dynamic>{'command': inputRaw}
                : null;
        final outputRaw = json['output'] ?? state?['output'];
        return ToolPart(
          id: id,
          messageId: messageId,
          sessionId: sessionId,
          tool: toolName,
          status: ToolStatus.from(toolStatus),
          input: inputMap,
          output: outputRaw,
          error: json['error'] as String? ?? state?['error'] as String?,
        );
      case 'image':
        return ImagePart(
          id: id,
          messageId: messageId,
          sessionId: sessionId,
          image: json['image'] as String? ?? '',
          alt: json['alt'] as String?,
        );
      case 'file':
        return FilePart(
          id: id,
          messageId: messageId,
          sessionId: sessionId,
          fileName: json['fileName'] as String? ?? 'file',
          mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
          data: json['data'] as String?,
          path: json['path'] as String?,
        );
      case 'step-start':
        return StepStartPart(
          id: id,
          messageId: messageId,
          sessionId: sessionId,
        );
      case 'step-finish':
        return StepFinishPart(
          id: id,
          messageId: messageId,
          sessionId: sessionId,
        );
      default:
        return UnknownPart(
          id: id,
          messageId: messageId,
          sessionId: sessionId,
          rawType: type ?? 'unknown',
          raw: json,
        );
    }
  }
}

/// Pure text fragment (the assistant's main response body).
class TextPart extends Part {
  const TextPart({
    required super.id,
    required super.messageId,
    required super.sessionId,
    required this.text,
  });

  final String text;
}

/// Internal reasoning trace (rendered collapsed by default).
class ReasoningPart extends Part {
  const ReasoningPart({
    required super.id,
    required super.messageId,
    required super.sessionId,
    required this.text,
  });

  final String text;
}

enum ToolStatus {
  pending,
  running,
  completed,
  error;

  static ToolStatus from(String? raw) => switch (raw) {
        'pending' => ToolStatus.pending,
        'running' => ToolStatus.running,
        'completed' => ToolStatus.completed,
        'error' => ToolStatus.error,
        _ => ToolStatus.pending,
      };

  bool get isTerminal => this == completed || this == error;
}

/// A tool invocation (bash, file read/write, web fetch …).
class ToolPart extends Part {
  const ToolPart({
    required super.id,
    required super.messageId,
    required super.sessionId,
    required this.tool,
    required this.status,
    this.input,
    this.output,
    this.error,
  });

  final String tool;
  final ToolStatus status;
  final Map<String, dynamic>? input;
  final Object? output;
  final String? error;
}

/// An image sent by the agent or user.
/// [image] can be:
///   - A data URL: `data:image/png;base64,...`
///   - A server file path (loaded via `/files/read?path=...`)
///   - A regular HTTP(S) URL
class ImagePart extends Part {
  const ImagePart({
    required super.id,
    required super.messageId,
    required super.sessionId,
    required this.image,
    this.alt,
  });

  /// The image source — data URL, file path, or HTTP URL.
  final String image;

  /// Optional alt text / description.
  final String? alt;

  /// Whether this is a base64 data URL.
  bool get isDataUrl => image.startsWith('data:');

  /// Whether this looks like a server-side file path (not a URL).
  bool get isFilePath =>
      !image.startsWith('data:') &&
      !image.startsWith('http://') &&
      !image.startsWith('https://');
}

/// A file attachment (from user or agent).
class FilePart extends Part {
  const FilePart({
    required super.id,
    required super.messageId,
    required super.sessionId,
    required this.fileName,
    required this.mimeType,
    this.data,
    this.path,
  });

  final String fileName;
  final String mimeType;

  /// Base64-encoded file content (for inline attachments).
  final String? data;

  /// Server-side file path (alternative to inline data).
  final String? path;

  bool get isImage => mimeType.startsWith('image/');
}

/// LLM step boundary markers — useful for separating "turns" inside one message.
class StepStartPart extends Part {
  const StepStartPart({
    required super.id,
    required super.messageId,
    required super.sessionId,
  });
}

class StepFinishPart extends Part {
  const StepFinishPart({
    required super.id,
    required super.messageId,
    required super.sessionId,
  });
}

/// Fallback for parts whose type we don't yet know how to render. We keep the
/// raw payload so the UI can show a debug view in dev builds.
class UnknownPart extends Part {
  const UnknownPart({
    required super.id,
    required super.messageId,
    required super.sessionId,
    required this.rawType,
    required this.raw,
  });

  final String rawType;
  final Map<String, dynamic> raw;
}
