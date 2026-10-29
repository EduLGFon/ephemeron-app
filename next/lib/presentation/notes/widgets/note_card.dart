import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/theme_palettes.dart';
import '../../../data/local/database.dart';

class DraggableNoteCard extends StatelessWidget {
  const DraggableNoteCard({
    super.key,
    required this.note,
    required this.palette,
    required this.onTap,
    required this.onLongPress,
  });

  final Note note;
  final AppPalette palette;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final card = _NoteCardContent(note: note, palette: palette);

    return Draggable<Note>(
      data: note,
      // Shown while dragging (ghost copy, slightly transparent)
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(
          opacity: 0.85,
          child: SizedBox(
            width: 160,
            height: 170,
            child: card,
          ),
        ),
      ),
      // The original card dims when dragged
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: card,
      ),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: card,
      ),
    );
  }
}

class _NoteCardContent extends StatelessWidget {
  const _NoteCardContent({required this.note, required this.palette});

  final Note note;
  final AppPalette palette;

  String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  String _preparePreviewContent(String content) {
    // flutter_markdown requires checkboxes to be prefixed with a list bullet (e.g. "- [ ]")
    // This regex converts standalone "[ ]" or "[x]" at the start of lines to "- [ ]" or "- [x]"
    String processed = content.replaceAllMapped(
      RegExp(r'^(\s*)\[([ x])\]', multiLine: true),
      (match) => '${match.group(1)}- [${match.group(2)}]',
    );

    // flutter_markdown doesn't support our custom ![alt|height](url) syntax.
    // Strip the |height part for the list preview.
    processed = processed.replaceAllMapped(RegExp(r'!\[([^\|\]]*?)\|(\d+)\]\('),
        (match) => '![${match.group(1)}](');

    return processed;
  }

  @override
  Widget build(BuildContext context) {
    final hasEventLink = note.eventId != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.text.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: hasEventLink
              ? palette.primary.withValues(alpha: 0.3)
              : palette.text.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRect(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: MarkdownBody(
                  data: _preparePreviewContent(note.content),
                  softLineBreak: true,
                  onTapLink: (text, href, title) {
                    if (href != null) {
                      launchUrl(Uri.parse(href));
                    }
                  },
                  styleSheet:
                      MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                    p: TextStyle(
                        color: palette.text.withValues(alpha: 0.8),
                        fontSize: 11,
                        height: 1.4),
                    h1: TextStyle(
                        color: palette.text,
                        fontSize: 14,
                        fontWeight: FontWeight.bold),
                    h2: TextStyle(
                        color: palette.text,
                        fontSize: 12,
                        fontWeight: FontWeight.bold),
                    h3: TextStyle(
                        color: palette.text,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                    code: TextStyle(color: palette.primary, fontSize: 10),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            note.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: palette.text, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatDate(note.createdAt),
                  style: TextStyle(
                      color: palette.text.withValues(alpha: 0.4), fontSize: 11),
                ),
              ),
              if (hasEventLink)
                Tooltip(
                  message: 'Linked to calendar event',
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_outlined,
                            size: 10, color: palette.primary),
                        const SizedBox(width: 3),
                        Text('Event',
                            style: TextStyle(
                                color: palette.primary,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
