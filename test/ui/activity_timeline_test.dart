import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_multi_agent/state/gateway_chat_store.dart';
import 'package:remote_multi_agent/ui/widgets/activity_timeline.dart';

void main() {
  testWidgets('renders command activity with collapsed output', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ActivityTimeline(
            activities: [
              ActivityItem(
                id: 'a1',
                kind: ActivityKind.command,
                status: ActivityStatus.completed,
                title: 'Ran npm test',
                command: 'npm test',
                output: 'line 1\nline 2\nline 3\nline 4\n',
                sequence: 1,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.textContaining('Ran npm test'), findsOneWidget);
    expect(find.textContaining('line 1'), findsOneWidget);
    expect(find.textContaining('line 4'), findsNothing);
    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();
    expect(find.textContaining('line 4'), findsOneWidget);
  });
}
