part of '../note_editor_screen.dart';

// Horizontal Markdown formatting toolbar shown above the body in Edit mode.

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.onAction});

  final void Function(String before, [String after]) onAction;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.format_bold),
            tooltip: 'Bold',
            onPressed: () => onAction('**', '**'),
          ),
          IconButton(
            icon: const Icon(Icons.format_italic),
            tooltip: 'Italic',
            onPressed: () => onAction('*', '*'),
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'Code',
            onPressed: () => onAction('`', '`'),
          ),
          IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Link',
            onPressed: () => onAction('[', '](url)'),
          ),
          IconButton(
            icon: const Icon(Icons.format_list_bulleted),
            tooltip: 'List',
            onPressed: () => onAction('- '),
          ),
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: 'Task',
            onPressed: () => onAction('- [ ] '),
          ),
          IconButton(
            icon: const Icon(Icons.title),
            tooltip: 'Heading',
            onPressed: () => onAction('## '),
          ),
          IconButton(
            icon: const Icon(Icons.format_quote),
            tooltip: 'Quote',
            onPressed: () => onAction('> '),
          ),
        ],
      ),
    );
  }
}
