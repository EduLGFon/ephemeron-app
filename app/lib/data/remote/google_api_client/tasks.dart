part of '../google_api_client.dart';

mixin _GoogleApiTasksOps on _GoogleApiBase {
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
  Future<Map<String, dynamic>> taskListCreate(String title) async {
    final r = await _http.post(
      Uri.parse('${AppConfig.tasksApiBase}/users/@me/lists'),
      headers: await _headers(),
      body: jsonEncode({'title': title}),
    );
    if (r.statusCode != 200) _throw(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> taskListPatch(
    String listId,
    String title,
  ) async {
    final r = await _http.patch(
      Uri.parse(
        '${AppConfig.tasksApiBase}/users/@me/lists/${Uri.encodeComponent(listId)}',
      ),
      headers: await _headers(),
      body: jsonEncode({'title': title}),
    );
    if (r.statusCode != 200) _throw(r);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  @override
  Future<void> taskListDelete(String listId) async {
    final r = await _http.delete(
      Uri.parse(
        '${AppConfig.tasksApiBase}/users/@me/lists/${Uri.encodeComponent(listId)}',
      ),
      headers: await _headers(),
    );
    if (r.statusCode != 204 && r.statusCode != 200) _throw(r);
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
      all.addAll(((body['items'] as List?) ?? []).cast<Map<String, dynamic>>());
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
  Future<Map<String, dynamic>> taskMove(
    String sourceTaskListId,
    String taskId,
    String destinationTaskListId,
  ) async {
    final r = await _http.post(
      Uri.parse(
        '${AppConfig.tasksApiBase}/lists/${Uri.encodeComponent(sourceTaskListId)}/tasks/${Uri.encodeComponent(taskId)}/move',
      ).replace(
        queryParameters: {'destinationTasklist': destinationTaskListId},
      ),
      headers: await _headers(),
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
