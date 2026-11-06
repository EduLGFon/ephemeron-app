// Notes: nested folders, Markdown bodies, event links, overflow notes,
// FTS5 search, attachments. Offline-first; sync via backend changesets.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/core/search/sanitize.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:ephemeron/data/repositories/pending_operations_repository.dart';
import 'package:ephemeron/core/time/time.dart';
import 'package:image/image.dart' as img;

part 'note_repository/folders.dart';
part 'note_repository/notes.dart';
part 'note_repository/search.dart';
part 'note_repository/links.dart';
part 'note_repository/attachments.dart';

class NoteSearchHit {
  const NoteSearchHit({required this.note, required this.snippet});
  final Note note;
  final String snippet;
}

class _NoteRepositoryBase {
  _NoteRepositoryBase(this._db, {Directory? attachmentDir})
    : _attachmentDir = attachmentDir;

  final AppDatabase _db;
  final Directory? _attachmentDir;
}

class NoteRepository extends _NoteRepositoryBase
    with
        _NoteFolderOps,
        _NoteCrudOps,
        _NoteSearchOps,
        _NoteLinkOps,
        _NoteAttachmentOps {
  NoteRepository(super._db, {super.attachmentDir});

  static final _linkPattern = RegExp(r'\[\[([^\[\]]+)\]\]');

  static List<String> extractLinkedTitles(String? body) {
    if (body == null || body.isEmpty) return [];
    final out = <String>[];
    for (final m in _linkPattern.allMatches(body)) {
      final title = m.group(1)!.trim();
      if (title.isNotEmpty && !out.contains(title)) out.add(title);
    }
    return out;
  }
}
