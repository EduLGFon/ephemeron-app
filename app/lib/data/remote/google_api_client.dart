// Thin hand-written Google REST client (Calendar + Tasks). No heavy
// googleapis dependency. Throws typed failures; never touches app data.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';

class GoogleApiException implements Exception {
  GoogleApiException(this.status, this.message, {this.retryAfterSec});

  final int status;
  final String message;
  final int? retryAfterSec;

  bool get isGone => status == 410;
  bool get isUnauthorized => status == 401;
  bool get isRateLimited => status == 403 || status == 429;
  bool get isConflict => status == 412;
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
  Future<void> eventDelete(String calendarId, String eventId);
  Future<List<Map<String, dynamic>>> taskLists();
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
  Future<void> taskDelete(String taskListId, String taskId);
}

class HttpGoogleApiClient implements GoogleApiClient {
  HttpGoogleApiClient({
    required Future<String?> Function() accessToken,
    http.Client? httpClient,
  }) : _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  final Future<String?> Function() _accessToken;
  final http.Client _http;

  Future<Map<String, String>> _headers({String? etag}) async {
    final token = await _accessToken();
    if (token == null) throw GoogleApiException(401, 'no token');
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    if (etag != null) headers['If-Match'] = etag;
    return headers;
  }

  Never _throw(http.Response r) {
    int? retry;
    final ra = r.headers['retry-after'];
    if (ra != null) retry = int.tryParse(ra);
    throw GoogleApiException(r.statusCode, r.body, retryAfterSec: retry);
  }

  @override
  Future<List<Map<String, dynamic>>> calendarList() async {
    final r = await _http.get(
      Uri.parse('${AppConfig.calendarApiBase}/users/me/calendarList'),
      headers: await _headers(),
    );
    if (r.statusCode != 200) _throw(r);
    final items = (jsonDecode(r.body) as Map)['items'] as List? ?? [];
    return items.cast<Map<String, dynamic>>();
  }

  @override
  Future<CalendarPage> eventsList(
    String calendarId, {
    String? syncToken,
    String? timeMin,
    String? timeMax,
  }) async {
    final all = <Map<String, dynamic>>[];
    String? pageToken;
    String? nextSyncToken;
    var pages = 0;
    do {
      final q = <String, String>{
        'singleEvents': 'false',
        'showDeleted': 'true',
        'maxResults': '250',
      };
      if (syncToken != null) q['syncToken'] = syncToken;
      if (timeMin != null) q['timeMin'] = timeMin;
      if (timeMax != null) q['timeMax'] = timeMax;
      if (pageToken != null) q['pageToken'] = pageToken;
      final r = await _http.get(
        Uri.parse(
          '${AppConfig.calendarApiBase}/calendars/${Uri.encodeComponent(calendarId)}/events',
        ).replace(queryParameters: q),
        headers: await _headers(),
      );
      if (r.statusCode != 200) _throw(r);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      all.addAll(
        ((body['items'] as List?) ?? []).cast<Map<String, dynamic>>(),
      );
      pageToken = body['nextPageToken'] as String?;
      if (body['nextSyncToken'] != null) {
        nextSyncToken = body['nextSyncToken'] as String;
      }
      pages++;
    } while (pageToken != null && pages < 50);
    return CalendarPage(items: all, nextSyncToken: nextSyncToken);
  }

  @override
  Future<Map<String, dynamic>> eventInsert(
    String calendarId,
    Map<String, dynamic> body,
  ) async {
    final r = await _http.post(
      Uri.parse(
        '${AppConfig.calendarApiBase}/calendars/${Uri.encodeComponent(calendarId)}/events',
      ).replace(queryParameters: {'conferenceDataVersion': '1'}),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (r.statusCode != 200) _throw(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> eventPatch(
    String calendarId,
    String eventId,
    Map<String, dynamic> body, {
    String? etag,
  }) async {
    final r = await _http.patch(
      Uri.parse(
        '${AppConfig.calendarApiBase}/calendars/${Uri.encodeComponent(calendarId)}/events/${Uri.encodeComponent(eventId)}',
      ).replace(queryParameters: {'conferenceDataVersion': '1'}),
      headers: await _headers(etag: etag),
      body: jsonEncode(body),
    );
    if (r.statusCode != 200) _throw(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Future<void> eventDelete(String calendarId, String eventId) async {
    final r = await _http.delete(
      Uri.parse(
        '${AppConfig.calendarApiBase}/calendars/${Uri.encodeComponent(calendarId)}/events/${Uri.encodeComponent(eventId)}',
      ),
      headers: await _headers(),
    );
    if (r.statusCode != 204 && r.statusCode != 200) _throw(r);
  }

  @override
  Future<List<Map<String, dynamic>>> taskLists() async {
    final r = await _http.get(
      Uri.parse('${AppConfig.tasksApiBase}/users/@me/lists'),
      headers: await _headers(),
    );
    if (r.statusCode != 200) _throw(r);
    return (((jsonDecode(r.body) as Map)['items'] as List?) ?? [])
        .cast<Map<String, dynamic>>();
  }

  @override
  Future<TasksPage> tasksList(String taskListId, {String? updatedMin}) async {
    final all = <Map<String, dynamic>>[];
    String? pageToken;
    var pages = 0;
    do {
      final q = <String, String>{
        'showDeleted': 'true',
        'showCompleted': 'true',
        'showHidden': 'true',
        'maxResults': '100',
      };
      if (updatedMin != null) q['updatedMin'] = updatedMin;
      if (pageToken != null) q['pageToken'] = pageToken;
      final r = await _http.get(
        Uri.parse(
          '${AppConfig.tasksApiBase}/lists/${Uri.encodeComponent(taskListId)}/tasks',
        ).replace(queryParameters: q),
        headers: await _headers(),
      );
      if (r.statusCode != 200) _throw(r);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      all.addAll(
        ((body['items'] as List?) ?? []).cast<Map<String, dynamic>>(),
      );
      pageToken = body['nextPageToken'] as String?;
      pages++;
    } while (pageToken != null && pages < 50);
    return TasksPage(
      items: all,
      nextUpdatedMin: DateTime.now().toUtc().toIso8601String(),
    );
  }

  @override
  Future<Map<String, dynamic>> taskInsert(
    String taskListId,
    Map<String, dynamic> body,
  ) async {
    final r = await _http.post(
      Uri.parse(
        '${AppConfig.tasksApiBase}/lists/${Uri.encodeComponent(taskListId)}/tasks',
      ),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    if (r.statusCode != 200) _throw(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> taskPatch(
    String taskListId,
    String taskId,
    Map<String, dynamic> body, {
    String? etag,
  }) async {
    final r = await _http.patch(
      Uri.parse(
        '${AppConfig.tasksApiBase}/lists/${Uri.encodeComponent(taskListId)}/tasks/${Uri.encodeComponent(taskId)}',
      ),
      headers: await _headers(etag: etag),
      body: jsonEncode(body),
    );
    if (r.statusCode != 200) _throw(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Future<void> taskDelete(String taskListId, String taskId) async {
    final r = await _http.delete(
      Uri.parse(
        '${AppConfig.tasksApiBase}/lists/${Uri.encodeComponent(taskListId)}/tasks/${Uri.encodeComponent(taskId)}',
      ),
      headers: await _headers(),
    );
    if (r.statusCode != 204 && r.statusCode != 200) _throw(r);
  }
}
