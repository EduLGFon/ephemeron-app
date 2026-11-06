part of '../microsoft_graph_models.dart';

class MsTodoList {
  const MsTodoList({
    required this.id,
    required this.displayName,
    this.wellknownListName,
  });

  final String id;
  final String displayName;
  final String? wellknownListName;

  factory MsTodoList.fromMap(Map<String, dynamic> m) {
    return MsTodoList(
      id: (m['id'] as String?) ?? '',
      displayName: (m['displayName'] as String?) ?? '',
      wellknownListName: m['wellknownListName'] as String?,
    );
  }
}

DateTime? _parseDateTime(dynamic v) {
  if (v == null) return null;
  if (v is String) return DateTime.tryParse(v)?.toUtc();
  if (v is Map<String, dynamic>) {
    return MsDateTimeTimeZone.fromMap(v).utc;
  }
  return null;
}

String? _bodyContent(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  if (v is Map<String, dynamic>) {
    return v['content'] as String?;
  }
  return null;
}

class MsTodoTask {
  const MsTodoTask({
    required this.id,
    required this.title,
    this.body,
    this.importance,
    this.status,
    this.dueDateTime,
    this.completedDateTime,
    this.createdDateTime,
    this.lastModifiedDateTime,
  });

  final String id;
  final String title;
  final String? body;
  final String? importance;
  final String? status;
  final MsDateTimeTimeZone? dueDateTime;
  final MsDateTimeTimeZone? completedDateTime;
  final DateTime? createdDateTime;
  final DateTime? lastModifiedDateTime;

  factory MsTodoTask.fromMap(Map<String, dynamic> m) {
    MsDateTimeTimeZone? due;
    final dueRaw = m['dueDateTime'];
    if (dueRaw is Map<String, dynamic>) {
      due = MsDateTimeTimeZone.fromMap(dueRaw);
    }
    MsDateTimeTimeZone? completed;
    final compRaw = m['completedDateTime'];
    if (compRaw is Map<String, dynamic>) {
      completed = MsDateTimeTimeZone.fromMap(compRaw);
    }
    return MsTodoTask(
      id: (m['id'] as String?) ?? '',
      title: (m['title'] as String?) ?? '',
      body: _bodyContent(m['body']),
      importance: m['importance'] as String?,
      status: m['status'] as String?,
      dueDateTime: due,
      completedDateTime: completed,
      createdDateTime: _parseDateTime(m['createdDateTime']),
      lastModifiedDateTime: _parseDateTime(m['lastModifiedDateTime']),
    );
  }
}
