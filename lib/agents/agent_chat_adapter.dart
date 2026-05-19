library;

import '../api/gateway_client.dart';
import '../models/agent.dart';
import '../state/gateway_chat_store.dart';

typedef AgentMetadata = Agent;

class AgentCommandSuggestion {
  const AgentCommandSuggestion({
    required this.command,
    this.description,
  });

  final String command;
  final String? description;
}

abstract class AgentChatAdapter {
  AgentChatAdapter({
    required this.client,
    required this.metadata,
    required this.chatStore,
  });

  final GatewayClient client;
  final AgentMetadata metadata;
  final GatewayChatStore chatStore;

  List<AgentCommandSuggestion> get commandSuggestions;
  bool get supportsAttachments;

  Future<void> sendMessage(
    String text, {
    List<Map<String, dynamic>> attachments = const [],
  });
  Future<void> sendSlashCommand(String command);
  Future<void> abort();

  bool get supportsSlashCommands => metadata.supportsSlashCommands;

  List<AgentCommandSuggestion> buildSuggestions(
    Iterable<String> fallbackCommands,
  ) {
    final fromMetadata = metadata.commands
        .map(
          (command) => AgentCommandSuggestion(
            command: command.name,
            description:
                command.description.isEmpty ? null : command.description,
          ),
        )
        .toList(growable: false);
    if (fromMetadata.isNotEmpty) {
      return fromMetadata;
    }
    return fallbackCommands
        .map((command) => AgentCommandSuggestion(command: command))
        .toList(growable: false);
  }
}
