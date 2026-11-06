part of '../note_editor_screen.dart';

// Word/char count plus the autosave status label under the body.

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.controller, required this.status});

  final TextEditingController controller;
  final _SaveStatus status;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final counts = countWords(value.text);
        final label = switch (status) {
          _SaveStatus.idle => 'Autosave on',
          _SaveStatus.saving => 'Saving...',
          _SaveStatus.saved => 'Saved',
          _SaveStatus.failed => 'Save failed',
        };
        return Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${counts.words} words, ${counts.chars} chars - $label',
            key: const Key('note-save-status'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: status == _SaveStatus.failed
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
        );
      },
    );
  }
}
