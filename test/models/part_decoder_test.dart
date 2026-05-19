import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/models/part.dart';

void main() {
  group('Part.fromJson', () {
    test('decodes a text part', () {
      final p = Part.fromJson(const {
        'id': 'prt_1',
        'messageID': 'msg_1',
        'sessionID': 'ses_1',
        'type': 'text',
        'text': 'hello',
      });
      expect(p, isA<TextPart>());
      expect((p as TextPart).text, 'hello');
    });

    test('decodes a tool part with state.status', () {
      final p = Part.fromJson(const {
        'id': 'prt_2',
        'messageID': 'msg_1',
        'sessionID': 'ses_1',
        'type': 'tool',
        'tool': 'bash',
        'state': {
          'status': 'running',
          'input': {'cmd': 'ls'},
        },
      });
      expect(p, isA<ToolPart>());
      final tool = p as ToolPart;
      expect(tool.tool, 'bash');
      expect(tool.status, ToolStatus.running);
      expect(tool.input?['cmd'], 'ls');
    });

    test('falls back to UnknownPart for unrecognised types', () {
      final p = Part.fromJson(const {
        'id': 'prt_3',
        'messageID': 'msg_1',
        'sessionID': 'ses_1',
        'type': 'newfangled-type',
      });
      expect(p, isA<UnknownPart>());
      expect((p as UnknownPart).rawType, 'newfangled-type');
    });
  });
}
