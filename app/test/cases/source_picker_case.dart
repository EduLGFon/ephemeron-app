// Two-step source picker: account first, then calendar/list, returning the
// selected source id.
import 'package:ephemeron/core/ui/source_picker_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('picks an account then a source', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                picked = await showSourcePickerSheet(
                  context,
                  title: 'Calendar source',
                  selectedId: 'c1',
                  options: const [
                    SourceOption(
                      id: 'c1',
                      name: 'Work',
                      account: 'me@example.com',
                    ),
                    SourceOption(
                      id: 'c2',
                      name: 'Personal',
                      account: 'other@example.com',
                    ),
                    SourceOption(id: 'local', name: 'Local', isLocal: true),
                  ],
                );
              },
              child: const Text('Pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();

    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.text('other@example.com'), findsOneWidget);
    expect(find.text('On this device'), findsOneWidget);

    await tester.tap(find.text('me@example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Work'));
    await tester.pumpAndSettle();
    expect(picked, 'c1');
  });

  testWidgets('back returns to the account list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSourcePickerSheet(
                context,
                title: 'List source',
                options: const [
                  SourceOption(
                    id: 'l1',
                    name: 'Work list',
                    account: 'me@example.com',
                  ),
                ],
                allowNone: true,
              ),
              child: const Text('Pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    expect(find.text('No list'), findsOneWidget);
    await tester.tap(find.text('me@example.com'));
    await tester.pumpAndSettle();
    expect(find.text('Work list'), findsOneWidget);
    await tester.tap(find.byTooltip('Back to accounts'));
    await tester.pumpAndSettle();
    expect(find.text('me@example.com'), findsOneWidget);
  });
}
