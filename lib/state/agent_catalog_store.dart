library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gateway_client.dart';
import '../models/agent.dart';
import 'gateway_client_provider.dart';

@immutable
class AgentCatalogState {
  const AgentCatalogState({
    required this.agents,
    required this.selectedAgentId,
    required this.loading,
    this.error,
  });

  final List<Agent> agents;
  final String? selectedAgentId;
  final bool loading;
  final String? error;

  AgentCatalogState copyWith({
    List<Agent>? agents,
    String? selectedAgentId,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      AgentCatalogState(
        agents: agents ?? this.agents,
        selectedAgentId: selectedAgentId ?? this.selectedAgentId,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class AgentCatalogStore extends StateNotifier<AgentCatalogState> {
  AgentCatalogStore({required GatewayClient client})
      : _client = client,
        super(
          const AgentCatalogState(
            agents: [],
            selectedAgentId: null,
            loading: true,
          ),
        ) {
    refresh();
  }

  final GatewayClient _client;

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final listedAgents = await _client.listAgents();
      final agents = await Future.wait(
        listedAgents.map((agent) async {
          if (!agent.supportsModels) return agent;
          try {
            final models = await _client.listAgentModels(agent.id);
            return Agent(
              id: agent.id,
              displayName: agent.displayName,
              supportsModels: agent.supportsModels,
              supportsSlashCommands: agent.supportsSlashCommands,
              supportsAttachments: agent.supportsAttachments,
              supportsPermissions: agent.supportsPermissions,
              sessionKind: agent.sessionKind,
              commands: agent.commands,
              raw: <String, dynamic>{
                ...agent.raw,
                'models':
                    models.map((model) => model.raw).toList(growable: false),
              },
            );
          } catch (_) {
            return agent;
          }
        }),
      );
      state = state.copyWith(
        agents: agents,
        selectedAgentId:
            state.selectedAgentId ?? (agents.isEmpty ? null : agents.first.id),
        loading: false,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  void selectAgent(String? agentId) {
    state = AgentCatalogState(
      agents: state.agents,
      selectedAgentId: agentId,
      loading: state.loading,
    );
  }

  Future<List<AgentModel>> modelsFor(String agentId, {String? profileId}) =>
      _client.listAgentModels(agentId, profileId: profileId);

  Future<List<AgentCommand>> commandsFor(
    String agentId, {
    String? projectId,
  }) =>
      _client.listAgentCommands(agentId, projectId: projectId);
}

final agentCatalogStoreProvider =
    StateNotifierProvider<AgentCatalogStore, AgentCatalogState>((ref) {
  final client = ref.watch(gatewayClientProvider);
  return AgentCatalogStore(client: client);
});

final agentCatalogProvider = agentCatalogStoreProvider;
