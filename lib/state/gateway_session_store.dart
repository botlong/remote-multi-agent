library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gateway_client.dart';
import '../models/gateway_session.dart';
import 'gateway_client_provider.dart';

@immutable
class GatewaySessionState {
  const GatewaySessionState({
    required this.projectId,
    required this.sessions,
    required this.loading,
    this.selectedSessionId,
    this.error,
  });

  final String projectId;
  final List<GatewaySession> sessions;
  final String? selectedSessionId;
  final bool loading;
  final String? error;

  GatewaySessionState copyWith({
    String? projectId,
    List<GatewaySession>? sessions,
    String? selectedSessionId,
    bool clearSelectedSession = false,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      GatewaySessionState(
        projectId: projectId ?? this.projectId,
        sessions: sessions ?? this.sessions,
        selectedSessionId: clearSelectedSession
            ? null
            : (selectedSessionId ?? this.selectedSessionId),
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class GatewaySessionStore extends StateNotifier<GatewaySessionState> {
  GatewaySessionStore({
    required GatewayClient client,
    required String projectId,
  })  : _client = client,
        super(
          GatewaySessionState(
            projectId: projectId,
            sessions: const [],
            loading: true,
          ),
        ) {
    refresh();
  }

  final GatewayClient _client;

  Future<void> refresh() async {
    if (state.projectId.isEmpty) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final sessions = await _client.listProjectSessions(state.projectId);
      state = state.copyWith(
        sessions: sessions,
        selectedSessionId: state.selectedSessionId ??
            (sessions.isEmpty ? null : sessions.first.id),
        loading: false,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  Future<GatewaySession> createSession({
    required String agentId,
    String? modelId,
    String? sandbox,
    String? permissionMode,
  }) async {
    final session = await _client.createSession(
      projectId: state.projectId,
      agentId: agentId,
      modelId: modelId,
      sandbox: sandbox,
      permissionMode: permissionMode,
    );
    final sessions = [
      session,
      ...state.sessions.where((s) => s.id != session.id),
    ];
    state = state.copyWith(
      sessions: sessions,
      selectedSessionId: session.id,
      clearError: true,
    );
    return session;
  }

  Future<void> renameSession(String sessionId, String newTitle) async {
    await _client.updateSession(sessionId, title: newTitle);
    final sessions = state.sessions.map((s) {
      if (s.id == sessionId) {
        return GatewaySession(
          id: s.id,
          projectId: s.projectId,
          agentId: s.agentId,
          title: newTitle,
          modelId: s.modelId,
          status: s.status,
          agentSessionId: s.agentSessionId,
          createdAtMs: s.createdAtMs,
          updatedAtMs: DateTime.now().millisecondsSinceEpoch,
          raw: s.raw,
        );
      }
      return s;
    }).toList();
    state = state.copyWith(sessions: sessions);
  }

  Future<void> deleteSession(String sessionId) async {
    await _client.deleteSession(sessionId);
    final sessions = state.sessions.where((s) => s.id != sessionId).toList();
    final selected = state.selectedSessionId == sessionId
        ? (sessions.isEmpty ? null : sessions.first.id)
        : state.selectedSessionId;
    state = state.copyWith(sessions: sessions, selectedSessionId: selected);
  }

  void selectSession(String? sessionId) {
    state = GatewaySessionState(
      projectId: state.projectId,
      sessions: state.sessions,
      selectedSessionId: sessionId,
      loading: state.loading,
    );
  }
}

final gatewaySessionStoreProvider = StateNotifierProvider.family<
    GatewaySessionStore, GatewaySessionState, String>(
  (ref, projectId) {
    final client = ref.watch(gatewayClientProvider);
    return GatewaySessionStore(client: client, projectId: projectId);
  },
);

final gatewaySessionListProvider = gatewaySessionStoreProvider;
