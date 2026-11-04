import 'package:drift/native.dart';
import 'package:ephemeron/core/db/db_provider.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/note_repository.dart';
import 'package:ephemeron/features/notes/presentation/markdown_editing_controller.dart';
import 'package:ephemeron/features/notes/presentation/markdown_preview.dart';
import 'package:ephemeron/features/notes/presentation/note_editor_screen.dart';
import 'package:ephemeron/features/settings/application/settings_providers.dart';
import 'package:ephemeron/features/settings/data/settings_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<TextSpan> _flatten(TextSpan span) {
  final out = <TextSpan>[];
  void walk(InlineSpan node) {
    if (node is TextSpan) {
      if (node.text != null) out.add(node);
      for (final child in node.children ?? const <InlineSpan>[]) {
        walk(child);
      }
    }
  }

  walk(span);
  return out;
}

void main() {
  testWidgets('opens in Read mode and edits one inline-styled body field', (
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
    // Edit mode is one field; the old split preview pane is gone.
    expect(find.byKey(const Key('note-live-preview')), findsNothing);
    expect(find.byType(MarkdownPreview), findsNothing);

    await tester.enterText(body, '# Live\n\nTyped **now**');
    await tester.pump();

    final field = tester.widget<TextField>(body);
    expect(field.controller, isA<MarkdownEditingController>());
    final controller = field.controller! as MarkdownEditingController;
    final span = controller.buildTextSpan(
      context: tester.element(body),
      style: DefaultTextStyle.of(tester.element(body)).style,
      withComposing: false,
    );
    expect(_flatten(span).map((s) => s.text).join(), controller.text);
    expect(
      _flatten(
        span,
      ).any((s) => s.text == 'now' && s.style?.fontWeight == FontWeight.bold),
      isTrue,
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

  testWidgets('typing then back saves and closes exactly once', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = NoteRepository(db, attachmentDir: null);
    final id = await repo.createNote(title: 'Back test');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          settingsRepositoryProvider.overrideWith(
            (ref) async => SettingsRepository(prefs),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => NoteEditorScreen(noteId: id),
                    ),
                  ),
                  child: const Text('Open note'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open note'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pump();

    await tester.enterText(
      find.byKey(const Key('note-body')),
      'Saved on the way out',
    );
    await tester.pump();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Open note'), findsOneWidget);
    expect(find.byType(NoteEditorScreen), findsNothing);
    final saved = await repo.getNote(id);
    expect(saved!.body, 'Saved on the way out');

    await tester.pumpWidget(Container());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });
}
