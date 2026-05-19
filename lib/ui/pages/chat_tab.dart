import 'package:flutter/material.dart';

import 'codex_thread_list_page.dart';

/// Chat tab with its own nested [Navigator] so that tapping a thread
/// pushes [CodexChatPage] within this tab without affecting the bottom nav.
class ChatTab extends StatefulWidget {
  const ChatTab({super.key});

  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = _navigatorKey.currentState;
        if (navigator != null && navigator.canPop()) {
          navigator.pop();
        }
      },
      child: Navigator(
        key: _navigatorKey,
        onGenerateRoute: (settings) {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const CodexThreadListPage(),
          );
        },
      ),
    );
  }
}
