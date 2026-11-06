// N-day / day timeline: hour gutter, day headers, all-day strip,
// current-time line, tap-empty to create, tap event for details.
// Composes the chrome, painters, event blocks, and interaction mixin;
// overlap layout lives in timeline_layout.dart.
// Split across `timeline_view/` parts (U10b); this file is the stable
// import path and owns the public [TimelineView] widget.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/drift/app_database.dart';
import '../../../../domain/habits/habit_calendar_entry.dart';
import '../../application/calendar_providers.dart';
import '../../application/calendar_state.dart';
import '../../../settings/application/settings_providers.dart';
import '../event_details_sheet.dart';
import '../habit_action_sheet.dart';
import '../task_action_sheet.dart';
import 'habit_timeline_block.dart';
import 'timeline_chrome.dart';
import 'timeline_controller.dart';
import 'timeline_event_block.dart';
import 'timeline_now_controller.dart';
import 'timeline_painters.dart';
import 'timeline_utils.dart';

part 'timeline_view/state.dart';
part 'timeline_view/build.dart';
part 'timeline_view/grid.dart';

class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key, required this.anchor, required this.dayCount});

  final DateTime anchor;
  final int dayCount;

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView>
    with
        TimelineInteraction,
        TimelineSwipe,
        TimelineScale,
        TimelineDrag,
        SingleTickerProviderStateMixin,
        WidgetsBindingObserver,
        _TimelineViewStateMixin {}
