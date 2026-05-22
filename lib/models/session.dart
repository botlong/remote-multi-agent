/// Domain model for an OpenCode session.
///
/// Source: `GET /session` (list) and `session.updated` SSE events.
library;

import 'package:flutter/foundation.dart';

@immutable
class Session {
  const Session({
    required this.id,
    required this.slug,
    required this.title,
    required this.directory,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.agent,
    this.modelId,
    this.providerId,
    this.cost = 0.0,
    this.tokens,
  });

  final String id;
  final String slug;
  final String title;
  final String directory;
  final int createdAtMs;
  final int updatedAtMs;
  final String? agent;
  final String? modelId;
  final String? providerId;
  final double cost;
  final SessionTokens? tokens;

  factory Session.fromJson(Map<String, dynamic> json) {
    final time = (json['time'] as Map?) ?? const {};
    final model = (json['model'] as Map?) ?? const {};
    return Session(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      title: json['title'] as String? ?? '',
      directory: json['directory'] as String? ?? '',
      createdAtMs: (time['created'] as int?) ?? 0,
      updatedAtMs: (time['updated'] as int?) ?? 0,
      agent: json['agent'] as String?,
      modelId: model['id'] as String?,
      providerId: model['providerID'] as String?,
      cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
      tokens: json['tokens'] is Map
          ? SessionTokens.fromJson(
              (json['tokens'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }
}

@immutable
class SessionTokens {
  const SessionTokens({
    required this.input,
    required this.output,
    required this.reasoning,
    required this.cacheRead,
    required this.cacheWrite,
  });

  final int input;
  final int output;
  final int reasoning;
  final int cacheRead;
  final int cacheWrite;

  int get total => input + output + reasoning;

  factory SessionTokens.fromJson(Map<String, dynamic> json) {
    final cache = (json['cache'] as Map?) ?? const {};
    return SessionTokens(
      input: (json['input'] as num?)?.toInt() ?? 0,
      output: (json['output'] as num?)?.toInt() ?? 0,
      reasoning: (json['reasoning'] as num?)?.toInt() ?? 0,
      cacheRead: (cache['read'] as num?)?.toInt() ?? 0,
      cacheWrite: (cache['write'] as num?)?.toInt() ?? 0,
    );
  }
}
