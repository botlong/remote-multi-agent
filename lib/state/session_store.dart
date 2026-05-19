/// Loads and refreshes the session list. Driven both by an explicit refresh
/// and by `session.updated` SSE events.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/opencode_client.dart';
import '../api/sse_stream.dart';
import '../models/session.dart';
import 'providers.dart';

@immutable
class SessionListState {
  const SessionListState({
    required this.items,
    required this.loading,
    this.error,
  });

  final List<Session> items;
  final bool loading;
  final String? error;

  SessionListState copyWith({
    List<Session>? items,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      SessionListState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );

  static const initial = SessionListState(items: [], loading: true);
}

class SessionListController extends StateNotifier<SessionListState> {
  SessionListController({required this.client, required this.sse})
      : super(SessionListState.initial) {
    refresh();
    _sub = sse.events.listen(_onEvent);
  }

  final OpencodeClient client;
  final SseClient sse;
  late final StreamSubscription<SseEvent> _sub;

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final items = await client.listSessions();
      items.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
      state = state.copyWith(items: items, loading: false);
    } catch (err) {
      state = state.copyWith(loading: false, error: '$err');
    }
  }

  Future<Session> createSession({String? directory}) async {
    final s = await client.createSession(directory: directory);
    state = state.copyWith(items: [s, ...state.items]);
    return s;
  }

  Future<void> renameSession(String sessionId, String newTitle) async {
    await client.renameSession(sessionId, newTitle);
    final next = [...state.items];
    final idx = next.indexWhere((s) => s.id == sessionId);
    if (idx != -1) {
      final old = next[idx];
      next[idx] = Session(
        id: old.id,
        slug: old.slug,
        title: newTitle,
        directory: old.directory,
        createdAtMs: old.createdAtMs,
        updatedAtMs: DateTime.now().millisecondsSinceEpoch,
        agent: old.agent,
        modelId: old.modelId,
        providerId: old.providerId,
        cost: old.cost,
        tokens: old.tokens,
      );
    }
    state = state.copyWith(items: next);
  }

  Future<void> deleteSession(String sessionId) async {
    await client.deleteSession(sessionId);
    final next = state.items.where((s) => s.id != sessionId).toList();
    state = state.copyWith(items: next);
  }

  void _onEvent(SseEvent ev) {
    final type = ev.data['type'] as String? ?? ev.type;
    if (type != 'session.updated') return;
    final info = ((ev.data['properties'] as Map?)?['info'] as Map?)
        ?.cast<String, dynamic>();
    if (info == null) return;
    final updated = Session.fromJson(info);
    final next = [...state.items];
    final idx = next.indexWhere((s) => s.id == updated.id);
    if (idx == -1) {
      next.insert(0, updated);
    } else {
      next[idx] = updated;
      next.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    }
    state = state.copyWith(items: next);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final sessionListControllerProvider =
    StateNotifierProvider<SessionListController, SessionListState>((ref) {
  final client = ref.watch(opencodeClientProvider);
  final sse = ref.watch(sseClientProvider);
  return SessionListController(client: client, sse: sse);
});
