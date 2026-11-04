// Read-only Microsoft Graph client (calendars + To Do). Throws typed failures;
// never logs tokens, headers, or personal data.
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/config/app_config.dart';
import '../../../domain/microsoft/microsoft_graph_models.dart';

class MicrosoftGraphException implements Exception {
  MicrosoftGraphException(this.status, this.message, {this.retryAfterSec});

  final int status;
  final String message;
  final int? retryAfterSec;

  bool get isUnauthorized => status == 401;
  bool get isForbidden => status == 403;
  bool get isNotFound => status == 404;
  bool get isGone => status == 410;
  bool get isRateLimited => status == 429;
  bool get isMalformed => status == 0;

  @override
  String toString() => 'MicrosoftGraphException($status, $message)';
}

abstract class MicrosoftGraphClient {
  Future<MsIdentity> getMe();
  Future<List<MsCalendar>> listCalendars();
  Future<List<MsEvent>> calendarView(
    DateTime startUtc,
    DateTime endUtc, {
    String? calendarId,
  });
  Future<List<MsTodoList>> listTodoLists();
  Future<List<MsTodoTask>> listTodoTasks(String listId);
}

class HttpMicrosoftGraphClient implements MicrosoftGraphClient {
  HttpMicrosoftGraphClient({
    required Future<String?> Function() accessToken,
    http.Client? httpClient,
  }) : _accessToken = accessToken,
       _http = httpClient ?? http.Client();

  final Future<String?> Function() _accessToken;
  final http.Client _http;

  static const int _maxPages = 50;

  Future<Map<String, String>> _headers({bool preferUtc = false}) async {
    final token = await _accessToken();
    if (token == null) {
      throw MicrosoftGraphException(401, 'no token');
    }
    final headers = <String, String>{
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
    if (preferUtc) {
      headers['Prefer'] = 'outlook.timezone="UTC"';
    }
    return headers;
  }

  Never _throw(http.Response r) {
    int? retry;
    for (final e in r.headers.entries) {
      if (e.key.toLowerCase() == 'retry-after') {
        retry = int.tryParse(e.value);
      }
    }
    throw MicrosoftGraphException(
      r.statusCode,
      _safeMessage(r.body),
      retryAfterSec: retry,
    );
  }

  String _safeMessage(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map<String, dynamic>) {
        final e = j['error'];
        if (e is Map<String, dynamic>) {
          final m = e['message'];
          if (m is String && m.isNotEmpty) return m;
        }
        final m = j['message'];
        if (m is String && m.isNotEmpty) return m;
      }
    } catch (_) {}
    return 'graph ${body.isNotEmpty ? 'error' : 'empty'}';
  }

  Map<String, dynamic> _decode(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      if (j is! Map<String, dynamic>) {
        throw MicrosoftGraphException(0, 'malformed json');
      }
      return j;
    } on FormatException {
      throw MicrosoftGraphException(0, 'malformed json');
    } on MicrosoftGraphException {
      rethrow;
    } catch (_) {
      throw MicrosoftGraphException(0, 'malformed json');
    }
  }

  List<T> _pageItems<T>(
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromMap,
  ) {
    final value = body['value'];
    if (value is! List) return const [];
    return value.whereType<Map<String, dynamic>>().map(fromMap).toList();
  }

  Future<List<T>> _paginate<T>(
    Uri initial,
    Map<String, String> headers,
    T Function(Map<String, dynamic>) fromMap,
  ) async {
    final all = <T>[];
    Uri? next = initial;
    var pages = 0;
    while (next != null && pages < _maxPages) {
      final r = await _http.get(next, headers: headers);
      if (r.statusCode < 200 || r.statusCode >= 300) _throw(r);
      final body = _decode(r);
      all.addAll(_pageItems(body, fromMap));
      final link = body['@odata.nextLink'];
      next = link is String && link.isNotEmpty ? Uri.parse(link) : null;
      pages++;
    }
    return all;
  }

  @override
  Future<MsIdentity> getMe() async {
    final headers = await _headers();
    final r = await _http.get(
      Uri.parse('${AppConfig.microsoftGraphBase}/me').replace(
        queryParameters: const {
          r'$select': 'id,displayName,mail,userPrincipalName',
        },
      ),
      headers: headers,
    );
    if (r.statusCode < 200 || r.statusCode >= 300) _throw(r);
    final body = _decode(r);
    return MsIdentity.fromMap(body);
  }

  @override
  Future<List<MsCalendar>> listCalendars() async {
    final headers = await _headers();
    final initial = Uri.parse('${AppConfig.microsoftGraphBase}/me/calendars')
        .replace(
          queryParameters: const {
            r'$select':
                'id,name,color,hexColor,isDefaultCalendar,canEdit,owner',
          },
        );
    return _paginate(initial, headers, MsCalendar.fromMap);
  }

  @override
  Future<List<MsEvent>> calendarView(
    DateTime startUtc,
    DateTime endUtc, {
    String? calendarId,
  }) async {
    final headers = await _headers(preferUtc: true);
    final path = calendarId == null || calendarId.isEmpty
        ? '/me/calendarView'
        : '/me/calendars/${Uri.encodeComponent(calendarId)}/calendarView';
    final initial = Uri.parse('${AppConfig.microsoftGraphBase}$path').replace(
      queryParameters: {
        r'$select':
            'id,subject,bodyPreview,start,end,isAllDay,location,showAs,isCancelled,seriesMasterId,type,recurrence,onlineMeetingUrl,attendees,organizer,lastModifiedDateTime',
        'startDateTime': startUtc.toUtc().toIso8601String(),
        'endDateTime': endUtc.toUtc().toIso8601String(),
      },
    );
    return _paginate(initial, headers, MsEvent.fromMap);
  }

  @override
  Future<List<MsTodoList>> listTodoLists() async {
    final headers = await _headers();
    final initial = Uri.parse('${AppConfig.microsoftGraphBase}/me/todo/lists')
        .replace(
          queryParameters: const {
            r'$select': 'id,displayName,wellknownListName',
          },
        );
    return _paginate(initial, headers, MsTodoList.fromMap);
  }

  @override
  Future<List<MsTodoTask>> listTodoTasks(String listId) async {
    final headers = await _headers();
    final initial =
        Uri.parse(
          '${AppConfig.microsoftGraphBase}/me/todo/lists/${Uri.encodeComponent(listId)}/tasks',
        ).replace(
          queryParameters: const {
            r'$select':
                'id,title,body,importance,status,dueDateTime,completedDateTime,createdDateTime,lastModifiedDateTime',
          },
        );
    return _paginate(initial, headers, MsTodoTask.fromMap);
  }
}
