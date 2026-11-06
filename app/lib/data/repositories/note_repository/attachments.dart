part of '../note_repository.dart';

mixin _NoteAttachmentOps on _NoteRepositoryBase {
  Future<String> createNote({
    required String title,
    String? body,
    String? folderId,
    String? linkedEventId,
  });

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
            createdAt: nowMs(),
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
