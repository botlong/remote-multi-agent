import 'package:flutter/material.dart';

import 'chat_tab.dart';
import 'files_page.dart';
import 'git_page.dart';
import 'settings_page.dart';

/// Root shell after first-run configuration. Houses a Material 3
/// [NavigationBar] with 4 tabs and preserves state across switches
/// via [IndexedStack].
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

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
