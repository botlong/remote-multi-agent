library;

import 'package:flutter/foundation.dart';

import '../../models/message.dart';
import '../../models/part.dart';

@immutable
class GatewayProjectView {
  const GatewayProjectView({
    required this.id,
    required this.name,
    required this.directory,
    required this.updatedAtMs,
  });

  final String id;
  final String name;
  final String directory;
  final int updatedAtMs;
}

@immutable
class GatewayAgentView {
  const GatewayAgentView({
    required this.id,
    required this.displayName,
    required this.supportsModels,
    required this.supportsSlashCommands,
    required this.commands,
    required this.models,
  });

  final String id;
  final String displayName;
  final bool supportsModels;
  final bool supportsSlashCommands;
  final List<GatewayCommandView> commands;
  final List<GatewayModelView> models;
}

@immutable
class GatewayModelView {
  const GatewayModelView({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;
}

@immutable
class GatewayCommandView {
  const GatewayCommandView({
    required this.name,
    required this.description,
  });

  final String name;
  final String description;
}

@immutable
class GatewaySessionView {
  const GatewaySessionView({
    required this.id,
    required this.projectId,
    required this.directory,
    required this.agentId,
    required this.modelId,
    required this.title,
    required this.status,
    required this.createdAtMs,
    required this.updatedAtMs,
  });

  final String id;
  final String projectId;
  final String directory;
  final String agentId;
  final String? modelId;
  final String title;
  final String status;
  final int createdAtMs;
  final int updatedAtMs;
}

@immutable
class GatewayMessageView {
  const GatewayMessageView({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAtMs,
    required this.streaming,
  });

  final String id;
  final String role;
  final String text;
  final int createdAtMs;
  final bool streaming;
}

List<GatewayProjectView> readProjects(dynamic state) {
  final items = _readList(state, ['projects', 'items', 'value']);
  return items.map(readProject).where((p) => p.id.isNotEmpty).toList()
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
}

GatewayProjectView readProject(dynamic value) {
  final map = _asMap(value);
  final directory = _string(map, value, ['directory', 'path']);
  return GatewayProjectView(
    id: _string(map, value, ['id', 'projectId']),
    name: _string(map, value, ['name', 'title'])
        .ifEmpty(_shortDirName(directory)),
    directory: directory,
    updatedAtMs: _int(map, value, ['updatedAt', 'updatedAtMs']),
  );
}

List<GatewayAgentView> readAgents(dynamic state) {
  final items = _readList(state, ['agents', 'items', 'value']);
  return items.map(readAgent).where((a) => a.id.isNotEmpty).toList();
}

GatewayAgentView readAgent(dynamic value) {
  final map = _asMap(value);
  final commands = _readList(value, ['commands'])
      .map(readCommand)
      .where((c) => c.name.isNotEmpty)
      .toList();
  final models = _readList(value, ['models'])
      .map(readModel)
      .where((m) => m.id.isNotEmpty)
      .toList();
  final rawModels = _readList(_asMap(map['raw']), ['models'])
      .map(readModel)
      .where((m) => m.id.isNotEmpty)
      .toList();
  final id = _string(map, value, ['id', 'agentId']);
  return GatewayAgentView(
    id: id,
    displayName:
        _string(map, value, ['displayName', 'name']).ifEmpty(_agentLabel(id)),
    supportsModels: _bool(
      map,
      value,
      ['supportsModels'],
      fallback: models.isNotEmpty || rawModels.isNotEmpty,
    ),
    supportsSlashCommands: _bool(
      map,
      value,
      ['supportsSlashCommands'],
      fallback: commands.isNotEmpty,
    ),
    commands: commands,
    models: models.isNotEmpty ? models : rawModels,
  );
}

GatewayModelView readModel(dynamic value) {
  final map = _asMap(value);
  final id = _string(map, value, ['id', 'modelId']);
  return GatewayModelView(
    id: id,
    displayName: _string(map, value, ['displayName', 'name']).ifEmpty(id),
  );
}

GatewayCommandView readCommand(dynamic value) {
  final map = _asMap(value);
  var name = _string(map, value, ['name', 'id', 'command']);
  if (name.isNotEmpty && !name.startsWith('/')) name = '/$name';
  return GatewayCommandView(
    name: name,
    description: _string(map, value, ['description', 'summary']),
  );
}

List<GatewaySessionView> readSessions(dynamic state) {
  final items = _readList(state, ['sessions', 'items', 'value']);
  return items.map(readSession).where((s) => s.id.isNotEmpty).toList()
    ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
}

GatewaySessionView readSession(dynamic value) {
  try {
    final nested = _property(value, 'session');
    if (nested != null) return readSession(nested);
  } catch (_) {/* ignore */}

  final map = _asMap(value);
  if (map.isEmpty) {
    try {
      final nested = _property(value, 'session');
      if (nested != null) return readSession(nested);
    } catch (_) {/* ignore */}
  }
  final model = _asMap(map['model']);
  final objectStatus = _property(value, 'status');
  final status = _string(map, null, ['status'])
      .ifEmpty(_property(objectStatus, 'wireName')?.toString() ?? '')
      .ifEmpty(_statusName(objectStatus));
  return GatewaySessionView(
    id: _string(map, value, ['id', 'sessionId']),
    projectId: _string(map, value, ['projectId']),
    directory: _string(map, value, ['directory', 'path']),
    agentId: _string(map, value, ['agentId', 'agent']).ifEmpty('opencode'),
    modelId:
        _string(map, value, ['modelId']).ifEmpty(_string(model, null, ['id'])),
    title: _string(map, value, ['title']).ifEmpty('(untitled)'),
    status: status.ifEmpty('idle'),
    createdAtMs: _int(map, value, ['createdAt', 'createdAtMs']),
    updatedAtMs: _int(map, value, ['updatedAt', 'updatedAtMs']),
  );
}

List<GatewayMessageView> readMessages(dynamic state) {
  var items =
      _readList(state, ['orderedMessages', 'messages', 'items', 'value']);
  if (items.isEmpty) {
    final map = _asMap(_property(state, 'messages'));
    if (map.isNotEmpty) items = map.values.toList();
  }
  return items.map(readMessage).where((m) => m.text.isNotEmpty).toList();
}

GatewayMessageView readMessage(dynamic value) {
  if (value is Message) {
    final text = value.orderedParts
        .whereType<TextPart>()
        .map((part) => part.text)
        .where((text) => text.isNotEmpty)
        .join('\n');
    return GatewayMessageView(
      id: value.id,
      role: switch (value.role) {
        MessageRole.user => 'user',
        MessageRole.assistant => 'assistant',
        MessageRole.system => 'system',
        MessageRole.unknown => 'assistant',
      },
      text: text,
      createdAtMs: value.createdAtMs ?? 0,
      streaming: value.status == MessageStatus.running,
    );
  }

  final map = _asMap(value);
  final partsText = _readPartsText(value);
  return GatewayMessageView(
    id: _string(map, value, ['id', 'messageId']),
    role: _string(map, value, ['role', 'author']).ifEmpty('assistant'),
    text:
        _string(map, value, ['text', 'content', 'message']).ifEmpty(partsText),
    createdAtMs: _int(map, value, ['createdAt', 'createdAtMs', 'timestamp']),
    streaming: _bool(map, value, ['streaming', 'isStreaming']),
  );
}

bool readLoading(dynamic state) =>
    _bool(_asMap(state), state, ['loading', 'isLoading']);

String? readError(dynamic state) {
  final map = _asMap(state);
  final error = _string(map, state, ['error']);
  return error.isEmpty ? null : error;
}

bool readStreaming(dynamic state) =>
    _bool(_asMap(state), state, ['isStreaming', 'streaming']);

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}

List<dynamic> _readList(dynamic value, List<String> keys) {
  if (value is List) return value;
  if (value is Iterable) return value.toList();
  final map = _asMap(value);
  for (final key in keys) {
    final v = map[key];
    if (v is List) return v;
    if (v is Iterable) return v.toList();
    if (v is Map) return v.values.toList();
  }
  if (value is Map) return value.values.toList();
  for (final key in keys) {
    try {
      final v = _property(value, key);
      if (v is List) return v;
      if (v is Iterable) return v.toList();
      if (v is Map) return v.values.toList();
    } catch (_) {/* ignore */}
  }
  return const [];
}

String _string(Map<String, dynamic> map, dynamic object, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value != null) return '$value';
  }
  for (final key in keys) {
    try {
      final value = _property(object, key);
      if (value != null) return '$value';
    } catch (_) {/* ignore */}
  }
  return '';
}

int _int(Map<String, dynamic> map, dynamic object, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    final parsed = _parseInt(value);
    if (parsed != null) return parsed;
  }
  final time = _asMap(map['time']);
  for (final key in const ['updated', 'created']) {
    final parsed = _parseInt(time[key]);
    if (parsed != null) return parsed;
  }
  for (final key in keys) {
    try {
      final parsed = _parseInt(_property(object, key));
      if (parsed != null) return parsed;
    } catch (_) {/* ignore */}
  }
  return 0;
}

int? _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is String) return int.tryParse(value);
  return null;
}

bool _bool(
  Map<String, dynamic> map,
  dynamic object,
  List<String> keys, {
  bool fallback = false,
}) {
  for (final key in keys) {
    final value = map[key];
    if (value is bool) return value;
  }
  for (final key in keys) {
    try {
      final value = _property(object, key);
      if (value is bool) return value;
    } catch (_) {/* ignore */}
  }
  return fallback;
}

dynamic _property(dynamic object, String name) {
  if (object == null) return null;
  switch (name) {
    case 'id':
      return (object as dynamic).id;
    case 'projectId':
      return (object as dynamic).projectId;
    case 'sessionId':
      return (object as dynamic).sessionId;
    case 'agentId':
      return (object as dynamic).agentId;
    case 'modelId':
      return (object as dynamic).modelId;
    case 'name':
      return (object as dynamic).name;
    case 'displayName':
      return (object as dynamic).displayName;
    case 'title':
      return (object as dynamic).title;
    case 'directory':
      return (object as dynamic).directory;
    case 'path':
      return (object as dynamic).path;
    case 'updatedAt':
      return (object as dynamic).updatedAt;
    case 'updatedAtMs':
      return (object as dynamic).updatedAtMs;
    case 'createdAt':
      return (object as dynamic).createdAt;
    case 'createdAtMs':
      return (object as dynamic).createdAtMs;
    case 'status':
      return (object as dynamic).status;
    case 'agent':
      return (object as dynamic).agent;
    case 'model':
      return (object as dynamic).model;
    case 'wireName':
      return (object as dynamic).wireName;
    case 'commands':
      return (object as dynamic).commands;
    case 'models':
      return (object as dynamic).models;
    case 'supportsModels':
      return (object as dynamic).supportsModels;
    case 'supportsSlashCommands':
      return (object as dynamic).supportsSlashCommands;
    case 'description':
      return (object as dynamic).description;
    case 'summary':
      return (object as dynamic).summary;
    case 'command':
      return (object as dynamic).command;
    case 'messages':
      return (object as dynamic).messages;
    case 'orderedMessages':
      return (object as dynamic).orderedMessages;
    case 'items':
      return (object as dynamic).items;
    case 'projects':
      return (object as dynamic).projects;
    case 'agents':
      return (object as dynamic).agents;
    case 'sessions':
      return (object as dynamic).sessions;
    case 'session':
      return (object as dynamic).session;
    case 'loading':
      return (object as dynamic).loading;
    case 'isLoading':
      return (object as dynamic).isLoading;
    case 'error':
      return (object as dynamic).error;
    case 'role':
      return (object as dynamic).role;
    case 'author':
      return (object as dynamic).author;
    case 'text':
      return (object as dynamic).text;
    case 'content':
      return (object as dynamic).content;
    case 'message':
      return (object as dynamic).message;
    case 'timestamp':
      return (object as dynamic).timestamp;
    case 'streaming':
      return (object as dynamic).streaming;
    case 'isStreaming':
      return (object as dynamic).isStreaming;
  }
  return null;
}

String _readPartsText(dynamic value) {
  final parts = _readList(value, ['orderedParts', 'parts']);
  final buffer = StringBuffer();
  for (final part in parts) {
    final map = _asMap(part);
    final text = _string(map, part, ['text']);
    if (text.isEmpty) continue;
    if (buffer.isNotEmpty) buffer.writeln();
    buffer.write(text);
  }
  return buffer.toString();
}

String _agentLabel(String id) {
  switch (id) {
    case 'codex':
      return 'Codex';
    case 'claude-code':
      return 'Claude Code';
    case 'opencode':
      return 'OpenCode';
    default:
      return id;
  }
}

String _statusName(Object? value) {
  if (value == null) return '';
  final raw = value.toString();
  final dot = raw.lastIndexOf('.');
  return dot == -1 ? raw : raw.substring(dot + 1);
}

String _shortDirName(String path) {
  final parts = path.split(RegExp(r'[/\\]')).where((p) => p.isNotEmpty);
  return parts.isEmpty ? path : parts.last;
}

extension GatewayStringX on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
