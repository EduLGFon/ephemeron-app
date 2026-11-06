// A [TextEditingController] that renders raw Markdown inline while typing.
// Markers stay visible but are dimmed; storage stays plain Markdown.
// The concatenated span text always equals [text] so cursor/IME offsets
// remain valid.
import 'package:flutter/material.dart';

part 'markdown_editing_controller/segment.dart';
part 'markdown_editing_controller/parsing.dart';
part 'markdown_editing_controller/rendering.dart';

class MarkdownEditingController extends TextEditingController {
  MarkdownEditingController({super.text});

  final Map<String, List<_Segment>> _cache = <String, List<_Segment>>{};
  static const int _maxCacheEntries = 32;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) => _buildTextSpan(
    context: context,
    style: style,
    withComposing: withComposing,
  );
}
