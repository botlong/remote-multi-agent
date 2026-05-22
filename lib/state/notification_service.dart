/// Notification service — system-level local notifications.
///
/// Shows OS notifications (status bar / notification shade) when the agent
/// finishes or errors. No signing, no FCM, no APNs required.
library;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Global key so we can show SnackBars from anywhere without a BuildContext.
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

// ─── Local notifications plugin ─────────────────────────────────────────────

final _plugin = FlutterLocalNotificationsPlugin();
int _notificationId = 0;
bool _initialized = false;

/// Call once at app startup (before runApp or in main).
Future<void> initNotifications() async {
  if (_initialized) return;

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  const settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
    macOS: iosSettings,
  );

  await _plugin.initialize(settings);
  _initialized = true;
}

/// Shows a system notification (notification shade / status bar).
/// If [sessionId] matches the currently-active session, the notification
/// is suppressed (user is already looking at it).
void showAppNotification({
  required String title,
  String? body,
  String? sessionId,
  Duration duration = const Duration(seconds: 4),
}) {
  // Suppress if user is viewing this session
  if (sessionId != null && sessionId == _activeSessionId) return;

  // System notification
  if (_initialized) {
    _plugin.show(
      _notificationId++,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'agent_events',
          'Agent Events',
          channelDescription: 'Notifications when agents finish or error',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}

String? _activeSessionId;

/// Update the active session ID for notification suppression.
void setActiveSessionId(String? id) => _activeSessionId = id;

/// Provider that tracks which session ID the user is currently viewing.
/// Used to suppress notifications for the active session.
final activeSessionIdProvider = StateProvider<String?>((ref) => null);
