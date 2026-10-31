import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ephemeron/data/services/home_widget_service.dart';
/// Best-effort foreground refresh of home-screen widgets. Pushes a small
/// placeholder payload for every widget type so newly pinned widgets are
/// never blank. Feature-specific data can override these via
/// [HomeWidgetService.updateByPrefix].
class HomeWidgetRefreshService {
  HomeWidgetRefreshService(this._service);
  final HomeWidgetService _service;

  Future<void> refreshDefaults() async {
    for (final w in homeWidgets) {
      await _service.updateByPrefix(
        keyPrefix: w.keyPrefix,
        title: w.keyPrefix.replaceAll('_', ' '),
        body: 'Open ephemeron for details.',
      );
    }
  }
}

final homeWidgetRefreshServiceProvider =
    Provider<HomeWidgetRefreshService>((ref) {
  return HomeWidgetRefreshService(ref.read(homeWidgetServiceProvider));
});