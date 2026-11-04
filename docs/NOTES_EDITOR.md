# Note editor

## Inline Markdown editing

Edit mode uses a single body field. `MarkdownEditingController`
(`app/lib/features/notes/presentation/markdown_editing_controller.dart`)
overrides `buildTextSpan` to style the raw Markdown in place:

- headings `#` to `######`
- bold `**` and `__`
- italic `*` and `_`
- bold-italic `***` and `___`
- inline code and fenced code blocks
- strikethrough `~~`
- links `[text](url)`
- blockquotes, bullets, numbered lists, and task checkboxes

Syntax markers stay visible but are dimmed. The concatenated span text always
equals `TextEditingController.text`, so cursor, selection, and IME offsets stay
correct. Parsed spans are cached per text and composing ranges are underlined.

Storage remains plain Markdown. Read mode continues to use the rendered
`MarkdownPreview`. No rich-text dependency is used.

## Event notes

Event details stays open while the event editor or note editor is pushed on top.
Returning reloads the event and the linked note list. `NoteRepository`
exposes both:

- `notesForEvent(eventId)` for one-shot reads
- `watchNotesForEvent(eventId)` for reactive lists

The Add note button creates a linked note and opens it without closing event
details. Tapping a linked note does the same. A saved note appears immediately
through the reactive stream.

## Back navigation

The note editor flushes pending autosave before leaving. Back navigation sets
an allow-pop flag, rebuilds `PopScope`, then pops once after the frame so the
same `PopScope` cannot block the programmatic pop.
