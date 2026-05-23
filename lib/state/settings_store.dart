/// Persistent connection settings for the trusted LAN gateway.
///
/// Stored in SharedPreferences so the app remembers them across launches.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    required this.baseUrl,
    required this.providerId,
    required this.modelId,
    this.themeMode = ThemeMode.system,
    this.lastAgentId = '',
    this.lastModelId = '',
    this.lastSessionId = '',
    this.lastProjectId = '',
  });

  final String baseUrl;
  final String providerId;
  final String modelId;
  final ThemeMode themeMode;

  /// Last-used preferences for quick restore.
  final String lastAgentId;
  final String lastModelId;
  final String lastSessionId;
  final String lastProjectId;

  bool get isConfigured =>
      baseUrl.isNotEmpty && providerId.isNotEmpty && modelId.isNotEmpty;

  AppSettings copyWith({
    String? baseUrl,
    String? providerId,
    String? modelId,
    ThemeMode? themeMode,
    String? lastAgentId,
    String? lastModelId,
    String? lastSessionId,
    String? lastProjectId,
  }) =>
      AppSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        providerId: providerId ?? this.providerId,
        modelId: modelId ?? this.modelId,
        themeMode: themeMode ?? this.themeMode,
        lastAgentId: lastAgentId ?? this.lastAgentId,
        lastModelId: lastModelId ?? this.lastModelId,
        lastSessionId: lastSessionId ?? this.lastSessionId,
        lastProjectId: lastProjectId ?? this.lastProjectId,
      );

  static const empty = AppSettings(
    baseUrl: 'http://127.0.0.1:4096',
    providerId: 'opencode',
    modelId: 'big-pickle',
  );
}

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._prefs) : super(_load(_prefs)) {
    _prefs.remove(_kLegacyToken);
  }

  final SharedPreferences _prefs;

  static AppSettings _load(SharedPreferences p) {
    final themeModeIndex = p.getInt(_kThemeMode);
    return AppSettings(
      baseUrl: p.getString(_kBaseUrl) ?? AppSettings.empty.baseUrl,
      providerId: p.getString(_kProvider) ?? AppSettings.empty.providerId,
      modelId: p.getString(_kModel) ?? AppSettings.empty.modelId,
      themeMode: themeModeIndex != null && themeModeIndex < ThemeMode.values.length
          ? ThemeMode.values[themeModeIndex]
          : ThemeMode.system,
      lastAgentId: p.getString(_kLastAgent) ?? '',
      lastModelId: p.getString(_kLastModel) ?? '',
      lastSessionId: p.getString(_kLastSession) ?? '',
      lastProjectId: p.getString(_kLastProject) ?? '',
    );
  }

  Future<void> update(AppSettings next) async {
    state = next;
    await Future.wait([
      _prefs.setString(_kBaseUrl, next.baseUrl),
      _prefs.setString(_kProvider, next.providerId),
      _prefs.setString(_kModel, next.modelId),
      _prefs.setInt(_kThemeMode, next.themeMode.index),
      _prefs.setString(_kLastAgent, next.lastAgentId),
      _prefs.setString(_kLastModel, next.lastModelId),
      _prefs.setString(_kLastSession, next.lastSessionId),
      _prefs.setString(_kLastProject, next.lastProjectId),
    ]);
  }

  /// Update last-used preferences. Only saves the keys that changed.
  Future<void> setLastUsed({
    String? agentId,
    String? modelId,
    String? sessionId,
    String? projectId,
  }) async {
    state = state.copyWith(
      lastAgentId: agentId ?? state.lastAgentId,
      lastModelId: modelId ?? state.lastModelId,
      lastSessionId: sessionId ?? state.lastSessionId,
      lastProjectId: projectId ?? state.lastProjectId,
    );
    final futures = <Future<bool>>[];
    if (agentId != null) futures.add(_prefs.setString(_kLastAgent, agentId));
    if (modelId != null) futures.add(_prefs.setString(_kLastModel, modelId));
    if (sessionId != null) {
      futures.add(_prefs.setString(_kLastSession, sessionId));
    }
    if (projectId != null) {
      futures.add(_prefs.setString(_kLastProject, projectId));
    }
    await Future.wait(futures);
  }

  static const _kBaseUrl = 'oc.baseUrl';
  static const _kLegacyToken = 'oc.bearerToken';
  static const _kProvider = 'oc.providerId';
  static const _kModel = 'oc.modelId';
  static const _kThemeMode = 'oc.themeMode';
  static const _kLastAgent = 'oc.lastAgentId';
  static const _kLastModel = 'oc.lastModelId';
  static const _kLastSession = 'oc.lastSessionId';
  static const _kLastProject = 'oc.lastProjectId';
}

/// Top-level provider. The async dependency is solved with [FutureProvider],
/// then we hang the controller off a synchronous provider for ergonomics.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>(
  (ref) => SharedPreferences.getInstance(),
);

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, AppSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).maybeWhen(
        data: (v) => v,
        orElse: () => null,
      );
  if (prefs == null) {
    throw StateError(
      'SharedPreferences not yet ready — wrap consumers in a Skeleton',
    );
  }
  return SettingsController(prefs);
});
