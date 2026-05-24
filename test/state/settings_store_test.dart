import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/state/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('isConfigured only requires a gateway base URL', () async {
    SharedPreferences.setMockInitialValues({
      'oc.baseUrl': 'http://127.0.0.1:4096',
      'oc.providerId': '',
      'oc.modelId': '',
    });
    final prefs = await SharedPreferences.getInstance();
    final controller = SettingsController(prefs);

    expect(controller.state.isConfigured, isTrue);
  });

  test('persists selected profile and default model per agent', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final controller = SettingsController(prefs);

    await controller.update(
      controller.state.copyWith(
        themeMode: ThemeMode.dark,
        selectedProfileByAgent: const {
          'codex': 'profile-openai',
          'claude-code': 'profile-anthropic',
        },
        defaultModelByAgent: const {
          'codex': 'openai/gpt-5',
          'claude-code': 'anthropic/claude-sonnet-4-5',
        },
      ),
    );

    final reloaded = SettingsController(prefs).state;

    expect(reloaded.selectedProfileByAgent['codex'], 'profile-openai');
    expect(reloaded.selectedProfileByAgent['claude-code'], 'profile-anthropic');
    expect(reloaded.defaultModelByAgent['codex'], 'openai/gpt-5');
    expect(
      reloaded.defaultModelByAgent['claude-code'],
      'anthropic/claude-sonnet-4-5',
    );
    expect(reloaded.themeMode, ThemeMode.dark);
  });
}
