import 'package:ephemeron/features/notes/presentation/markdown_editing_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  testWidgets('styles headings and bold content while dimming markers', (
    tester,
  ) async {
    final controller = MarkdownEditingController(
      text: '# Heading\n\nHello **world**',
    );
    addTearDown(controller.dispose);
    late TextSpan span;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            span = controller.buildTextSpan(
              context: context,
              style: const TextStyle(color: Colors.black, fontSize: 14),
              withComposing: false,
            );
            return const SizedBox();
          },
        ),
      ),
    );

    final spans = _flatten(span);
    // The span tree must preserve every character exactly.
    expect(spans.map((s) => s.text).join(), controller.text);

    final heading = spans.firstWhere(
      (s) =>
          s.text!.contains('Heading') && s.style?.fontWeight == FontWeight.bold,
    );
    expect(heading.style?.fontWeight, FontWeight.bold);

    final bold = spans.firstWhere((s) => s.text == 'world');
    expect(bold.style?.fontWeight, FontWeight.bold);

    final markers = spans.where((s) => s.text == '**').toList();
    expect(markers, isNotEmpty);
    for (final marker in markers) {
      expect(marker.style?.color?.a ?? 1, lessThan(1));
    }
  });

  testWidgets('keeps span text equal to the controller value while typing', (
    tester,
  ) async {
    final controller = MarkdownEditingController();
    addTearDown(controller.dispose);
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );

    for (final value in [
      '',
      'plain typing',
      '## Heading\n\n- [ ] task',
      'a **bold** and `code` and [link](https://example.com)',
    ]) {
      controller.text = value;
      final built = controller.buildTextSpan(
        context: ctx,
        style: const TextStyle(color: Colors.black),
        withComposing: false,
      );
      expect(_flatten(built).map((s) => s.text).join(), value);
    }
  });
}
