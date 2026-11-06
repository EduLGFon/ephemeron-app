// Static timeline chrome: hour gutter, day headers, all-day strip.
// Pure presentation; dragging and tapping arrive via callbacks.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/habits/habit_calendar_entry.dart';
import '../habit_calendar_marker.dart';

import '../../../../core/time/device_date_format.dart';
import '../../../../core/time/time.dart';
import '../../../../data/drift/app_database.dart';
import '../../application/calendar_providers.dart';
import 'timeline_utils.dart';

part 'timeline_chrome/hour_gutter.dart';
part 'timeline_chrome/day_header.dart';
part 'timeline_chrome/all_day_strip.dart';
