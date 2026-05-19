/// Tracks codex threads on the *client* side (the server is process-spawn,
/// it has no persistent thread registry beyond what's currently running).
///
/// Each thread is a {threadId, directory, title, lastTouched} tuple persisted
/// to SharedPreferences. We treat this as the equivalent of OpenCode's
/// `/session` list endpoint.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'settings_store.dart';

@immutable
class CodexThread {
  const CodexThread({
    required this.localKey,
    this.threadId,
    required this.directory,
    required this.title,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  /// Stable client-side id (UUID). Unlike threadId, this exists immediately
  /// upon creation, before any server interaction.
  final String localKey;

  /// Server-side codex thread id (UUID). Empty until the first
  /// `thread.started` event.
  final String? threadId;

  final String directory;
  final String title;
  final int createdAtMs;
  final int updatedAtMs;

  CodexThread copyWith({
    String? threadId,
    String? title,
    int? updatedAtMs,
  }) =>
      CodexThread(
        localKey: localKey,
        threadId: threadId ?? this.threadId,
        directory: directory,
        title: title ?? this.title,
        createdAtMs: createdAtMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
      );

  Map<String, dynamic> toJson() => {
        'localKey': localKey,
        'threadId': threadId,
        'directory': directory,
        'title': title,
        'createdAtMs': createdAtMs,
        'updatedAtMs': updatedAtMs,
      };

  factory CodexThread.fromJson(Map<String, dynamic> j) => CodexThread(
        localKey: j['localKey'] as String? ?? '',
        threadId: j['threadId'] as String?,
        directory: j['directory'] as String? ?? '',
        title: j['title'] as String? ?? '(untitled)',
        createdAtMs: (j['createdAtMs'] as num?)?.toInt() ?? 0,
        updatedAtMs: (j['updatedAtMs'] as num?)?.toInt() ?? 0,
      );
}

@immutable
class CodexThreadListState {
  const CodexThreadListState({required this.items});
  final List<CodexThread> items;
  static const empty = CodexThreadListState(items: []);
}

class CodexThreadListController extends StateNotifier<CodexThreadListState> {
  CodexThreadListController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;
  static const _kKey = 'codex.threads';

  static CodexThreadListState _load(SharedPreferences p) {
    final raw = p.getString(_kKey);
    if (raw == null || raw.isEmpty) return CodexThreadListState.empty;
    try {
      final list = (jsonDecode(raw) as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(CodexThread.fromJson)
          .toList();
      list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      return CodexThreadListState(items: list);
    } catch (_) {
      return CodexThreadListState.empty;
    }
  }

  Future<void> _persist() async {
    await _prefs.setString(
      _kKey,
      jsonEncode(state.items.map((t) => t.toJson()).toList()),
    );
  }

  Future<CodexThread> create({
    required String directory,
    String? initialTitle,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final t = CodexThread(
      localKey: 'lk_${now}_${state.items.length}',
      threadId: null,
      directory: directory,
      title: initialTitle ?? 'New thread',
      createdAtMs: now,
      updatedAtMs: now,
    );
    state = CodexThreadListState(items: [t, ...state.items]);
    await _persist();
    return t;
  }

  Future<void> updateThreadId(String localKey, String threadId) async {
    final next = state.items.map((t) {
      if (t.localKey != localKey) return t;
      return t.copyWith(
        threadId: threadId,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();
    state = CodexThreadListState(items: next);
    await _persist();
  }

  Future<void> rename(String localKey, String title) async {
    final next = state.items.map((t) {
      if (t.localKey != localKey) return t;
      return t.copyWith(
        title: title,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
      );
    }).toList();
    state = CodexThreadListState(items: next);
    await _persist();
  }

  Future<void> touch(String localKey) async {
    final next = state.items.map((t) {
      if (t.localKey != localKey) return t;
      return t.copyWith(updatedAtMs: DateTime.now().millisecondsSinceEpoch);
    }).toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    state = CodexThreadListState(items: next);
    await _persist();
  }

  Future<void> delete(String localKey) async {
    state = CodexThreadListState(
      items: state.items.where((t) => t.localKey != localKey).toList(),
    );
    await _persist();
  }
}

final codexThreadListProvider =
    StateNotifierProvider<CodexThreadListController, CodexThreadListState>(
        (ref) {
  final prefs = ref.watch(sharedPreferencesProvider).maybeWhen(
        data: (v) => v,
        orElse: () => null,
      );
  if (prefs == null) {
    throw StateError('SharedPreferences not yet ready');
  }
  return CodexThreadListController(prefs);
});
