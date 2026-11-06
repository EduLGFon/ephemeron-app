// Thin hand-written Google REST client (Calendar + Tasks). No heavy
// googleapis dependency. Throws typed failures; never touches app data.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

part 'google_api_client/core.dart';
part 'google_api_client/calendar.dart';
part 'google_api_client/tasks.dart';

class GoogleApiException implements Exception {
  GoogleApiException(this.status, this.message, {this.retryAfterSec});

  final int status;
  final String message;
  final int? retryAfterSec;

  bool get isGone => status == 410;
  bool get isUnauthorized => status == 401;
  bool get isConflict => status == 412;

  /// 429, or 403 carrying a rate-limit/quota reason. All other 403s are
  /// permission denials (missing scopes, revoked access) and must never
  /// be treated as rate limits or stale rows.
  bool get isRateLimited {
    if (status == 429) return true;
    if (status != 403) return false;
    final m = message.toLowerCase();
    return m.contains('ratelimit') ||
        m.contains('quotaexceeded') ||
        m.contains('quota_exceeded');
  }

  /// Expired/revoked token (401) or a non-rate-limit 403. The queued row is
  /// valid; the credential is not. Keep the row and ask to reconnect.
  bool get isPermissionDenied {
    if (status == 401) return true;
    if (status != 403) return false;
    return !isRateLimited;
  }
}

class CalendarPage {
  CalendarPage({required this.items, this.nextSyncToken});
  final List<Map<String, dynamic>> items;
  final String? nextSyncToken;
}

class TasksPage {
  TasksPage({required this.items, this.nextUpdatedMin});
  final List<Map<String, dynamic>> items;
  final String? nextUpdatedMin;
}

abstract class GoogleApiClient {
  Future<List<Map<String, dynamic>>> calendarList();
  Future<CalendarPage> eventsList(
    String calendarId, {
    String? syncToken,
    String? timeMin,
    String? timeMax,
  });
  Future<Map<String, dynamic>> eventInsert(
    String calendarId,
    Map<String, dynamic> body,
  );
  Future<Map<String, dynamic>> eventPatch(
    String calendarId,
    String eventId,
    Map<String, dynamic> body, {
    String? etag,
  });
  Future<Map<String, dynamic>> eventMove(
    String sourceCalendarId,
    String eventId,
    String destinationCalendarId,
  );
  Future<void> eventDelete(String calendarId, String eventId);
  Future<List<Map<String, dynamic>>> taskLists();
  Future<Map<String, dynamic>> taskListCreate(String title);
  Future<Map<String, dynamic>> taskListPatch(String listId, String title);
  Future<void> taskListDelete(String listId);
  Future<TasksPage> tasksList(String taskListId, {String? updatedMin});
  Future<Map<String, dynamic>> taskInsert(
    String taskListId,
    Map<String, dynamic> body,
  );
  Future<Map<String, dynamic>> taskPatch(
    String taskListId,
    String taskId,
    Map<String, dynamic> body, {
    String? etag,
  });
  Future<Map<String, dynamic>> taskMove(
    String sourceTaskListId,
    String taskId,
    String destinationTaskListId,
  );
  Future<void> taskDelete(String taskListId, String taskId);
}

class HttpGoogleApiClient extends _GoogleApiBase
    with _GoogleApiCalendarOps, _GoogleApiTasksOps
    implements GoogleApiClient {
  HttpGoogleApiClient({required super.accessToken, super.httpClient});
}
