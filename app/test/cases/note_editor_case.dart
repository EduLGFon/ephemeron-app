import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/note_repository.dart';
import 'package:ephemeron/features/notes/presentation/markdown_preview.dart';
import 'package:ephemeron/features/notes/presentation/note_editor_screen.dart';
import 'package:ephemeron/features/settings/application/settings_providers.dart';
import 'package:ephemeron/features/settings/data/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens in Read mode and shows a live preview while editing', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = NoteRepository(db, attachmentDir: null);
    final id = await repo.createNote(
      title: 'Read me',
      body: '# Heading\n\nHello **world**',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          settingsRepositoryProvider.overrideWith(
            (ref) async => SettingsRepository(prefs),
          ),
        ],
        child: MaterialApp(home: NoteEditorScreen(noteId: id)),
      ),
    );
    await tester.pumpAndSettle();

    // Read mode renders the body and shows the title as a heading.
    expect(find.text('Read me'), findsOneWidget);
    expect(find.byType(MarkdownPreview), findsOneWidget);
    expect(find.text('Heading'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byKey(const Key('note-body')), findsNothing);

    await tester.tap(find.byTooltip('Edit'));
    await tester.pump();

    expect(find.byTooltip('Read'), findsOneWidget);
    expect(find.byKey(const Key('note-title')), findsOneWidget);
    final body = find.byKey(const Key('note-body'));
    expect(body, findsOneWidget);

    await tester.enterText(body, '# Live\n\nTyped **now**');
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('note-live-preview')),
        matching: find.text('Live'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Read'));
    await tester.pump();
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byType(MarkdownPreview), findsOneWidget);
    expect(find.byKey(const Key('note-body')), findsNothing);

    // Autosave flushes the latest text; leaving the screen also flushes.
    await tester.pump(const Duration(seconds: 1));
    final saved = await repo.getNote(id);
    expect(saved!.body, contains('Typed **now**'));

    await tester.pumpWidget(Container());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });
}
