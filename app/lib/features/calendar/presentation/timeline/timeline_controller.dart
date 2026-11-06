// Interaction state for the timeline: scroll position, zoom, pinch,
// tap-empty-to-create, and long-press drag-to-move with 15-minute snapping.
// Mixed into the timeline view's state; the state supplies [anchor] and
// [dayCount] from its widget.
// Split across `timeline_controller/` parts; this file stays the stable
// import path and owns the public constants and the [TimelineInteraction]
// mixin (declared in `timeline_controller/core.dart`).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../data/repositories/event_repository.dart';
import '../../application/calendar_providers.dart';
import '../../../settings/application/settings_providers.dart';
import '../event_editor_sheet.dart';
import '../scope_sheet.dart';
import 'timeline_utils.dart';

part 'timeline_controller/core.dart';
part 'timeline_controller/swipe.dart';
part 'timeline_controller/scale.dart';
part 'timeline_controller/drag.dart';

const double timelineBaseHourHeight = 56;
const double timelineGutterWidth = 48;
const double timelineMinScale = 0.5;
const double timelineMaxScale = 3.0;
