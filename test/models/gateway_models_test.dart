import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/models/agent.dart';
import 'package:remote_multi_agent/models/gateway_event.dart';
import 'package:remote_multi_agent/models/gateway_session.dart';
import 'package:remote_multi_agent/models/project.dart';

void main() {
  group('Project.fromJson', () {
    test('uses defaults for missing fields', () {
      final project = Project.fromJson(const <String, dynamic>{});

      expect(project.id, '');
      expect(project.name, '');
      expect(project.directory, '');
      expect(project.updatedAtMs, 0);
    });
  });

  group('Agent.fromJson', () {
    test('decodes capabilities and commands', () {
      final agent = Agent.fromJson(const <String, dynamic>{
        'id': 'codex',
        'displayName': 'Codex',
        'supportsModels': true,
        'supportsSlashCommands': true,
        'commands': [
          {'name': '/fast', 'description': 'Switch model behavior'},
        ],
      });

      expect(agent.id, 'codex');
      expect(agent.supportsModels, isTrue);
      expect(agent.supportsSlashCommands, isTrue);
      expect(agent.supportsAttachments, isFalse);
      expect(agent.supportsPermissions, isFalse);
      expect(agent.sessionKind, 'thread');
      expect(agent.commands.single.name, '/fast');
    });

    test('exposes nested raw availability metadata', () {
      final agent = Agent.fromJson(const <String, dynamic>{
        'id': 'codex',
        'displayName': 'Codex',
        'raw': {
          'available': true,
          'command': {'command': 'codex'},
        },
      });

      expect(agent.raw['available'], isTrue);
      expect((agent.raw['command'] as Map)['command'], 'codex');
    });
  });

  group('GatewaySession.fromJson', () {
    test('decodes known status values', () {
      final session = GatewaySession.fromJson(const <String, dynamic>{
        'id': 's1',
        'projectId': 'p1',
        'agentId': 'codex',
        'status': 'waiting-for-approval',
        'createdAt': '1779177600000',
      });

      expect(session.id, 's1');
      expect(session.projectId, 'p1');
      expect(session.directory, '');
      expect(session.status, GatewaySessionStatus.waitingForApproval);
      expect(session.createdAtMs, 1779177600000);
      expect(session.updatedAtMs, 0);
    });
  });

  group('GatewayEvent', () {
    test('decodes JSON SSE envelope and preserves raw', () {
      final event = GatewayEvent.fromSseData(
        sseEvent: 'gateway',
        data: '''
{"type":"message.delta","sessionId":"s1","agentId":"codex","timestamp":1779177600000,"data":{"text":"hi"},"raw":{"provider":"cli"}}''',
      );

      expect(event.type, 'message.delta');
      expect(event.sseEvent, 'gateway');
      expect(event.sessionId, 's1');
      expect(event.agentId, 'codex');
      expect(event.timestampMs, 1779177600000);
      expect(event.data['text'], 'hi');
      expect(event.raw['provider'], 'cli');
    });

    test('falls back to raw map for malformed SSE data', () {
      final event = GatewayEvent.fromSseData(
        sseEvent: 'message',
        data: 'not json',
      );

      expect(event.type, 'message');
      expect(event.data['_raw'], 'not json');
      expect(event.raw['_raw'], 'not json');
    });
  });
}
