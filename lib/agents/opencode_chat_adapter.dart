library;

import 'agent_chat_adapter.dart';

class OpenCodeChatAdapter extends AgentChatAdapter {
  OpenCodeChatAdapter({
    required super.client,
    required super.metadata,
    required super.chatStore,
  });

  static const _fallbackCommands = <String>[
    '/help',
    '/clear',
    '/compact',
    '/undo',
    '/redo',
    '/share',
    '/unshare',
  ];

  @override
  List<AgentCommandSuggestion> get commandSuggestions =>
      buildSuggestions(_fallbackCommands);

  @override
  bool get supportsAttachments => metadata.supportsAttachments;

  @override
  Future<void> sendMessage(
    String text, {
    List<Map<String, dynamic>> attachments = const [],
  }) {
    return chatStore.sendMessage(text, attachments: attachments);
  }

  @override
  Future<void> sendSlashCommand(String command) {
    return chatStore.sendSlashCommand(command);
  }

  @override
  Future<void> abort() => chatStore.abort();
}
