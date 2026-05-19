import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/settings_store.dart';
import '../theme.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';

class OpencodeMobileApp extends ConsumerWidget {
  const OpencodeMobileApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(sharedPreferencesProvider);
    return MaterialApp(
      title: 'OpenCode Mobile',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: prefs.maybeWhen(
        data: (_) => ref.watch(settingsControllerProvider).themeMode,
        orElse: () => ThemeMode.system,
      ),
      home: prefs.when(
        loading: () => const _SplashScreen(),
        error: (e, _) => _ErrorScreen(error: e),
        data: (_) {
          final settings = ref.watch(settingsControllerProvider);
          // First run → always go to settings so the user can punch in URL.
          if (!settings.isConfigured) return const SettingsPage(firstRun: true);
          return const HomePage();
        },
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to start: $error'),
          ),
        ),
      );
}
