library;

List<Map<String, dynamic>> credentialEntriesForAgent(
  String agentId,
  List<Map<String, dynamic>> entries,
) {
  return entries
      .where((entry) => credentialEntryMatchesAgent(agentId, entry))
      .toList(growable: false);
}

bool credentialEntryMatchesAgent(
  String agentId,
  Map<String, dynamic> entry,
) {
  final appType = credentialEntryAppType(entry);
  final providers = credentialEntryProviders(entry);
  return switch (agentId) {
    'codex' => appType == 'codex' || providers.contains('openai'),
    'claude-code' => appType == 'claude' ||
        appType == 'claude-desktop' ||
        providers.contains('anthropic'),
    'opencode' => appType == 'opencode' ||
        providers.any(
          _opencodeCompatibleProviders.contains,
        ),
    _ => providers.isNotEmpty,
  };
}

const _opencodeCompatibleProviders = {
  'opencode',
  'openai',
  'anthropic',
  'google',
};

String? credentialEntryAppType(Map<String, dynamic> entry) {
  final raw = entry['raw'];
  if (raw is Map && raw['appType'] != null) {
    final value = raw['appType'].toString();
    return value.isEmpty ? null : value;
  }
  return null;
}

List<String> credentialEntryProviders(Map<String, dynamic> entry) {
  final keys = entry['keys'];
  if (keys is Map && keys.isNotEmpty) {
    return keys.keys
        .map((key) => key.toString())
        .where((key) => key.isNotEmpty)
        .toList(growable: false);
  }
  final provider = entry['provider']?.toString() ?? '';
  return provider.isEmpty ? const <String>[] : <String>[provider];
}
