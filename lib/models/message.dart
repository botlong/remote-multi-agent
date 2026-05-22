/// Domain model for an OpenCode message.
///
/// Wire reference: properties.info from `message.updated` events.
/// Unlike [Part]s, messages are flat metadata + an ordered list of parts that
/// gets filled in by subsequent `message.part.updated` events.
library;

import 'package:flutter/foundation.dart';

import 'part.dart';

enum MessageRole { user, assistant, system, unknown }

enum MessageStatus { pending, running, completed, error, unknown }

@immutable
class Message {
  const Message({
    required this.id,
    required this.role,
    required this.sessionId,
    required this.status,
    required this.parts,
    this.createdAtMs,
    this.completedAtMs,
    this.modelId,
    this.providerId,
  });

  final String id;
  final MessageRole role;
  final String sessionId;
  final MessageStatus status;

  /// Parts in arrival order. Map for O(1) updates by id; we expose insertion
  /// order via [orderedParts].
  final Map<String, Part> parts;
  final int? createdAtMs;
  final int? completedAtMs;
  final String? modelId;
  final String? providerId;

  Iterable<Part> get orderedParts => parts.values;

  factory Message.fromJson(Map<String, dynamic> json) {
    // The history endpoint wraps each message as { info: {...}, parts: [...] }
    // while SSE events send the info fields directly. Handle both.
    final Map<String, dynamic> info;
    final List<dynamic> rawParts;
    if (json.containsKey('info') && json['info'] is Map) {
      info = (json['info'] as Map).cast<String, dynamic>();
      rawParts = json['parts'] as List<dynamic>? ?? const [];
    } else {
      info = json;
      rawParts = json['parts'] as List<dynamic>? ?? const [];
    }

    final parsedParts = <String, Part>{};
    for (final p in rawParts.whereType<Map<String, dynamic>>()) {
      final part = Part.fromJson(p);
      if (part.id.isNotEmpty) {
        parsedParts[part.id] = part;
      }
    }

    return Message(
      id: info['id'] as String? ?? '',
      role: switch (info['role']) {
        'user' => MessageRole.user,
        'assistant' => MessageRole.assistant,
        'system' => MessageRole.system,
        _ => MessageRole.unknown,
      },
      sessionId: info['sessionID'] as String? ?? '',
      status: switch (info['status']) {
        'pending' => MessageStatus.pending,
        'running' => MessageStatus.running,
        'completed' => MessageStatus.completed,
        'error' => MessageStatus.error,
        _ => MessageStatus.unknown,
      },
      parts: parsedParts,
      createdAtMs: (info['time'] as Map?)?['created'] as int?,
      completedAtMs: (info['time'] as Map?)?['completed'] as int?,
      modelId: info['modelID'] as String? ??
          (info['model'] as Map?)?['id'] as String?,
      providerId: info['providerID'] as String? ??
          (info['model'] as Map?)?['providerID'] as String?,
    );
  }

  Message copyWith({
    String? id,
    MessageRole? role,
    String? sessionId,
    MessageStatus? status,
    Map<String, Part>? parts,
    int? createdAtMs,
    int? completedAtMs,
    String? modelId,
    String? providerId,
  }) {
    return Message(
      id: id ?? this.id,
      role: role ?? this.role,
      sessionId: sessionId ?? this.sessionId,
      status: status ?? this.status,
      parts: parts ?? this.parts,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      completedAtMs: completedAtMs ?? this.completedAtMs,
      modelId: modelId ?? this.modelId,
      providerId: providerId ?? this.providerId,
    );
  }

  Message withPartUpsert(Part part) {
    final next = Map<String, Part>.from(parts);
    next[part.id] = part;
    return copyWith(parts: next);
  }
}
