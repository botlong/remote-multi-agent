/// Riverpod providers for the Codex backend, parallel to providers.dart for
/// OpenCode. Kept in a separate file so the OpenCode pipeline still works on
/// the main branch and we can switch with a single import.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/codex_client.dart';
import 'codex_chat_store.dart';
import 'codex_thread_store.dart';
import 'settings_store.dart';

/// QQBot URL = same host as the configured OpenCode baseUrl + port 8787.
/// We reuse `settings.baseUrl` because the user already configured it.
String _qqBotBase(AppSettings s) {
  final u = Uri.parse(s.baseUrl);
  return 'http://${u.host}:8787';
}

final codexClientProvider = Provider<CodexClient>((ref) {
  final s = ref.watch(settingsControllerProvider);
  final url = _qqBotBase(s);
  // Token here is the QQBot bearer (different from OpenCode's bearer).
  // We piggyback on `s.bearerToken` for now; if you want a separate field,
  // add it to AppSettings.
  final client = CodexClient(
    baseUrl: Uri.parse(url),
    bearerToken: s.bearerToken,
  );
  ref.onDispose(client.close);
  return client;
});

/// Per-thread chat controller, keyed by the *local* key (UUID we assign
/// before the server has produced a thread_id).
final codexChatProvider = StateNotifierProvider.autoDispose
    .family<CodexChatController, CodexChatState, String>((ref, localKey) {
  final client = ref.watch(codexClientProvider);
  final list = ref.read(codexThreadListProvider).items;
  final matches = list.where((e) => e.localKey == localKey);
  final t = matches.isEmpty ? null : matches.first;
  return CodexChatController(
    client: client,
    localKey: localKey,
    threadId: t?.threadId,
    directory: t?.directory ?? '',
  );
});
