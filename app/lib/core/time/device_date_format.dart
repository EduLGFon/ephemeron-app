// Device/app-locale aware date formatting helpers. All user-facing dates
// should go through these so they follow the device format instead of a
// hard-coded pattern. Storage formats (ISO date keys) are unaffected.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DeviceDateFormat {
  static String locale(BuildContext context) =>
      Localizations.localeOf(context).toString();

  static String date(BuildContext context, DateTime d) =>
      DateFormat.yMMMd(locale(context)).format(d);

  static String dateTime(BuildContext context, DateTime d) =>
      DateFormat.yMMMd(locale(context)).add_Hm().format(d);

  static String time(BuildContext context, DateTime d) =>
      DateFormat.Hm(locale(context)).format(d);

  static String monthYear(BuildContext context, DateTime d) =>
      DateFormat.yMMM(locale(context)).format(d);

  static String monthName(BuildContext context, int month) =>
      DateFormat.MMMM(locale(context)).format(DateTime(2000, month));

  static String shortMonthName(BuildContext context, int month) =>
      DateFormat.MMM(locale(context)).format(DateTime(2000, month));

  static String weekday(BuildContext context, DateTime d) =>
      DateFormat.E(locale(context)).format(d);

  static String weekdayFull(BuildContext context, DateTime d) =>
      DateFormat.EEEE(locale(context)).format(d);

  static DateFormat yMMMd(BuildContext context) =>
      DateFormat.yMMMd(locale(context));

  static DateFormat yMMM(BuildContext context) =>
      DateFormat.yMMM(locale(context));

  static DateFormat hm(BuildContext context) => DateFormat.Hm(locale(context));

  static DateFormat e(BuildContext context) => DateFormat.E(locale(context));

  static DateFormat eeee(BuildContext context) =>
      DateFormat.EEEE(locale(context));

  static DateFormat mmmm(BuildContext context) =>
      DateFormat.MMMM(locale(context));

  static DateFormat mmm(BuildContext context) =>
      DateFormat.MMM(locale(context));

  static String dateIso(BuildContext context, String iso) {
    try {
      return date(context, DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }
}
