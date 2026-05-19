/// Riverpod providers that wire HTTP/SSE clients to settings.
///
/// The clients are deliberately *not* autoDispose: dropping the SSE socket
/// every time the user pops a screen would be bad UX (we'd miss events while
/// reconnecting). Instead we rebuild only when a relevant setting changes,
/// which Riverpod handles by virtue of `ref.watch(settingsControllerProvider)`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/opencode_client.dart';
import '../api/sse_stream.dart';
import 'chat_store.dart';
import 'settings_store.dart';

final opencodeClientProvider = Provider<OpencodeClient>((ref) {
  final s = ref.watch(settingsControllerProvider);
  final client = OpencodeClient(
    baseUrl: Uri.parse(s.baseUrl),
    bearerToken: s.bearerToken,
  );
  ref.onDispose(client.close);
  return client;
});

final sseClientProvider = Provider<SseClient>((ref) {
  final s = ref.watch(settingsControllerProvider);
  final url = Uri.parse('${s.baseUrl.replaceAll(RegExp(r'/$'), '')}/event');
  final client = SseClient(
    SseConfig(
      url: url,
      bearerToken: s.bearerToken,
    ),
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Per-session chat controller. Keyed by session id. autoDispose so leaving a
/// chat tears down its reducer (events still buffered in SseClient replay).
final chatControllerProvider = StateNotifierProvider.autoDispose
    .family<ChatController, ChatState, String>((ref, sessionId) {
  final sse = ref.watch(sseClientProvider);
  final client = ref.watch(opencodeClientProvider);
  return ChatController(sessionId: sessionId, sse: sse, client: client);
});
