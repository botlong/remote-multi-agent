/// Gateway agent metadata models.
library;

class Agent {
  const Agent({
    required this.id,
    required this.displayName,
    required this.supportsModels,
    required this.supportsSlashCommands,
    required this.supportsAttachments,
    required this.supportsPermissions,
    required this.sessionKind,
    required this.commands,
    required this.raw,
  });

  final String id;
  final String displayName;
  final bool supportsModels;
  final bool supportsSlashCommands;
  final bool supportsAttachments;
  final bool supportsPermissions;
  final String sessionKind;
  final List<AgentCommand> commands;
  final Map<String, dynamic> raw;

  factory Agent.fromJson(Map<String, dynamic> json) {
    final commands = json['commands'] as List<dynamic>? ?? const <dynamic>[];
    final raw = json['raw'] is Map
        ? (json['raw'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return Agent(
      id: json['id'] as String? ?? '',
      displayName:
          json['displayName'] as String? ?? json['name'] as String? ?? '',
      supportsModels: json['supportsModels'] as bool? ?? false,
      supportsSlashCommands: json['supportsSlashCommands'] as bool? ?? false,
      supportsAttachments: json['supportsAttachments'] as bool? ?? false,
      supportsPermissions: json['supportsPermissions'] as bool? ?? false,
      sessionKind: json['sessionKind'] as String? ?? 'thread',
      commands: commands
          .whereType<Map<String, dynamic>>()
          .map(AgentCommand.fromJson)
          .toList(growable: false),
      raw: <String, dynamic>{
        ...json,
        ...raw,
      },
    );
  }
}

class AgentModel {
  const AgentModel({
    required this.id,
    required this.displayName,
    required this.raw,
  });

  final String id;
  final String displayName;
  final Map<String, dynamic> raw;

  factory AgentModel.fromJson(Map<String, dynamic> json) {
    return AgentModel(
      id: json['id'] as String? ?? json['modelId'] as String? ?? '',
      displayName:
          json['displayName'] as String? ?? json['name'] as String? ?? '',
      raw: Map<String, dynamic>.from(json),
    );
  }
}

class AgentCommand {
  const AgentCommand({
    required this.name,
    required this.description,
    required this.raw,
  });

  final String name;
  final String description;
  final Map<String, dynamic> raw;

  factory AgentCommand.fromJson(Map<String, dynamic> json) {
    return AgentCommand(
      name: json['name'] as String? ?? json['id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      raw: Map<String, dynamic>.from(json),
    );
  }
}
