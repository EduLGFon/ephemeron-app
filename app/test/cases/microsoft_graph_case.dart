import 'dart:convert';

import 'package:ephemeron/features/sync/data/microsoft_graph_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('getMe maps identity', () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'id': 'u1',
          'displayName': 'Alice',
          'mail': 'alice@example.com',
          'userPrincipalName': 'alice@contoso.com',
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => 'tok',
      httpClient: client,
    );
    final me = await api.getMe();
    expect(me.id, 'u1');
    expect(me.displayName, 'Alice');
    expect(me.mail, 'alice@example.com');
    expect(me.userPrincipalName, 'alice@contoso.com');
  });

  test('token provider null throws 401', () async {
    final client = MockClient((req) async => http.Response('', 200));
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => null,
      httpClient: client,
    );
    expect(
      () => api.listCalendars(),
      throwsA(
        isA<MicrosoftGraphException>().having((e) => e.status, 'status', 401),
      ),
    );
  });

  test('listCalendars maps fields', () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'value': [
            {
              'id': 'c1',
              'name': 'Calendar',
              'color': 'auto',
              'hexColor': '#ff0000',
              'isDefaultCalendar': true,
              'canEdit': true,
              'owner': {'name': 'Alice', 'address': 'alice@example.com'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => 'tok',
      httpClient: client,
    );
    final cals = await api.listCalendars();
    expect(cals.length, 1);
    expect(cals.first.id, 'c1');
    expect(cals.first.name, 'Calendar');
    expect(cals.first.hexColor, '#ff0000');
    expect(cals.first.isDefaultCalendar, true);
    expect(cals.first.canEdit, true);
    expect(cals.first.owner?.address, 'alice@example.com');
  });

  test('calendarView is scoped to the requested calendar', () async {
    Uri? seen;
    final client = MockClient((req) async {
      seen = req.url;
      return http.Response(
        jsonEncode({'value': <Object>[]}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => 'tok',
      httpClient: client,
    );
    await api.calendarView(
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 1, 2),
      calendarId: 'c1',
    );
    expect(seen!.path, contains('/me/calendars/c1/calendarView'));
  });

  test('calendarView pagination and mapping all-day/timed', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'value': [
              {
                'id': 'e1',
                'subject': 'All day',
                'isAllDay': true,
                'start': {'dateTime': '2026-01-01T00:00:00', 'timeZone': 'UTC'},
                'end': {'dateTime': '2026-01-02T00:00:00', 'timeZone': 'UTC'},
                'location': {'displayName': 'Home'},
                'attendees': [
                  {
                    'emailAddress': {
                      'name': 'Bob',
                      'address': 'bob@example.com',
                    },
                    'type': 'required',
                    'status': {'response': 'accepted'},
                  },
                ],
                'organizer': {
                  'emailAddress': {
                    'name': 'Alice',
                    'address': 'alice@example.com',
                  },
                },
                'recurrence': {
                  'pattern': {'type': 'daily', 'interval': 1},
                  'range': {
                    'type': 'endDate',
                    'startDate': '2026-01-01',
                    'endDate': '2026-01-05',
                  },
                },
                'lastModifiedDateTime': '2026-01-01T00:00:00Z',
              },
            ],
            '@odata.nextLink': 'https://example.com/next',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'value': [
            {
              'id': 'e2',
              'subject': 'Timed',
              'isAllDay': false,
              'start': {'dateTime': '2026-01-01T10:00:00', 'timeZone': 'UTC'},
              'end': {'dateTime': '2026-01-01T11:00:00', 'timeZone': 'UTC'},
              'showAs': 'busy',
              'isCancelled': false,
              'type': 'singleInstance',
              'onlineMeetingUrl': 'https://meet',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => 'tok',
      httpClient: client,
    );
    final events = await api.calendarView(
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 1, 2),
    );
    expect(events.length, 2);
    final allDay = events.first;
    expect(allDay.isAllDay, true);
    expect(allDay.start?.utc, DateTime.utc(2026, 1, 1));
    expect(allDay.location?.displayName, 'Home');
    expect(allDay.attendees.first.emailAddress?.address, 'bob@example.com');
    expect(allDay.attendees.first.response, 'accepted');
    expect(allDay.recurrence?.pattern?.type, 'daily');
    expect(allDay.recurrence?.range?.endDate, '2026-01-05');
    final timed = events[1];
    expect(timed.isAllDay, false);
    expect(timed.start?.utc, DateTime.utc(2026, 1, 1, 10));
    expect(timed.end?.utc, DateTime.utc(2026, 1, 1, 11));
    expect(timed.onlineMeetingUrl, 'https://meet');
  });

  test('missing optional fields handled', () async {
    final client = MockClient((req) async {
      return http.Response(
        jsonEncode({
          'value': [
            {'id': 'e3'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => 'tok',
      httpClient: client,
    );
    final events = await api.calendarView(
      DateTime.utc(2026, 1, 1),
      DateTime.utc(2026, 1, 2),
    );
    expect(events.length, 1);
    expect(events.first.id, 'e3');
    expect(events.first.subject, isNull);
    expect(events.first.start, isNull);
  });

  test('listTodoLists and tasks mapping', () async {
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/lists')) {
        return http.Response(
          jsonEncode({
            'value': [
              {
                'id': 'l1',
                'displayName': 'Tasks',
                'wellknownListName': 'defaultList',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'value': [
            {
              'id': 't1',
              'title': 'Buy milk',
              'body': {'content': '2%'},
              'importance': 'high',
              'status': 'notStarted',
              'dueDateTime': {
                'dateTime': '2026-01-02T00:00:00',
                'timeZone': 'UTC',
              },
              'completedDateTime': {
                'dateTime': '2026-01-03T00:00:00',
                'timeZone': 'UTC',
              },
              'createdDateTime': '2026-01-01T00:00:00Z',
              'lastModifiedDateTime': '2026-01-01T00:00:00Z',
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => 'tok',
      httpClient: client,
    );
    final lists = await api.listTodoLists();
    expect(lists.first.displayName, 'Tasks');
    final tasks = await api.listTodoTasks('l1');
    expect(tasks.length, 1);
    expect(tasks.first.title, 'Buy milk');
    expect(tasks.first.body, '2%');
    expect(tasks.first.dueDateTime?.utc, DateTime.utc(2026, 1, 2));
    expect(tasks.first.completedDateTime?.utc, DateTime.utc(2026, 1, 3));
    expect(tasks.first.createdDateTime, DateTime.utc(2026, 1, 1));
  });

  test('401 typed', () async {
    final client = MockClient(
      (req) async => http.Response('{"error":{"message":"unauth"}}', 401),
    );
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => 'tok',
      httpClient: client,
    );
    expect(
      () => api.getMe(),
      throwsA(
        isA<MicrosoftGraphException>().having((e) => e.status, 'status', 401),
      ),
    );
  });

  test('403 typed', () async {
    final client = MockClient((req) async => http.Response('{}', 403));
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => 'tok',
      httpClient: client,
    );
    expect(
      () => api.listCalendars(),
      throwsA(
        isA<MicrosoftGraphException>().having((e) => e.status, 'status', 403),
      ),
    );
  });

  test('429 with Retry-After', () async {
    final client = MockClient(
      (req) async => http.Response('{}', 429, headers: {'retry-after': '7'}),
    );
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => 'tok',
      httpClient: client,
    );
    try {
      await api.listTodoLists();
      fail('expected');
    } catch (e) {
      final ex = e as MicrosoftGraphException;
      expect(ex.status, 429);
      expect(ex.retryAfterSec, 7);
    }
  });

  test('malformed json throws', () async {
    final client = MockClient((req) async => http.Response('not json', 200));
    final api = HttpMicrosoftGraphClient(
      accessToken: () async => 'tok',
      httpClient: client,
    );
    expect(
      () => api.getMe(),
      throwsA(
        isA<MicrosoftGraphException>().having(
          (e) => e.isMalformed,
          'malformed',
          true,
        ),
      ),
    );
  });

  test('404 and 410 typed', () async {
    for (final code in [404, 410]) {
      final client = MockClient((req) async => http.Response('{}', code));
      final api = HttpMicrosoftGraphClient(
        accessToken: () async => 'tok',
        httpClient: client,
      );
      try {
        await api.listTodoTasks('l1');
        fail('expected');
      } catch (e) {
        expect((e as MicrosoftGraphException).status, code);
      }
    }
  });
}
