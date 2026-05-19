library;

import 'agent_chat_adapter.dart';

class CodexChatAdapter extends AgentChatAdapter {
  CodexChatAdapter({
    required super.client,
    required super.metadata,
    required super.chatStore,
  });

  static const _fallbackCommands = <String>[
    '/help',
    '/clear',
    '/compact',
    '/model',
    '/approvals',
    '/status',
  ];

  @override
  List<AgentCommandSuggestion> get commandSuggestions {
    final suggestions = buildSuggestions(_fallbackCommands);
    final fastSupported =
        metadata.commands.any((command) => command.name == '/fast') ||
            metadata.raw['supportsFast'] == true ||
            metadata.raw['fast'] == true;
    if (fastSupported &&
        !suggestions.any((suggestion) => suggestion.command == '/fast')) {
      return <AgentCommandSuggestion>[
        ...suggestions,
        const AgentCommandSuggestion(command: '/fast'),
      ];
    }
    return suggestions;
  }

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
