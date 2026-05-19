/// Lightweight in-app notification service.
///
/// Listens for `session.completed` / `session.error` events from all active
/// chat stores and shows a notification when the app is backgrounded or the
/// user is viewing a different session.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global key so we can show SnackBars from anywhere without a BuildContext.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Shows a brief in-app notification.
void showAppNotification({
  required String title,
  String? body,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = rootScaffoldMessengerKey.currentState;
  if (messenger == null) return;
  messenger.showSnackBar(
    SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          if (body != null && body.isNotEmpty)
            Text(body, maxLines: 2, overflow: TextOverflow.ellipsis),
        ],
      ),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(label: 'OK', onPressed: () {}),
    ),
  );
}

/// Provider that tracks which session ID the user is currently viewing.
/// Used to suppress notifications for the active session.
final activeSessionIdProvider = StateProvider<String?>((ref) => null);
