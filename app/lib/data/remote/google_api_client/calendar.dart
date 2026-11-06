part of '../google_api_client.dart';

mixin _GoogleApiCalendarOps on _GoogleApiBase {
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
      all.addAll(((body['items'] as List?) ?? []).cast<Map<String, dynamic>>());
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
  Future<Map<String, dynamic>> eventMove(
    String sourceCalendarId,
    String eventId,
    String destinationCalendarId,
  ) async {
    final r = await _http.post(
      Uri.parse(
        '${AppConfig.calendarApiBase}/calendars/${Uri.encodeComponent(sourceCalendarId)}/events/${Uri.encodeComponent(eventId)}/move',
      ).replace(queryParameters: {'destination': destinationCalendarId}),
      headers: await _headers(),
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
}
