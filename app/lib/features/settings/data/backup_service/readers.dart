part of '../backup_service.dart';

// Typed readers: JSON numbers may decode as int or double; bools may be
// stored as 0/1 by hand-written backups.
String _reqStr(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is! String) throw BackupFormatException('Field $key must be text.');
  return v;
}

String? _optStr(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is! String) throw BackupFormatException('Field $key must be text.');
  return v;
}

int _reqInt(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is int) return v;
  throw BackupFormatException('Field $key must be an integer.');
}

int? _optInt(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is int) return v;
  throw BackupFormatException('Field $key must be an integer.');
}

double? _optDouble(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is num) return v.toDouble();
  throw BackupFormatException('Field $key must be a number.');
}

bool _reqBool(Map<String, dynamic> m, String key, {bool fallback = false}) {
  final v = m[key];
  if (v == null) return fallback;
  if (v is bool) return v;
  if (v is int) return v != 0;
  throw BackupFormatException('Field $key must be true/false.');
}
