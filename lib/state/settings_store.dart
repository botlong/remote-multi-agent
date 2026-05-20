/// Persistent connection settings (server URL, bearer token, default model).
///
/// Stored in SharedPreferences so the app remembers them across launches.
/// We avoid a heavier secure-storage dep on purpose — the server runs on the
/// user's own LAN/Tailscale, and the bearer token is just OPENCODE_SERVER_PASSWORD.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppSettings {
  const AppSettings({
    required this.baseUrl,
    required this.bearerToken,
    required this.providerId,
    required this.modelId,
    this.themeMode = ThemeMode.system,
  });

  final String baseUrl;
  final String bearerToken;
  final String providerId;
  final String modelId;
  final ThemeMode themeMode;

  bool get isConfigured =>
      baseUrl.isNotEmpty && providerId.isNotEmpty && modelId.isNotEmpty;

  AppSettings copyWith({
    String? baseUrl,
    String? bearerToken,
    String? providerId,
    String? modelId,
    ThemeMode? themeMode,
  }) =>
      AppSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        bearerToken: bearerToken ?? this.bearerToken,
        providerId: providerId ?? this.providerId,
        modelId: modelId ?? this.modelId,
        themeMode: themeMode ?? this.themeMode,
      );

  static const empty = AppSettings(
    baseUrl: 'http://127.0.0.1:4096',
    bearerToken: '',
    providerId: 'opencode',
    modelId: 'big-pickle',
  );
}

class SettingsController extends StateNotifier<AppSettings> {
  SettingsController(this._prefs) : super(_load(_prefs));

  final SharedPreferences _prefs;

  static AppSettings _load(SharedPreferences p) {
    final themeModeIndex = p.getInt(_kThemeMode);
    return AppSettings(
      baseUrl: p.getString(_kBaseUrl) ?? AppSettings.empty.baseUrl,
      bearerToken: p.getString(_kToken) ?? '',
      providerId: p.getString(_kProvider) ?? AppSettings.empty.providerId,
      modelId: p.getString(_kModel) ?? AppSettings.empty.modelId,
      themeMode: themeModeIndex != null && themeModeIndex < ThemeMode.values.length
          ? ThemeMode.values[themeModeIndex]
          : ThemeMode.system,
    );
  }

  Future<void> update(AppSettings next) async {
    state = next;
    await Future.wait([
      _prefs.setString(_kBaseUrl, next.baseUrl),
      _prefs.setString(_kToken, next.bearerToken),
      _prefs.setString(_kProvider, next.providerId),
      _prefs.setString(_kModel, next.modelId),
      _prefs.setInt(_kThemeMode, next.themeMode.index),
    ]);
  }

  static const _kBaseUrl = 'oc.baseUrl';
  static const _kToken = 'oc.bearerToken';
  static const _kProvider = 'oc.providerId';
  static const _kModel = 'oc.modelId';
  static const _kThemeMode = 'oc.themeMode';
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
