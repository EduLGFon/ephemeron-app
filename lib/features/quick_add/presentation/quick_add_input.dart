import '../../../core/theme/theme_palettes.dart';
import 'package:flutter/material.dart';
import '../../../presentation/notes/smart_list_formatter.dart'; // Make sure this exists, or use whatever formatter is there

class QuickAddInput extends StatelessWidget {
  final TextEditingController titleController;
  final FocusNode titleFocusNode;
  final TextEditingController descController;
  final FocusNode descFocusNode;
  final String titleHint;
  final AppPalette palette;

  const QuickAddInput({
    super.key,
    required this.titleController,
    required this.titleFocusNode,
    required this.descController,
    required this.descFocusNode,
    required this.titleHint,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: titleController,
          focusNode: titleFocusNode,
          autofocus: false,
          style: TextStyle(
              color: palette.text, fontSize: 18, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: titleHint,
            hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
            border: InputBorder.none,
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 8),
          ),
        ),
        TextField(
          controller: descController,
          focusNode: descFocusNode,
          style: TextStyle(color: palette.text, fontSize: 14),
          maxLines: null,
          expands: false,
          inputFormatters: [SmartListFormatter()],
          contentInsertionConfiguration: ContentInsertionConfiguration(
            allowedMimeTypes: const [
              'image/png',
              'image/jpeg',
              'image/gif',
              'image/webp'
            ],
            onContentInserted: (content) {
              // Usually handled in the state, but left empty here if not provided as callback
            },
          ),
          decoration: InputDecoration(
            hintText: 'Add description...',
            hintStyle: TextStyle(color: palette.text.withValues(alpha: 0.5)),
            border: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
