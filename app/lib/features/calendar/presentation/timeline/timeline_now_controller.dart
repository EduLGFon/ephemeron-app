// Holds the "now" instant used to paint the timeline current-time line.
// Refreshed on visibility signals (resume, tab switch, route return, ticker
// mode) instead of a per-second timer to keep battery impact near zero.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class TimelineNowController extends ValueNotifier<DateTime> {
  TimelineNowController({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super((clock ?? DateTime.now)());

  final DateTime Function() _clock;

  DateTime get now => value;

  void refresh() => value = _clock();
}

final timelineNowControllerProvider = Provider<TimelineNowController>((ref) {
  final controller = TimelineNowController();
  ref.onDispose(controller.dispose);
  return controller;
});
