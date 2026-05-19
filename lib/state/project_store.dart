library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gateway_client.dart';
import '../models/project.dart';
import 'gateway_client_provider.dart';

@immutable
class ProjectState {
  const ProjectState({
    required this.projects,
    required this.selectedProjectId,
    required this.loading,
    this.error,
  });

  final List<Project> projects;
  final String? selectedProjectId;
  final bool loading;
  final String? error;

  ProjectState copyWith({
    List<Project>? projects,
    String? selectedProjectId,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      ProjectState(
        projects: projects ?? this.projects,
        selectedProjectId: selectedProjectId ?? this.selectedProjectId,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class ProjectStore extends StateNotifier<ProjectState> {
  ProjectStore({required GatewayClient client})
      : _client = client,
        super(
          const ProjectState(
            projects: [],
            selectedProjectId: null,
            loading: true,
          ),
        ) {
    refresh();
  }

  final GatewayClient _client;

  Future<void> refresh() async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final projects = await _client.listProjects();
      state = state.copyWith(
        projects: projects,
        selectedProjectId: state.selectedProjectId ??
            (projects.isEmpty ? null : projects.first.id),
        loading: false,
      );
    } catch (error) {
      state = state.copyWith(loading: false, error: error.toString());
    }
  }

  Future<Project> addProject(String directory) async {
    final project = await _client.createProject(
      directory: directory,
      name: _shortDirName(directory),
    );
    final projects = [
      project,
      ...state.projects.where((p) => p.id != project.id),
    ];
    state = state.copyWith(
      projects: projects,
      selectedProjectId: project.id,
      clearError: true,
    );
    return project;
  }

  void selectProject(String? projectId) {
    state = ProjectState(
      projects: state.projects,
      selectedProjectId: projectId,
      loading: state.loading,
    );
  }
}

String _shortDirName(String path) {
  final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

final projectStoreProvider =
    StateNotifierProvider<ProjectStore, ProjectState>((ref) {
  final client = ref.watch(gatewayClientProvider);
  return ProjectStore(client: client);
});
