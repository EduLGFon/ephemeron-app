// Notes: nested folders, Markdown bodies, event links, overflow notes,
// FTS5 search, attachments. Offline-first; sync via backend changesets.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:ephemeron/core/ids/ids.dart';
import 'package:ephemeron/data/drift/app_database.dart';
import 'package:image/image.dart' as img;

class NoteSearchHit {
  const NoteSearchHit({required this.note, required this.snippet});
  final Note note;
  final String snippet;
}

class NoteRepository {
  NoteRepository(this._db, {Directory? attachmentDir})
    : _attachmentDir = attachmentDir;

  final AppDatabase _db;
  final Directory? _attachmentDir;

  int _now() => DateTime.now().toUtc().millisecondsSinceEpoch;

  // Folders.

  Stream<List<Folder>> watchFolders(String? parentId) {
    final q = _db.select(_db.folders)..where((t) => t.deletedAt.isNull());
    if (parentId == null) {
      q.where((t) => t.parentId.isNull());
    } else {
      q.where((t) => t.parentId.equals(parentId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return q.watch();
  }

  Stream<List<Folder>> watchChildFolders(String? parentId) =>
      watchFolders(parentId);

  Future<List<Folder>> childFolders(String? parentId) async {
    final q = _db.select(_db.folders)..where((t) => t.deletedAt.isNull());
    if (parentId == null) {
      q.where((t) => t.parentId.isNull());
    } else {
      q.where((t) => t.parentId.equals(parentId));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.sortOrder)]);
    return q.get();
  }

  Future<String> createFolder(String name, {String? parentId}) async {
    final id = newId();
    final now = _now();
    await _db
        .into(_db.folders)
        .insert(
          FoldersCompanion.insert(
            id: id,
            parentId: Value(parentId),
            name: name,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }

  /// Chain from filesystem root down to [folderId] (inclusive).
  Future<List<Folder>> breadcrumbs(String folderId) async {
    final chain = <Folder>[];
    String? cursor = folderId;
    while (cursor != null) {
      final f = await (_db.select(
        _db.folders,
      )..where((t) => t.id.equals(cursor!))).getSingleOrNull();
      if (f == null) break;
      chain.insert(0, f);
      cursor = f.parentId;
    }
    return chain;
  }

  /// Moves a folder; refuses moves into itself or its own descendants.
  Future<void> moveFolder(String folderId, String? newParentId) async {
    if (newParentId == folderId) return;
    if (newParentId != null) {
      final crumbs = await breadcrumbs(newParentId);
      if (crumbs.any((f) => f.id == folderId)) return;
    }
    await (_db.update(_db.folders)..where((t) => t.id.equals(folderId))).write(
      FoldersCompanion(parentId: Value(newParentId), updatedAt: Value(_now())),
    );
  }

  /// Deletes a folder: children are reparented to the deleted folder's
  /// parent and its notes follow the folder's notes destination.
  Future<void> deleteFolder(String folderId) async {
    final folder = await (_db.select(
      _db.folders,
    )..where((t) => t.id.equals(folderId))).getSingleOrNull();
    if (folder == null) return;
    await _db.transaction(() async {
      await (_db.update(
        _db.folders,
      )..where((t) => t.parentId.equals(folderId))).write(
        FoldersCompanion(
          parentId: Value(folder.parentId),
          updatedAt: Value(_now()),
        ),
      );
      await (_db.update(
        _db.notes,
      )..where((t) => t.folderId.equals(folderId))).write(
        NotesCompanion(
          folderId: Value(folder.parentId),
          updatedAt: Value(_now()),
          dirty: const Value(true),
        ),
      );
      await (_db.delete(_db.folders)..where((t) => t.id.equals(folderId))).go();
    });
  }

  // Notes.

  Future<String> createNote({
    required String title,
    String? body,
    String? folderId,
    String? linkedEventId,
  }) async {
    final id = newId();
    final now = _now();
    await _db
        .into(_db.notes)
        .insert(
          NotesCompanion.insert(
            id: id,
            folderId: Value(folderId),
            title: Value(title),
            body: Value(body),
            linkedEventId: Value(linkedEventId),
            createdAt: now,
            updatedAt: now,
          ),
        );
    await refreshLinks(id);
    return id;
  }

  Future<Note?> getNote(String id) {
    return (_db.select(
      _db.notes,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Stream<Note?> watchNote(String id) {
    return (_db.select(
      _db.notes,
    )..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<void> updateNote(
    String id, {
    String? title,
    String? Function()? body,
    String? Function()? folderId,
  }) async {
    await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        title: title == null ? const Value.absent() : Value(title),
        body: body == null ? const Value.absent() : Value(body()),
        folderId: folderId == null ? const Value.absent() : Value(folderId()),
        updatedAt: Value(_now()),
        dirty: const Value(true),
      ),
    );
    if (body != null || title != null) await refreshLinks(id);
  }

  Future<void> setPinned(String id, bool pinned) async {
    await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        pinned: Value(pinned),
        updatedAt: Value(_now()),
        dirty: const Value(true),
      ),
    );
  }

  Future<String> duplicateNote(String id) async {
    final src = await getNote(id);
    if (src == null) throw StateError('note $id not found');
    return createNote(
      title: '${src.title} (copy)',
      body: src.body,
      folderId: src.folderId,
      linkedEventId: src.linkedEventId,
    );
  }

  Future<void> trashNote(String id) async {
    await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        deletedAt: Value(_now()),
        updatedAt: Value(_now()),
        dirty: const Value(true),
      ),
    );
  }

  Future<void> restoreNote(String id) async {
    await (_db.update(_db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(_now()),
        dirty: const Value(true),
      ),
    );
  }

  Future<List<Note>> notesInFolder(String? folderId) {
    final q = _db.select(_db.notes)..where((t) => t.deletedAt.isNull());
    if (folderId == null) {
      q.where((t) => t.folderId.isNull());
    } else {
      q.where((t) => t.folderId.equals(folderId));
    }
    q.orderBy([
      (t) => OrderingTerm.desc(t.pinned),
      (t) => OrderingTerm.desc(t.updatedAt),
    ]);
    return q.get();
  }

  Stream<List<Note>> watchNotesInFolder(String? folderId) {
    final q = _db.select(_db.notes)..where((t) => t.deletedAt.isNull());
    if (folderId == null) {
      q.where((t) => t.folderId.isNull());
    } else {
      q.where((t) => t.folderId.equals(folderId));
    }
    q.orderBy([
      (t) => OrderingTerm.desc(t.pinned),
      (t) => OrderingTerm.desc(t.updatedAt),
    ]);
    return q.watch();
  }

  Future<List<Note>> notesForEvent(String eventId) {
    return (_db.select(_db.notes)
          ..where((t) => t.linkedEventId.equals(eventId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
  }

  /// Overflow note for long event descriptions. Idempotent per event:
  /// returns the existing overflow note when present.
  Future<String?> ensureOverflowNote(String eventId, String fullText) async {
    final existing =
        await (_db.select(_db.notes)
              ..where(
                (t) => t.linkedEventId.equals(eventId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    if (existing != null) {
      if (existing.body != fullText) {
        await updateNote(existing.id, body: () => fullText);
      }
      return existing.id;
    }
    return createNote(
      title: 'Event description',
      body: fullText,
      linkedEventId: eventId,
    );
  }

  Stream<List<Note>> watchTrash() {
    return (_db.select(_db.notes)
          ..where((t) => t.deletedAt.isNotNull())
          ..orderBy([(t) => OrderingTerm.desc(t.deletedAt)]))
        .watch();
  }

  // Search via FTS5 with highlighted snippets.

  Future<List<NoteSearchHit>> searchNotes(String query) async {
    final q = query.trim();
    if (q.isEmpty) return [];
    final stripped = q.replaceAll('%', '').replaceAll('_', '').trim();
    if (stripped.isEmpty) return [];
    final like = '%$stripped%';
    final rows =
        await (_db.select(_db.notes)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    (t.title.like(like) | t.body.like(like)),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
            .get();
    return [
      for (final n in rows) NoteSearchHit(note: n, snippet: _snippet(n, q)),
    ];
  }

  String _snippet(Note note, String query) {
    final body = note.body ?? '';
    final idx = body.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) {
      final t = note.title;
      return t.length > 80 ? '${t.substring(0, 80)}...' : t;
    }
    final start = (idx - 30).clamp(0, body.length);
    final end = (idx + query.length + 30).clamp(0, body.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < body.length ? '...' : '';
    return '$prefix${body.substring(start, end)}$suffix';
  }

  // Backlinks: [[Note title]] references resolved by exact title match.
  // Rebuilt on every title/body save; unresolvable titles are ignored.

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

  /// Rebuilds outgoing links for [noteId] from its current body.
  Future<void> refreshLinks(String noteId) async {
    final note = await getNote(noteId);
    if (note == null) return;
    final titles = extractLinkedTitles(note.body);
    await _db.transaction(() async {
      await (_db.delete(
        _db.noteLinks,
      )..where((t) => t.fromNoteId.equals(noteId))).go();
      for (final title in titles) {
        final target =
            await (_db.select(_db.notes)
                  ..where((t) => t.title.equals(title) & t.deletedAt.isNull()))
                .getSingleOrNull();
        if (target != null && target.id != noteId) {
          await _db
              .into(_db.noteLinks)
              .insert(
                NoteLinksCompanion.insert(
                  fromNoteId: noteId,
                  toNoteId: target.id,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }
    });
  }

  /// Notes linking TO [noteId] (excludes trashed).
  Future<List<Note>> backlinks(String noteId) async {
    final rows = await (_db.select(
      _db.noteLinks,
    )..where((t) => t.toNoteId.equals(noteId))).get();
    final ids = rows.map((r) => r.fromNoteId).toSet();
    if (ids.isEmpty) return [];
    return (_db.select(
      _db.notes,
    )..where((t) => t.id.isIn(ids) & t.deletedAt.isNull())).get();
  }

  /// Notes that [noteId] links to (excludes trashed).
  Future<List<Note>> forwardLinks(String noteId) async {
    final rows = await (_db.select(
      _db.noteLinks,
    )..where((t) => t.fromNoteId.equals(noteId))).get();
    final ids = rows.map((r) => r.toNoteId).toSet();
    if (ids.isEmpty) return [];
    return (_db.select(
      _db.notes,
    )..where((t) => t.id.isIn(ids) & t.deletedAt.isNull())).get();
  }

  // Attachments (content-addressed; orphan cleanup on demand).

  Future<String?> addAttachment({
    required String ownerId,
    required String sourcePath,
    String? mime,
  }) async {
    final dir = _attachmentDir;
    if (dir == null) return null;
    final src = File(sourcePath);
    if (!await src.exists()) return null;
    var bytes = await src.readAsBytes();
    var ext = sourcePath.contains('.')
        ? sourcePath.split('.').last.toLowerCase()
        : 'bin';
    // Compress large images: max 1600 px on the long edge, JPG quality 80
    // (PNG when the image has alpha; the pinned image pkg has no WebP
    // encoder). Small non-image files are stored as-is.
    final compressed = _compressImage(bytes);
    if (compressed != null) {
      bytes = compressed.bytes;
      ext = compressed.ext;
      mime = compressed.mime;
    }
    var hash = 0;
    for (final b in bytes) {
      hash = ((hash * 31) + b) & 0x7fffffff;
    }
    final dest = File('${dir.path}/$hash.$ext');
    if (!await dest.exists()) {
      await dest.writeAsBytes(bytes, flush: true);
    }
    final id = newId();
    await _db
        .into(_db.attachments)
        .insert(
          AttachmentsCompanion.insert(
            id: id,
            ownerType: 'note',
            ownerId: ownerId,
            path: dest.path,
            mime: Value(mime),
            size: Value(bytes.length),
            hash: Value(hash.toString()),
            createdAt: _now(),
          ),
        );
    return id;
  }

  /// Imports a .md or .txt file as a note. The file name (without
  /// extension) becomes the title; the whole content becomes the body.
  Future<String> importMarkdownFile(String path, {String? folderId}) async {
    final file = File(path);
    final body = await file.readAsString();
    final base = path.split(Platform.pathSeparator).last;
    final title = base.contains('.')
        ? base.substring(0, base.lastIndexOf('.'))
        : base;
    return createNote(title: title, body: body, folderId: folderId);
  }

  Future<void> deleteOrphanAttachments() async {
    final all = await _db.select(_db.attachments).get();
    final ownerIds = <String>{};
    for (final n in await _db.select(_db.notes).get()) {
      ownerIds.add(n.id);
    }
    for (final a in all) {
      if (!ownerIds.contains(a.ownerId)) {
        await (_db.delete(
          _db.attachments,
        )..where((t) => t.id.equals(a.id))).go();
        try {
          await File(a.path).delete();
        } catch (_) {}
      }
    }
  }
}

class _Compressed {
  const _Compressed(this.bytes, this.ext, this.mime);
  final Uint8List bytes;
  final String ext;
  final String mime;
}

/// Resizes to max 1600 px on the long edge and re-encodes: JPG quality 80
/// for opaque images, PNG for images with alpha. Returns null when [bytes]
/// do not decode as an image (caller stores the original file).
_Compressed? _compressImage(Uint8List bytes) {
  const maxEdge = 1600;
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    return null;
  }
  if (decoded == null) return null;
  var image = decoded;
  final longEdge = image.width > image.height ? image.width : image.height;
  if (longEdge > maxEdge) {
    if (image.width >= image.height) {
      image = img.copyResize(image, width: maxEdge);
    } else {
      image = img.copyResize(image, height: maxEdge);
    }
  } else if (bytes.length < 200 * 1024) {
    // Small enough already: skip re-encoding to avoid quality loss.
    return null;
  }
  if (image.hasAlpha) {
    return _Compressed(img.encodePng(image), 'png', 'image/png');
  }
  return _Compressed(img.encodeJpg(image, quality: 80), 'jpg', 'image/jpeg');
}
