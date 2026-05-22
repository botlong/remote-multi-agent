import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/gateway_client_provider.dart';
import '../../state/settings_store.dart';
import 'chat_tab.dart';
import 'files_page.dart';
import 'gateway_chat_page.dart';
import 'gateway_ui_adapters.dart';
import 'git_page.dart';
import 'settings_page.dart';

/// Root shell after first-run configuration. Houses a Material 3
/// [NavigationBar] with 4 tabs and preserves state across switches
/// via [IndexedStack].
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;
  bool _attemptedRestore = false;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.workspaces_outlined),
      selectedIcon: Icon(Icons.workspaces),
      label: 'Projects',
    ),
    NavigationDestination(
      icon: Icon(Icons.difference_outlined),
      selectedIcon: Icon(Icons.difference),
      label: 'Git',
    ),
    NavigationDestination(
      icon: Icon(Icons.snippet_folder_outlined),
      selectedIcon: Icon(Icons.snippet_folder),
      label: 'Files',
    ),
    NavigationDestination(
      icon: Icon(Icons.tune_outlined),
      selectedIcon: Icon(Icons.tune),
      label: 'Settings',
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryRestoreLastSession();
    });
  }

  /// Best-effort restore: if a lastSessionId is saved, try to fetch it and
  /// navigate directly to the chat page. Falls back silently on any error.
  Future<void> _tryRestoreLastSession() async {
    if (_attemptedRestore) return;
    _attemptedRestore = true;

    final settings = ref.read(settingsControllerProvider);
    if (settings.lastSessionId.isEmpty || settings.lastProjectId.isEmpty) {
      return;
    }

    try {
      final client = ref.read(gatewayClientProvider);
      final session = await client.getSession(settings.lastSessionId);
      if (!mounted || session.id.isEmpty) return;

      final sessionView = readSession(session);
      final projectView = GatewayProjectView(
        id: settings.lastProjectId,
        name: '',
        directory: sessionView.directory,
        updatedAtMs: 0,
      );

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GatewayChatPage(
            session: sessionView,
            project: projectView,
          ),
        ),
      );
    } catch (_) {
      // Session no longer exists or network error — fall back to normal flow.
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          ChatTab(),
          GitPage(),
          FilesPage(),
          SettingsPage(firstRun: false),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (i) => setState(() => _currentIndex = i),
          destinations: _destinations,
        ),
      ),
    );
  }
}
