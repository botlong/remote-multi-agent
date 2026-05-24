import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/state/agent_config_filter.dart';

void main() {
  test('filters credential entries by the agent that can use them', () {
    final entries = <Map<String, dynamic>>[
      {
        'id': 'profile-openai',
        'source': 'profile',
        'keys': {
          'openai': {'key': '***'},
        },
      },
      {
        'id': 'profile-anthropic',
        'source': 'profile',
        'keys': {
          'anthropic': {'key': '***'},
        },
      },
      {
        'id': 'cc-opencode',
        'source': 'cc-switch',
        'provider': 'opencode',
        'raw': {'appType': 'opencode'},
      },
    ];

    expect(
      credentialEntriesForAgent('codex', entries).map((e) => e['id']),
      ['profile-openai'],
    );
    expect(
      credentialEntriesForAgent('claude-code', entries).map((e) => e['id']),
      ['profile-anthropic'],
    );
    expect(
      credentialEntriesForAgent('opencode', entries).map((e) => e['id']),
      ['profile-openai', 'profile-anthropic', 'cc-opencode'],
    );
  });
}
