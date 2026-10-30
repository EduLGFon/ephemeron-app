// Shared Google Calendar color palette (colorId -> Color). Single source
// of truth used by the editor and timeline views.
import 'package:flutter/material.dart';

const Map<String, Color> googleCalendarColors = <String, Color>{
  '1': Color(0xFF7986CB),
  '2': Color(0xFF33B679),
  '3': Color(0xFF8E24AA),
  '4': Color(0xFFE67C73),
  '5': Color(0xFFF6BF26),
  '6': Color(0xFF3F51B5),
  '7': Color(0xFF039BE5),
  '8': Color(0xFF0B8043),
  '9': Color(0xFFD50000),
  '10': Color(0xFF303F9F),
  '11': Color(0xFF616161),
};

Color googleCalendarColor(String id, {Color fallback = Colors.blue}) =>
    googleCalendarColors[id] ?? fallback;
