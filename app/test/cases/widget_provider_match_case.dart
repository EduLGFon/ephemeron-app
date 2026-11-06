import 'package:ephemeron/data/services/home_widget_data_binder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('widgetProviderMatches handles short and qualified names', () {
    expect(
      widgetProviderMatches(
        'WeekCalendarWidgetProvider',
        'WeekCalendarWidgetProvider',
      ),
      isTrue,
    );
    expect(
      widgetProviderMatches(
        'com.spotnik.ephemeron.WeekCalendarWidgetProvider',
        'WeekCalendarWidgetProvider',
      ),
      isTrue,
    );
    expect(widgetProviderMatches(null, 'WeekCalendarWidgetProvider'), isFalse);
    expect(
      widgetProviderMatches(
        'UnrelatedWidgetProvider',
        'WeekCalendarWidgetProvider',
      ),
      isFalse,
    );
    expect(
      widgetProviderMatches(
        'WeekCalendarWidgetProvider',
        'MonthCalendarWidgetProvider',
      ),
      isFalse,
    );
    expect(
      widgetProviderMatches(
        'com.spotnik.ephemeron.WeekCalendarWidgetProviderExtra',
        'WeekCalendarWidgetProvider',
      ),
      isFalse,
    );
  });
}
