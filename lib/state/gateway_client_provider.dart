library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/gateway_client.dart';
import 'settings_store.dart';

final gatewayClientProvider = Provider<GatewayClient>((ref) {
  final settings = ref.watch(settingsControllerProvider);
  final client = GatewayClient(
    baseUrl: Uri.parse(settings.baseUrl),
    bearerToken: settings.bearerToken,
  );
  ref.onDispose(client.close);
  return client;
});
